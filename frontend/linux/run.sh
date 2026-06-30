#!/usr/bin/env bash
set -euo pipefail

# Resolve the directory where this script lives (works with symlinks)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

# Add bundled libraries to the search path
export LD_LIBRARY_PATH="${SCRIPT_DIR}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

exec "$SCRIPT_DIR/ainas_frontend" "$@"
