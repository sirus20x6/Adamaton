# BGE-M3 + BGE-Reranker-v2-m3 sidecar.
# Assumes the host has nvidia-container-toolkit installed; compose uses the
# `deploy.resources.reservations.devices` block to attach all visible GPUs.

FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/cache \
    TRANSFORMERS_CACHE=/cache \
    SENTENCE_TRANSFORMERS_HOME=/cache

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3.11 \
        python3.11-venv \
        python3-pip \
        curl \
        ca-certificates \
        git \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY pyproject.toml ./
COPY app ./app

RUN python3 -m pip install --upgrade pip \
    && python3 -m pip install -e .

EXPOSE 8089

CMD ["python3", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8089"]
