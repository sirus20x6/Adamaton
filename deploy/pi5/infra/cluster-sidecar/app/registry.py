"""Self-registration into evo.workers so the cluster-sidecar shows up
in the dashboard's Nodes UI.

Mirrors the Go ``core/workerregistry`` package's UPSERT + heartbeat
contract:

  * one UPSERT at startup with detected capabilities
  * heartbeat every 30s refreshes last_heartbeat/last_seen + telemetry
    (cpu_pct, ram_used_gb, load_avg_1m)
  * one UPDATE on shutdown flips status='offline'

The identity is ``cluster-sidecar@<hostname>``. ``declared_queues`` is
the synthetic ``http:cluster`` string — Temporal-style queues use bare
lowercase names so an ``http:`` prefix is a clear signal to the UI
that this isn't a Temporal worker.

If WORKERS_REGISTRY_DSN is unset the whole module is a no-op — the
sidecar still serves /v1/cluster + /v1/assign, it just doesn't show
up in the Nodes UI.
"""

from __future__ import annotations

import asyncio
import logging
import os
import platform
import socket
import subprocess
from typing import Optional, Tuple

import asyncpg
import psutil

log = logging.getLogger("cluster-sidecar.registry")


def _detect_nvidia_gpu() -> Tuple[str, int, int, str]:
    """Probe nvidia-smi for GPU info. Returns ``(model, count, vram_gb, driver)``.

    Returns ``("", 0, 0, "")`` on any failure (binary missing, no GPU,
    parse error, timeout). Mirrors ``core/workerregistry/detect.go``
    so the cluster-sidecar reports the same shape as Go workers.

    The container must run with ``--gpus all`` (or compose
    ``deploy.resources.reservations.devices``) and at least the
    ``utility`` driver capability for nvidia-smi to be present.
    """
    try:
        result = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=name,driver_version,memory.total",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (FileNotFoundError, OSError, subprocess.TimeoutExpired) as exc:
        log.debug("nvidia-smi not available: %s", exc)
        return "", 0, 0, ""

    if result.returncode != 0:
        log.debug("nvidia-smi returned %d: %s", result.returncode, result.stderr.strip())
        return "", 0, 0, ""

    rows = [r for r in (line.strip() for line in result.stdout.splitlines()) if r]
    if not rows:
        return "", 0, 0, ""

    model = ""
    driver = ""
    count = 0
    # Min-VRAM across cards (heterogeneous fleets: dispatch must match the
    # guaranteed-available card, not the largest).
    min_vram_mb = 0
    for i, row in enumerate(rows):
        fields = [f.strip() for f in row.split(",")]
        if len(fields) < 3:
            continue
        name, drv, mem_str = fields[0], fields[1], fields[2]
        if i == 0:
            model = name
            driver = drv
        count += 1
        try:
            mb = int(mem_str)
        except ValueError:
            continue
        if mb > 0 and (min_vram_mb == 0 or mb < min_vram_mb):
            min_vram_mb = mb

    vram_gb = round(min_vram_mb / 1024) if min_vram_mb > 0 else 0
    return model, count, vram_gb, driver


_UPSERT_SQL = """
INSERT INTO evo.workers (
    id, identity, hostname, tailscale_ip, declared_queues,
    cpu_arch, cpu_features, cpu_count, ram_gb,
    gpu_model, gpu_count, gpu_vram_gb, driver_version,
    status, last_heartbeat, last_seen
) VALUES (
    $1, $2, $3, NULLIF($4,'')::inet, $5,
    $6, $7, $8, $9,
    NULLIF($10,''), $11, $12, NULLIF($13,''),
    'active', NOW(), NOW()
)
ON CONFLICT (id) DO UPDATE SET
    identity        = EXCLUDED.identity,
    hostname        = EXCLUDED.hostname,
    tailscale_ip    = EXCLUDED.tailscale_ip,
    declared_queues = EXCLUDED.declared_queues,
    cpu_arch        = EXCLUDED.cpu_arch,
    cpu_features    = EXCLUDED.cpu_features,
    cpu_count       = EXCLUDED.cpu_count,
    ram_gb          = EXCLUDED.ram_gb,
    gpu_model       = EXCLUDED.gpu_model,
    gpu_count       = EXCLUDED.gpu_count,
    gpu_vram_gb     = EXCLUDED.gpu_vram_gb,
    driver_version  = EXCLUDED.driver_version,
    status          = CASE WHEN evo.workers.status IN ('draining','maintenance','banned')
                           THEN evo.workers.status ELSE 'active' END,
    last_heartbeat  = NOW(),
    last_seen       = NOW()
"""

_HEARTBEAT_SQL = """
UPDATE evo.workers
   SET last_heartbeat = NOW(),
       last_seen      = NOW(),
       cpu_pct        = $2,
       ram_used_gb    = $3,
       load_avg_1m    = $4
 WHERE id = $1
"""

_OFFLINE_SQL = "UPDATE evo.workers SET status = 'offline', last_seen = NOW() WHERE id = $1"


class WorkerRegistration:
    """Owns the asyncpg connection + heartbeat task for one sidecar.

    Construct via :meth:`start`; call :meth:`stop` from the FastAPI
    lifespan teardown to mark the row offline cleanly.
    """

    def __init__(self, dsn: str, worker_id: str, identity: str, hostname: str):
        self._dsn = dsn
        self._worker_id = worker_id
        self._identity = identity
        self._hostname = hostname
        self._pool: Optional[asyncpg.Pool] = None
        self._task: Optional[asyncio.Task[None]] = None
        self._stop_event = asyncio.Event()

    @classmethod
    async def start(cls) -> Optional["WorkerRegistration"]:
        dsn = os.environ.get("WORKERS_REGISTRY_DSN", "")
        if not dsn:
            log.info("WORKERS_REGISTRY_DSN unset; cluster-sidecar will not appear in the Nodes UI")
            return None

        hostname = os.environ.get("WORKER_HOSTNAME") or socket.gethostname() or "unknown"
        identity = os.environ.get("WORKER_IDENTITY", "cluster-sidecar")
        worker_id = f"{identity}@{hostname}"

        reg = cls(dsn=dsn, worker_id=worker_id, identity=identity, hostname=hostname)
        try:
            await reg._upsert()
        except Exception as exc:
            log.warning("workers UPSERT failed; sidecar will not appear in Nodes UI: %s", exc)
            await reg._close_pool()
            return None
        reg._task = asyncio.create_task(reg._heartbeat_loop(), name="workers-heartbeat")
        log.info("registered as evo.workers row", extra={"id": worker_id})
        return reg

    async def stop(self) -> None:
        self._stop_event.set()
        if self._task is not None:
            try:
                await asyncio.wait_for(self._task, timeout=5.0)
            except (asyncio.TimeoutError, asyncio.CancelledError):
                self._task.cancel()
        if self._pool is not None:
            try:
                async with self._pool.acquire() as conn:
                    await conn.execute(_OFFLINE_SQL, self._worker_id)
                log.info("marked offline", extra={"id": self._worker_id})
            except Exception as exc:
                log.warning("offline UPDATE failed: %s", exc)
        await self._close_pool()

    async def _ensure_pool(self) -> asyncpg.Pool:
        if self._pool is None:
            self._pool = await asyncpg.create_pool(self._dsn, min_size=1, max_size=2)
        return self._pool

    async def _close_pool(self) -> None:
        if self._pool is not None:
            try:
                await self._pool.close()
            except Exception:
                pass
            self._pool = None

    async def _upsert(self) -> None:
        # Best-effort hardware probe; missing values land as NULL via
        # the NULLIF + nullable-arg pattern from the Go impl.
        cpu_arch = platform.machine() or "unknown"
        cpu_count = psutil.cpu_count(logical=True) or 0
        ram_gb_value = int(round(psutil.virtual_memory().total / (1024 ** 3)))
        ram_gb_arg: Optional[int] = ram_gb_value if ram_gb_value > 0 else None

        # The sidecar's workload is CPU-only (HDBSCAN + UMAP), but we still
        # report the host's GPU so the Nodes UI / dispatcher know what
        # silicon is *present* on this hostname.
        gpu_model, gpu_count, gpu_vram_gb, gpu_driver = _detect_nvidia_gpu()

        pool = await self._ensure_pool()
        async with pool.acquire() as conn:
            await conn.execute(
                _UPSERT_SQL,
                self._worker_id,           # $1  id
                self._identity,            # $2  identity
                self._hostname,            # $3  hostname
                "",                        # $4  tailscale_ip (empty -> NULL)
                ["http:cluster"],          # $5  declared_queues
                cpu_arch,                  # $6  cpu_arch
                [],                        # $7  cpu_features (skip the cpuid dance)
                cpu_count,                 # $8  cpu_count
                ram_gb_arg,                # $9  ram_gb
                gpu_model,                 # $10 gpu_model
                gpu_count,                 # $11 gpu_count
                gpu_vram_gb,               # $12 gpu_vram_gb
                gpu_driver,                # $13 driver_version
            )

    async def _heartbeat_loop(self) -> None:
        period = float(os.environ.get("WORKER_HEARTBEAT_SEC", "30"))
        while not self._stop_event.is_set():
            try:
                await asyncio.wait_for(self._stop_event.wait(), timeout=period)
                return  # stop requested
            except asyncio.TimeoutError:
                pass
            await self._heartbeat_once()

    async def _heartbeat_once(self) -> None:
        cpu_pct = psutil.cpu_percent(interval=None)  # since last call; first call returns 0.0
        vm = psutil.virtual_memory()
        ram_used_gb = float((vm.total - vm.available) / (1024 ** 3))
        # load_avg_1m: psutil.getloadavg is Unix-only; fall back to None on weirdness.
        try:
            load_1m = float(psutil.getloadavg()[0])
        except (AttributeError, OSError):
            load_1m = None

        try:
            pool = await self._ensure_pool()
            async with pool.acquire() as conn:
                await conn.execute(
                    _HEARTBEAT_SQL,
                    self._worker_id,
                    float(cpu_pct) if cpu_pct == cpu_pct else None,  # NaN guard
                    ram_used_gb if ram_used_gb == ram_used_gb else None,
                    load_1m,
                )
        except Exception as exc:
            log.warning("heartbeat failed: %s", exc)
