# syntax=docker/dockerfile:1
# AI-NAS Backend Dockerfile
#
# Build context: monorepo root (the parent of backend/)
#
# Examples:
#   CPU build:    docker build -t ainas-backend:latest -f backend/Dockerfile .
#   CUDA build:   docker build -t ainas-backend:cuda \
#                   --build-arg BASE_IMAGE=nvidia/cuda:12.4.1-runtime-ubuntu22.04 \
#                   --build-arg BUILDER_BASE_IMAGE=nvidia/cuda:12.4.1-devel-ubuntu22.04 \
#                   --build-arg TORCH_INDEX_URL=https://download.pytorch.org/whl/cu124 \
#                   -f backend/Dockerfile .
#   ROCm build:   docker build -t ainas-backend:rocm \
#                   --build-arg BASE_IMAGE=rocm/pytorch:rocm7.2.4_ubuntu24.04_py3.12_pytorch_release_2.10.0 \
#                   -f backend/Dockerfile .
#
# Run:
#   docker run -p 9026:9026 -v ./storage:/app/storage ainas-backend:latest

ARG BASE_IMAGE=python:3.12-slim
ARG BUILDER_BASE_IMAGE=${BASE_IMAGE}
ARG TORCH_INDEX_URL=
ARG LLAMA_CPP_CMAKE_ARGS=

# ═══════════════════════════════════════════════════════════════════════════════
#  Builder Stage  —  install all Python dependencies via uv
# ═══════════════════════════════════════════════════════════════════════════════
FROM ${BUILDER_BASE_IMAGE} AS builder

ARG TORCH_INDEX_URL
ARG LLAMA_CPP_CMAKE_ARGS

WORKDIR /build

# System build-time dependencies (compilers, cmake for llama-cpp-python, etc.)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    build-essential \
    cmake \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Copy only dependency metadata for optimal layer caching
COPY backend/pyproject.toml backend/uv.lock ./backend/

# Install project dependencies (frozen = exact lockfile versions, no dev extras)
# CMAKE_ARGS is forwarded to llama-cpp-python for GPU backend support
# For ROCm/HIP builds, ensure the HIP compiler is discoverable
RUN --mount=type=cache,target=/root/.cache/uv \
    cd backend && \
    if [ -n "$LLAMA_CPP_CMAKE_ARGS" ]; then \
        export PATH="/opt/rocm/bin:/usr/local/cuda/bin:$PATH" && \
        export CMAKE_PREFIX_PATH="/opt/rocm:$CMAKE_PREFIX_PATH" && \
        export LIBRARY_PATH="/usr/local/cuda/lib64/stubs:$LIBRARY_PATH" && \
        export LD_LIBRARY_PATH="/usr/local/cuda/lib64:/usr/local/cuda/lib64/stubs:$LD_LIBRARY_PATH" && \
        if [ -f /usr/local/cuda/lib64/stubs/libcuda.so ] && [ ! -f /usr/local/cuda/lib64/stubs/libcuda.so.1 ]; then \
            ln -sf libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1; \
        fi && \
        CMAKE_ARGS="$LLAMA_CPP_CMAKE_ARGS" uv sync --frozen --no-dev ${TORCH_INDEX_URL:+--index-url "$TORCH_INDEX_URL"} && \
        uv cache clean; \
    else \
        uv sync --frozen --no-dev ${TORCH_INDEX_URL:+--index-url "$TORCH_INDEX_URL"} && \
        uv cache clean; \
    fi

# ═══════════════════════════════════════════════════════════════════════════════
#  Runtime Stage  —  minimal image with the application and its venv
# ═══════════════════════════════════════════════════════════════════════════════
FROM ${BASE_IMAGE} AS runtime

ARG LLAMA_CPP_CMAKE_ARGS

WORKDIR /app

# Runtime system dependencies
#   libgomp1   — OpenMP runtime (required by llama.cpp / PyTorch)
#   curl       — healthcheck probe
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
    curl \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Create non-privileged user
RUN groupadd -r app && useradd -r -g app -d /app -s /sbin/nologin app

# Copy the virtual environment from the builder
COPY --from=builder /build/backend/.venv /app/.venv

# Copy the backend package (needed so that `import backend.main` resolves)
COPY backend/ /app/backend/

# Copy the Flutter web build (served by FastAPI as static files)
# The path matches main.py's default: backend/../frontend/build/web/
COPY frontend/build/web/ /app/frontend/build/web/

# Copy entrypoint script
COPY backend/containerize/docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

# Runtime data directories
RUN mkdir -p /app/storage/nasdata /app/storage/nasmetadata/thumbnails /app/logs && \
    chown -R app:app /app

ENV \
    PATH="/app/.venv/bin:$PATH" \
    PYTHONPATH="/app" \
    PYTHONUNBUFFERED=1

USER app

# Health check — uses the status endpoint exposed by the API router
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl -sf http://localhost:${AINAS_PORT:-9026}/api/status || exit 1

EXPOSE 9026

ENTRYPOINT ["/app/docker-entrypoint.sh"]
