"""UMAP + HDBSCAN clustering sidecar for SkillRAE.

Replaces the K-means clustering that previously ran inside the Go
``skills-rae`` worker. Two endpoints:

  POST /v1/cluster   bulk: take all skill embeddings, return a
                     hierarchical community tree + noise list
  POST /v1/assign    incremental: take one skill embedding + the
                     current leaf-community representatives, return the
                     nearest community (or noise=true if below
                     ASSIGN_MIN_SIM)
  GET  /healthz      probe

Design notes
------------
* HDBSCAN's "extract clusters at a different epsilon" trick gives us a
  cheap hierarchy: run HDBSCAN once with the default EOM selection
  (call that the leaf level), then extract DBSCAN-style assignments at
  two larger epsilon values to get medium + broad levels. Each level
  is a flat partition of the corpus into clusters; parent linkage is
  derived from "which broader-level cluster do most of this finer-level
  cluster's members belong to."
* UMAP reduces 1024-dim bge-m3 vectors to 50 dims before clustering.
  HDBSCAN's density metric is sensitive to high-dim sparsity and UMAP
  is the standard preprocessing step in production pipelines.
* All assignments are computed in process memory; nothing here writes
  to postgres. The Go caller takes the structured response and does
  the SQL persistence in one transaction.
"""

from __future__ import annotations

import json
import logging
import os
import sys
import time
import uuid
from contextlib import asynccontextmanager
from typing import Any, AsyncIterator

import hdbscan
import numpy as np
import umap
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from .registry import WorkerRegistration


# ---------------------------------------------------------------------------
# Logging (structured JSON, mirrors the bge-m3 sidecar)
# ---------------------------------------------------------------------------


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "ts": time.time(),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        for key, value in record.__dict__.items():
            if key in (
                "args", "msg", "levelname", "name", "exc_info", "exc_text",
                "stack_info", "lineno", "pathname", "filename", "module",
                "msecs", "relativeCreated", "thread", "threadName",
                "processName", "process", "created", "funcName", "levelno",
            ):
                continue
            try:
                json.dumps(value)
                payload[key] = value
            except (TypeError, ValueError):
                payload[key] = repr(value)
        return json.dumps(payload, ensure_ascii=False)


def _configure_logging() -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())


_configure_logging()
log = logging.getLogger("cluster-sidecar")


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

UMAP_DIMS = int(os.environ.get("UMAP_DIMS", "50"))
UMAP_NEIGHBORS = int(os.environ.get("UMAP_NEIGHBORS", "15"))
UMAP_MIN_DIST = float(os.environ.get("UMAP_MIN_DIST", "0.0"))
UMAP_METRIC = os.environ.get("UMAP_METRIC", "cosine")

HDBSCAN_MIN_CLUSTER_SIZE = int(os.environ.get("HDBSCAN_MIN_CLUSTER_SIZE", "15"))
HDBSCAN_MIN_SAMPLES = int(os.environ.get("HDBSCAN_MIN_SAMPLES", "5"))
HDBSCAN_SELECTION = os.environ.get("HDBSCAN_SELECTION", "eom")  # "eom" or "leaf"

# Epsilon multipliers used to extract broader hierarchy levels from the
# same HDBSCAN run. The default EOM selection is the leaf level. We then
# cut the condensed tree at two larger epsilons (relative to the
# corpus's median pairwise distance in the reduced space) to derive
# the medium and broad levels.
HIERARCHY_EPS_MULTIPLIERS = (1.5, 3.0)

ASSIGN_MIN_SIM = float(os.environ.get("ASSIGN_MIN_SIM", "0.4"))


# ---------------------------------------------------------------------------
# Request / response schemas
# ---------------------------------------------------------------------------


class ClusterRequest(BaseModel):
    vectors: list[list[float]] = Field(..., description="N x D matrix of embeddings")
    skill_ids: list[str] = Field(..., description="N skill UUIDs (string form)")


class ClusterCommunityOut(BaseModel):
    temp_id: int = Field(..., description="0-based id, unique within this response")
    parent_temp_id: int | None = Field(None, description="id of broader-level parent, or null at root level")
    level: int = Field(..., description="0 = broadest, max_level = leaf")
    member_skill_ids: list[str] = Field(..., description="skills assigned to this community at this level")
    representative_indices: list[int] = Field(
        ...,
        description="indices into the original vectors array of the 3 members closest to the centroid",
    )


class ClusterResponse(BaseModel):
    tree_id: str
    levels: int
    communities: list[ClusterCommunityOut]
    noise_skill_ids: list[str]
    diagnostics: dict[str, Any] = Field(default_factory=dict)


class AssignCommunity(BaseModel):
    id: str
    embedding: list[float]


class AssignRequest(BaseModel):
    vector: list[float]
    communities: list[AssignCommunity]


class AssignResponse(BaseModel):
    community_id: str | None
    similarity: float
    noise: bool


# ---------------------------------------------------------------------------
# Lifespan
# ---------------------------------------------------------------------------


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    log.info("cluster-sidecar ready", extra={
        "umap_dims": UMAP_DIMS,
        "min_cluster_size": HDBSCAN_MIN_CLUSTER_SIZE,
        "min_samples": HDBSCAN_MIN_SAMPLES,
        "selection": HDBSCAN_SELECTION,
    })
    # Best-effort: self-register in evo.workers so the dashboard's
    # Nodes UI sees us. WORKERS_REGISTRY_DSN unset is a clean no-op.
    registration = await WorkerRegistration.start()
    try:
        yield
    finally:
        if registration is not None:
            await registration.stop()


app = FastAPI(lifespan=lifespan)


# ---------------------------------------------------------------------------
# /healthz
# ---------------------------------------------------------------------------


@app.get("/healthz")
async def healthz() -> dict[str, Any]:
    return {"ok": True, "service": "cluster-sidecar"}


# ---------------------------------------------------------------------------
# /v1/cluster
# ---------------------------------------------------------------------------


def _l2_normalize(matrix: np.ndarray) -> np.ndarray:
    """Row-wise L2 normalise so cosine == dot product later."""
    norms = np.linalg.norm(matrix, axis=1, keepdims=True)
    norms[norms == 0] = 1.0
    return matrix / norms


def _representatives_for(member_indices: np.ndarray, reduced: np.ndarray, top: int = 3) -> list[int]:
    """Pick the `top` members closest to the cluster's centroid in reduced space."""
    if member_indices.size == 0:
        return []
    sub = reduced[member_indices]
    centroid = sub.mean(axis=0)
    diffs = sub - centroid
    dists = np.linalg.norm(diffs, axis=1)
    order = np.argsort(dists)
    picked = member_indices[order[:top]].tolist()
    return picked


def _build_level(
    labels: np.ndarray,
    reduced: np.ndarray,
    skill_ids: list[str],
    level: int,
) -> tuple[list[ClusterCommunityOut], list[str]]:
    """Build community rows for one level + return noise skill_ids if level == leaf."""
    communities: list[ClusterCommunityOut] = []
    noise: list[str] = []
    unique = sorted({int(lbl) for lbl in labels})
    for lbl in unique:
        if lbl < 0:
            # HDBSCAN noise; only surfaced at the leaf level.
            continue
        member_idx = np.where(labels == lbl)[0]
        member_skill_ids = [skill_ids[i] for i in member_idx]
        reps = _representatives_for(member_idx, reduced)
        communities.append(
            ClusterCommunityOut(
                temp_id=0,  # rewritten below after we merge across levels
                parent_temp_id=None,
                level=level,
                member_skill_ids=member_skill_ids,
                representative_indices=reps,
            )
        )
    return communities, noise


def _link_parents(
    leaf_communities: list[ClusterCommunityOut],
    parent_communities: list[ClusterCommunityOut],
    skill_to_parent_temp: dict[str, int],
) -> None:
    """Set parent_temp_id on each leaf based on majority-membership in the parent level."""
    for leaf in leaf_communities:
        votes: dict[int, int] = {}
        for sid in leaf.member_skill_ids:
            p = skill_to_parent_temp.get(sid)
            if p is None:
                continue
            votes[p] = votes.get(p, 0) + 1
        if not votes:
            leaf.parent_temp_id = None
            continue
        leaf.parent_temp_id = max(votes.items(), key=lambda kv: kv[1])[0]


def _cluster_hierarchy(
    vectors: np.ndarray,
    skill_ids: list[str],
) -> tuple[list[ClusterCommunityOut], list[str], dict[str, Any]]:
    """Run UMAP + HDBSCAN + extract a 3-level hierarchy."""
    t0 = time.time()

    # --- UMAP ---
    reducer = umap.UMAP(
        n_components=UMAP_DIMS,
        n_neighbors=min(UMAP_NEIGHBORS, max(2, len(vectors) - 1)),
        min_dist=UMAP_MIN_DIST,
        metric=UMAP_METRIC,
        random_state=42,
    )
    reduced = reducer.fit_transform(vectors)
    t_umap = time.time() - t0

    # --- HDBSCAN ---
    clusterer = hdbscan.HDBSCAN(
        min_cluster_size=HDBSCAN_MIN_CLUSTER_SIZE,
        min_samples=HDBSCAN_MIN_SAMPLES,
        cluster_selection_method=HDBSCAN_SELECTION,
        prediction_data=True,
        core_dist_n_jobs=1,
    )
    leaf_labels = clusterer.fit_predict(reduced)
    t_hdbscan = time.time() - t_umap - t0

    # Pick epsilons relative to a robust scale: median distance to 5th
    # nearest neighbour in reduced space.
    if len(reduced) > 6:
        from scipy.spatial import cKDTree

        tree = cKDTree(reduced)
        _, idx = tree.query(reduced, k=6)
        nn5 = np.linalg.norm(reduced - reduced[idx[:, 5]], axis=1)
        scale = float(np.median(nn5))
    else:
        scale = 1.0

    # --- Build communities per level ---
    leaf_comms, _ = _build_level(leaf_labels, reduced, skill_ids, level=2)
    noise_indices = np.where(leaf_labels < 0)[0]
    noise_skill_ids = [skill_ids[i] for i in noise_indices]

    mid_labels = clusterer.single_linkage_tree_.get_clusters(
        cut_distance=scale * HIERARCHY_EPS_MULTIPLIERS[0],
        min_cluster_size=HDBSCAN_MIN_CLUSTER_SIZE,
    )
    broad_labels = clusterer.single_linkage_tree_.get_clusters(
        cut_distance=scale * HIERARCHY_EPS_MULTIPLIERS[1],
        min_cluster_size=HDBSCAN_MIN_CLUSTER_SIZE,
    )

    mid_comms, _ = _build_level(mid_labels, reduced, skill_ids, level=1)
    broad_comms, _ = _build_level(broad_labels, reduced, skill_ids, level=0)

    # --- Assign temp_ids globally + link parents ---
    next_id = 0
    for c in broad_comms:
        c.temp_id = next_id
        next_id += 1
    for c in mid_comms:
        c.temp_id = next_id
        next_id += 1
    for c in leaf_comms:
        c.temp_id = next_id
        next_id += 1

    broad_member_to_temp = {sid: c.temp_id for c in broad_comms for sid in c.member_skill_ids}
    _link_parents(mid_comms, broad_comms, broad_member_to_temp)

    mid_member_to_temp = {sid: c.temp_id for c in mid_comms for sid in c.member_skill_ids}
    _link_parents(leaf_comms, mid_comms, mid_member_to_temp)

    all_comms = broad_comms + mid_comms + leaf_comms

    diagnostics = {
        "umap_ms": int(t_umap * 1000),
        "hdbscan_ms": int(t_hdbscan * 1000),
        "n_skills": len(skill_ids),
        "broad_count": len(broad_comms),
        "mid_count": len(mid_comms),
        "leaf_count": len(leaf_comms),
        "noise_count": len(noise_skill_ids),
        "scale": scale,
    }
    return all_comms, noise_skill_ids, diagnostics


@app.post("/v1/cluster", response_model=ClusterResponse)
async def cluster(req: ClusterRequest) -> ClusterResponse:
    if len(req.vectors) != len(req.skill_ids):
        raise HTTPException(400, f"vectors/skill_ids length mismatch: {len(req.vectors)} vs {len(req.skill_ids)}")
    if len(req.vectors) < HDBSCAN_MIN_CLUSTER_SIZE * 2:
        raise HTTPException(
            400,
            f"too few skills to cluster: got {len(req.vectors)}, need at least {HDBSCAN_MIN_CLUSTER_SIZE * 2}",
        )

    vectors = np.array(req.vectors, dtype=np.float32)
    if vectors.ndim != 2:
        raise HTTPException(400, "vectors must be a 2D array")
    vectors = _l2_normalize(vectors)

    communities, noise, diagnostics = _cluster_hierarchy(vectors, req.skill_ids)

    tree_id = str(uuid.uuid4())
    log.info("cluster done", extra={"tree_id": tree_id, **diagnostics})
    return ClusterResponse(
        tree_id=tree_id,
        levels=3,
        communities=communities,
        noise_skill_ids=noise,
        diagnostics=diagnostics,
    )


# ---------------------------------------------------------------------------
# /v1/assign
# ---------------------------------------------------------------------------


@app.post("/v1/assign", response_model=AssignResponse)
async def assign(req: AssignRequest) -> AssignResponse:
    if not req.communities:
        return AssignResponse(community_id=None, similarity=0.0, noise=True)

    q = np.array(req.vector, dtype=np.float32)
    qn = np.linalg.norm(q)
    if qn == 0:
        raise HTTPException(400, "zero vector")
    q = q / qn

    embeddings = np.array([c.embedding for c in req.communities], dtype=np.float32)
    norms = np.linalg.norm(embeddings, axis=1, keepdims=True)
    norms[norms == 0] = 1.0
    embeddings = embeddings / norms

    sims = embeddings @ q
    best_idx = int(np.argmax(sims))
    best_sim = float(sims[best_idx])

    if best_sim < ASSIGN_MIN_SIM:
        return AssignResponse(community_id=None, similarity=best_sim, noise=True)
    return AssignResponse(
        community_id=req.communities[best_idx].id,
        similarity=best_sim,
        noise=False,
    )
