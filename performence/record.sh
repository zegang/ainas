#!/bin/bash
# Record a Perfetto trace of the running AI-NAS C++ backend.
# Usage: ./record.sh [-d duration_sec] [-o output_file]

set -euo pipefail

DURATION=10
OUTPUT="ainas-trace.perfetto"

while getopts "d:o:" opt; do
  case $opt in
    d) DURATION="$OPTARG" ;;
    o) OUTPUT="$OPTARG" ;;
    *) echo "Usage: $0 [-d seconds] [-o file]"; exit 1 ;;
  esac
done

BUILTIN_CONFIG="$(dirname "$0")/configs/perfetto-backend.cfg"

if command -v perfetto &>/dev/null; then
  echo "Recording ${DURATION}s trace to ${OUTPUT} ..."
  perfetto \
    --txt \
    --config "$BUILTIN_CONFIG" \
    --out "$OUTPUT"
  echo "Done. View at https://ui.perfetto.dev — open $OUTPUT"
else
  echo "Perfetto CLI not found. Install:"
  echo "  curl -LO https://dl.google.com/perfetto/perfetto && chmod +x perfetto && sudo mv perfetto /usr/local/bin/"
  echo ""
  echo "Alternatively, use the C++ backend's built-in trace dump:"
  echo "  kill -USR1 \$(pgrep ainas-backend-cpp)  # triggers trace dump to /tmp/"
  exit 1
fi
