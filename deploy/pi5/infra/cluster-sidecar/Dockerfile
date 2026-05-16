# Clustering sidecar. CPU-only (HDBSCAN + UMAP run on the workstation
# beside bge-m3; no GPU needed). Exposes /v1/cluster and /v1/assign on
# port 8091. Modelled on ../sidecar/Dockerfile.

FROM python:3.11-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY pyproject.toml ./
COPY app ./app

RUN python3 -m pip install --upgrade pip \
    && python3 -m pip install -e .

EXPOSE 8091

CMD ["python3", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8091"]
