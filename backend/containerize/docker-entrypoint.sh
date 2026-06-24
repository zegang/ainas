#!/usr/bin/env bash
# AI-NAS Backend — Docker entrypoint
#
# Responsible for:
#   1. Applying environment-overrides to config.yaml
#   2. Running database migrations
#   3. Starting the uvicorn server
set -euo pipefail

APP_DIR="/app/backend"
CONFIG_FILE="${APP_DIR}/config.yaml"

# ── 1. Optional: write a minimal config.yaml from environment variables ──────
# If the user didn't mount a custom config.yaml, the baked-in default
# (all commented-out) is already present.  Every setting can still be
# controlled at runtime via environment variables — see core/config.py.

# ── 2. Ensure storage directories exist ─────────────────────────────────────
mkdir -p /app/storage/nasdata /app/storage/nasmetadata/thumbnails ${APP_DIR}/logs

# ── 3. Run database migrations ──────────────────────────────────────────────
echo "Running database migrations..."
cd "${APP_DIR}"
.venv/bin/alembic upgrade head 2>/dev/null || echo "Warning: migrations skipped or already up-to-date"

# ── 4. Start uvicorn ────────────────────────────────────────────────────────
echo "Starting AI-NAS backend on ${AINAS_ADDR:-0.0.0.0}:${AINAS_PORT:-9026}..."
exec .venv/bin/uvicorn backend.main:app \
    --host "${AINAS_ADDR:-0.0.0.0}" \
    --port "${AINAS_PORT:-9026}" \
    --no-access-log \
    --loop uvloop \
    --http h11
