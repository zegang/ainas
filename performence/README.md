# Perfetto Performance Tracing

This directory contains Perfetto configurations and scripts for tracing the
AI-NAS stack (Flutter frontend, C++ backend, Python backend).

## Quick Start

```bash
# Record a 10-second trace of the C++ backend
./record.sh -d 10 -o trace.perfetto

# View a trace in the Perfetto UI
./view.sh trace.perfetto
```

## Prerequisites

- **Perfetto CLI tools** (for recording system traces):
  ```bash
  # Linux
  curl -LO https://dl.google.com/perfetto/perfetto
  chmod +x perfetto
  sudo mv perfetto /usr/local/bin/
  ```

- **Perfetto UI**: https://ui.perfetto.dev (browser-based viewer)

## Layer-specific Tracing

### C++ Backend (backendcpp/)
- Compile with `-DAINAS_ENABLE_TRACING=ON` to enable Perfetto instrumentation
- Key events: request handling, file I/O, AI inference, database queries

### Flutter Frontend (frontend/)
- Use `dart:developer` Timeline API (built-in, no extra package)
- Record traces via Flutter DevTools or `--trace-startup` flag

### Python Backend (backend/)
- OpenTelemetry SDK exports traces via OTLP
- Receivers configured in `otel-collector-config.yml`

## How to Use (C++ Backend)

```bash
# Build with tracing enabled
cmake -B build -S . -DAINAS_ENABLE_TRACING=ON
cmake --build build

# Run the backend
AINAS_LOG_LEVEL=error AINAS_AI_ENABLED=false ./build/src/ainas-backend-cpp

# In another terminal: trigger a trace dump via SIGUSR1
kill -USR1 $(pgrep ainas-backend-cpp)

# View the trace
./performence/view.sh   # opens https://ui.perfetto.dev
```

The trace is written to `/tmp/ainas-trace.perfetto` in Chrome Trace Event JSON format, which the Perfetto UI imports natively.
