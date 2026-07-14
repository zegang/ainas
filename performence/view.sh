#!/bin/bash
# Open a Perfetto trace file in the web UI.
# Usage: ./view.sh trace.perfetto

set -euo pipefail

TRACE="${1:-ainas-trace.perfetto}"

if [ ! -f "$TRACE" ]; then
  echo "Trace file not found: $TRACE"
  echo "Usage: $0 <trace-file>"
  exit 1
fi

echo "Opening $TRACE in Perfetto UI..."
echo "  https://ui.perfetto.dev"

# If on Linux with xdg-open, open the URL directly
if command -v xdg-open &>/dev/null; then
  xdg-open "https://ui.perfetto.dev"
elif command -v open &>/dev/null; then
  open "https://ui.perfetto.dev"
fi

echo "Drag & drop $TRACE onto the page."
