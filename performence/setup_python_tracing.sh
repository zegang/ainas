#!/bin/bash
# Install Python dependencies for OpenTelemetry tracing.
# Run this once after cloning/updating the repo.

set -euo pipefail

cd "$(dirname "$0")/../backend"

pip install --quiet \
  opentelemetry-api \
  opentelemetry-sdk \
  opentelemetry-exporter-otlp-proto-grpc \
  opentelemetry-instrumentation-fastapi \
  opentelemetry-instrumentation-httpx

echo "Python tracing dependencies installed."
echo ""
echo "To enable tracing, set before starting the Python backend:"
echo "  export OTEL_SERVICE_NAME=ainas-python-backend"
echo "  export OTEL_TRACES_EXPORTER=otlp"
echo "  export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317"
