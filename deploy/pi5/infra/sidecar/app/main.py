"""Embedding + reranker sidecar.

Default models: BGE-M3 for embeddings, Qwen3-Reranker-0.6B for reranking.
Both are env-overridable (``EMBED_MODEL`` / ``RERANK_MODEL``).

Exposes:
  - GET  /healthz
  - POST /v1/embeddings  (OpenAI-compatible)
  - POST /v1/rerank      (custom)

Models load lazily on first request (guarded by an asyncio.Lock) and are
warmed up in a background task at startup so the first real request is fast.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import sys
import time
from contextlib import asynccontextmanager
from typing import Any, AsyncIterator

import numpy as np
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Logging (structured JSON)
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
            if key in ("args", "msg", "levelname", "name", "exc_info", "exc_text",
                      "stack_info", "lineno", "pathname", "filename", "module",
                      "msecs", "relativeCreated", "thread", "threadName",
                      "processName", "process", "created", "funcName",
                      "levelno"):
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
log = logging.getLogger("sidecar")


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

EMBED_MODEL = os.environ.get("EMBED_MODEL", "BAAI/bge-m3")
RERANK_MODEL = os.environ.get("RERANK_MODEL", "Qwen/Qwen3-Reranker-0.6B")
MODEL_CACHE = os.environ.get("MODEL_CACHE", "/cache")
EMBED_BATCH_SIZE = int(os.environ.get("EMBED_BATCH_SIZE", "32"))
EMBED_MAX_TOKENS = int(os.environ.get("EMBED_MAX_TOKENS", "8192"))


def _is_qwen3_family(name: str) -> bool:
    """Whether the loaded embed model expects the Qwen3-style query prefix."""
    lower = name.lower()
    return "qwen3" in lower or "octen" in lower


QWEN3_QUERY_PREFIX = (
    "Instruct: Given a web search query, retrieve relevant passages that "
    "answer the query\nQuery: "
)


def _resolve_device(override: str | None = None) -> str:
    if override:
        return override.strip().lower()
    try:
        import torch

        return "cuda" if torch.cuda.is_available() else "cpu"
    except Exception:  # pragma: no cover - torch import failure is fatal elsewhere
        return "cpu"


# DEVICE is the legacy default; per-component overrides take precedence.
DEVICE = _resolve_device()
EMBED_DEVICE = _resolve_device(os.environ.get("EMBED_DEVICE"))
RERANK_DEVICE = _resolve_device(os.environ.get("RERANK_DEVICE"))
# When false, the reranker model is never loaded — useful for a CPU-only
# embed-only sidecar to skip ~1-2 GB of weights and overhead. The
# /v1/rerank endpoint will 503 in that mode.
LOAD_RERANK_MODEL = (
    os.environ.get("LOAD_RERANK_MODEL", "true").strip().lower()
    not in ("0", "false", "no", "off")
)
# Optional CPU quantization for the reranker. ``int8`` applies PyTorch
# dynamic quantization to Linear modules — halves weight memory so that
# per-layer working set fits in CPU L3 on chips with large caches
# (EPYC Milan-X, Genoa-X). Ignored on cuda.
RERANK_QUANT = os.environ.get("RERANK_QUANT", "none").strip().lower()


def _cpu_thread_count() -> int | None:
    raw = os.environ.get("CPU_THREADS", "").strip()
    if not raw:
        return None
    try:
        return max(1, int(raw))
    except ValueError:
        return None


def _maybe_set_cpu_threads() -> None:
    n = _cpu_thread_count()
    if n is None:
        return
    try:
        import torch
        torch.set_num_threads(n)
    except Exception:
        pass


_maybe_set_cpu_threads()


# ---------------------------------------------------------------------------
# Lazy model singletons
# ---------------------------------------------------------------------------

_embed_model: Any | None = None
_rerank_model: Any | None = None
_embed_lock = asyncio.Lock()
_rerank_lock = asyncio.Lock()


async def get_embed_model() -> Any:
    global _embed_model
    if _embed_model is not None:
        return _embed_model
    async with _embed_lock:
        if _embed_model is not None:
            return _embed_model
        log.info("loading embed model", extra={"model": EMBED_MODEL, "device": EMBED_DEVICE})
        loop = asyncio.get_running_loop()
        _embed_model = await loop.run_in_executor(None, _load_embed_model_sync)
        log.info("embed model loaded", extra={"model": EMBED_MODEL})
    return _embed_model


def _load_embed_model_sync() -> Any:
    import torch
    from sentence_transformers import SentenceTransformer

    model_kwargs: dict[str, Any] = {}
    if EMBED_DEVICE == "cuda":
        model_kwargs["torch_dtype"] = torch.float16
    return SentenceTransformer(
        EMBED_MODEL,
        device=EMBED_DEVICE,
        cache_folder=MODEL_CACHE,
        model_kwargs=model_kwargs,
    )


async def get_rerank_model() -> Any:
    if not LOAD_RERANK_MODEL:
        raise HTTPException(
            status_code=503,
            detail="rerank disabled on this sidecar (LOAD_RERANK_MODEL=false)",
        )
    global _rerank_model
    if _rerank_model is not None:
        return _rerank_model
    async with _rerank_lock:
        if _rerank_model is not None:
            return _rerank_model
        log.info("loading rerank model", extra={"model": RERANK_MODEL, "device": RERANK_DEVICE})
        loop = asyncio.get_running_loop()
        _rerank_model = await loop.run_in_executor(None, _load_rerank_model_sync)
        log.info("rerank model loaded", extra={"model": RERANK_MODEL})
    return _rerank_model


def _load_rerank_model_sync() -> Any:
    # FlagEmbedding's FlagReranker collides with transformers ≥ 5.x
    # (XLMRobertaTokenizer.prepare_for_model was removed). sentence-
    # transformers' CrossEncoder is actively maintained against the
    # current transformers and loads the BGE / Qwen3 reranker families
    # natively (predict() does the right thing for both).
    import torch
    from sentence_transformers import CrossEncoder

    model_kwargs: dict[str, Any] = {}
    if RERANK_DEVICE == "cuda":
        model_kwargs["torch_dtype"] = torch.float16
    ce = CrossEncoder(
        RERANK_MODEL,
        device=RERANK_DEVICE,
        cache_folder=MODEL_CACHE,
        model_kwargs=model_kwargs,
    )

    # Optional CPU-only INT8 dynamic quantization. Only Linear modules
    # are quantized — activations stay FP32. The win on Zen-3-style CPUs
    # is memory bandwidth: per-layer weights at INT8 (~22 MB for a 0.6B
    # split across 28 layers) fit in 3D V-Cache's per-CCD L3, vs ~44 MB
    # at FP16 which spills to DRAM.
    if RERANK_DEVICE == "cpu" and RERANK_QUANT == "int8":
        inner = getattr(ce, "model", None)
        if inner is None:
            log.warning("rerank quantize: CrossEncoder.model missing, skipping")
        else:
            log.info("quantizing rerank model to int8 (dynamic, Linear only)")
            quantized = torch.quantization.quantize_dynamic(
                inner, {torch.nn.Linear}, dtype=torch.qint8
            )
            ce.model = quantized
            log.info("rerank int8 quantization complete")

    return ce


# ---------------------------------------------------------------------------
# Pydantic schemas
# ---------------------------------------------------------------------------


class EmbeddingsRequest(BaseModel):
    model: str = Field(default=EMBED_MODEL)
    input: str | list[str]
    encoding_format: str | None = Field(default="float")
    dimensions: int | None = None
    # Qwen3-Embedding-family models (and Octen, which is LoRA on top) were
    # trained with asymmetric prompting: queries get an instruction prefix,
    # documents get raw text. Symmetric encoders (BGE-M3) ignore this.
    input_type: str | None = Field(default=None, description="\"query\" | \"document\" | None")


class EmbeddingItem(BaseModel):
    object: str = "embedding"
    embedding: list[float]
    index: int


class EmbeddingsUsage(BaseModel):
    prompt_tokens: int = 0
    total_tokens: int = 0


class EmbeddingsResponse(BaseModel):
    object: str = "list"
    data: list[EmbeddingItem]
    model: str
    usage: EmbeddingsUsage


class RerankRequest(BaseModel):
    model: str | None = Field(default=RERANK_MODEL)
    query: str
    documents: list[str]
    top_k: int | None = None


class RerankResultItem(BaseModel):
    index: int
    score: float


class RerankResponse(BaseModel):
    results: list[RerankResultItem]
    model: str


class HealthResponse(BaseModel):
    ok: bool
    device: str
    embed_loaded: bool
    rerank_loaded: bool


# ---------------------------------------------------------------------------
# Lifespan: warm up models in the background
# ---------------------------------------------------------------------------


async def _warmup() -> None:
    try:
        await get_embed_model()
        if LOAD_RERANK_MODEL:
            await get_rerank_model()
        log.info("warmup complete")
    except Exception:  # pragma: no cover
        log.exception("warmup failed")


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
    log.info(
        "sidecar starting",
        extra={
            "embed": EMBED_MODEL, "embed_device": EMBED_DEVICE,
            "rerank": RERANK_MODEL if LOAD_RERANK_MODEL else "(disabled)",
            "rerank_device": RERANK_DEVICE if LOAD_RERANK_MODEL else "n/a",
            "rerank_quant": RERANK_QUANT if LOAD_RERANK_MODEL else "n/a",
            "cpu_threads": _cpu_thread_count(),
        },
    )
    task = asyncio.create_task(_warmup(), name="sidecar-warmup")
    try:
        yield
    finally:
        task.cancel()
        try:
            await task
        except (asyncio.CancelledError, Exception):  # pragma: no cover
            pass


app = FastAPI(title="deepresearch-sidecar", version="0.1.0", lifespan=lifespan)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@app.get("/healthz", response_model=HealthResponse)
async def healthz() -> HealthResponse:
    # Surface the embed device (the most operationally interesting datum);
    # rerank_loaded stays accurate even when LOAD_RERANK_MODEL=false (then
    # it just reads ``not loaded``).
    return HealthResponse(
        ok=True,
        device=str(EMBED_DEVICE),
        embed_loaded=_embed_model is not None,
        rerank_loaded=_rerank_model is not None,
    )


def _truncate_inputs(inputs: list[str], max_chars: int) -> list[str]:
    # Cheap char-based guard; transformer truncates to model max internally too.
    return [x if len(x) <= max_chars else x[:max_chars] for x in inputs]


def _approx_token_count(items: list[str]) -> int:
    # Cheap proxy: ~4 chars per token. Avoids loading a tokenizer just for the
    # usage block in the OpenAI response.
    return sum(max(1, len(x) // 4) for x in items)


@app.post("/v1/embeddings", response_model=EmbeddingsResponse)
async def embeddings(req: EmbeddingsRequest) -> EmbeddingsResponse:
    if isinstance(req.input, str):
        inputs = [req.input]
    else:
        inputs = list(req.input)

    if not inputs:
        raise HTTPException(status_code=400, detail="input must not be empty")

    inputs = _truncate_inputs(inputs, max_chars=EMBED_MAX_TOKENS * 4)

    # Apply Qwen3-style query prefix when the loaded model expects it.
    # BGE-M3 / symmetric encoders pass through unchanged.
    if req.input_type == "query" and _is_qwen3_family(EMBED_MODEL):
        inputs = [QWEN3_QUERY_PREFIX + x for x in inputs]

    model = await get_embed_model()
    loop = asyncio.get_running_loop()

    def _encode() -> np.ndarray:
        out = model.encode(
            inputs,
            batch_size=EMBED_BATCH_SIZE,
            normalize_embeddings=True,
            convert_to_numpy=True,
            show_progress_bar=False,
        )
        return np.asarray(out, dtype=np.float32)

    try:
        vectors = await loop.run_in_executor(None, _encode)
    except Exception as exc:
        log.exception("embedding failed")
        raise HTTPException(status_code=500, detail=f"embedding failed: {exc}") from exc

    if req.dimensions is not None and req.dimensions > 0 and req.dimensions < vectors.shape[1]:
        vectors = vectors[:, : req.dimensions]
        # re-normalize after truncation so cosine sim stays meaningful
        norms = np.linalg.norm(vectors, axis=1, keepdims=True)
        norms[norms == 0] = 1.0
        vectors = vectors / norms

    items = [
        EmbeddingItem(embedding=vec.tolist(), index=i)
        for i, vec in enumerate(vectors)
    ]
    tokens = _approx_token_count(inputs)
    return EmbeddingsResponse(
        data=items,
        model=req.model or EMBED_MODEL,
        usage=EmbeddingsUsage(prompt_tokens=tokens, total_tokens=tokens),
    )


@app.post("/v1/rerank", response_model=RerankResponse)
async def rerank(req: RerankRequest) -> RerankResponse:
    if not req.documents:
        raise HTTPException(status_code=400, detail="documents must not be empty")

    model = await get_rerank_model()
    pairs = [[req.query, doc] for doc in req.documents]

    loop = asyncio.get_running_loop()

    def _score() -> list[float]:
        # CrossEncoder.predict normalises across both BGE-style classification
        # heads and Qwen3-style generative yes/no logit-diffs. Sigmoid maps
        # the output to [0, 1] so downstream consumers can treat it as a
        # confidence regardless of the underlying reranker family.
        import torch

        raw = model.predict(pairs, activation_fn=torch.nn.Sigmoid())
        try:
            return [float(x) for x in raw]
        except TypeError:
            return [float(raw)]

    try:
        scores = await loop.run_in_executor(None, _score)
    except Exception as exc:
        log.exception("rerank failed")
        raise HTTPException(status_code=500, detail=f"rerank failed: {exc}") from exc

    indexed = sorted(
        ((i, float(s)) for i, s in enumerate(scores)),
        key=lambda t: t[1],
        reverse=True,
    )
    if req.top_k is not None and req.top_k > 0:
        indexed = indexed[: req.top_k]

    results = [RerankResultItem(index=i, score=s) for i, s in indexed]
    return RerankResponse(results=results, model=req.model or RERANK_MODEL)
