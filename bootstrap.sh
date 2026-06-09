#!/bin/bash
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load defaults from .env if it exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
fi

export NAS_HOST=${NAS_HOST:-0.0.0.0}
export NAS_PORT=${NAS_PORT:-9026}
export FRONTEND_PORT=${FRONTEND_PORT:-8080}

# If NAS_HOST is 0.0.0.0, resolve a real host IP for mDNS broadcasting.
if [ "$NAS_HOST" == "0.0.0.0" ]; then
    # Detect the primary local IP address; fallback to 127.0.0.1 if detection fails.
    DETECTED_IP=$(hostname -I | awk '{print $1}' | xargs)
    export NAS_ADVERTISE_ADDR=${DETECTED_IP:-127.0.0.1}
else
    export NAS_ADVERTISE_ADDR="$NAS_HOST"
fi

# Auto-detect GUI environment (X11 or Wayland) to default to native Linux app
if [ -z "$FRONTEND_PLATFORM" ]; then
    if [[ "$OSTYPE" == "linux-gnu"* ]] && [[ -n "$DISPLAY" || -n "$WAYLAND_DISPLAY" ]]; then
        export FRONTEND_PLATFORM="linux"
    else
        export FRONTEND_PLATFORM="web"
    fi
fi

export ENABLE_AI=${ENABLE_AI:-false}

# Handle global platform override parameter
if [[ "$1" == "--platform" ]]; then
    export FRONTEND_PLATFORM="$2"
    shift 2
fi

show_usage() {
    echo "AI-NAS Bootstrap Script"
    echo "Usage: ./bootstrap.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --upgrade    Upgrade Python and Flutter dependencies to latest allowed versions"
    echo "  --outdated   Check for outdated Flutter dependencies"
    echo "  --setup      Install Python dependencies and Flutter SDK submodule"
    echo "  --backend    Setup and run only the FastAPI backend"
    echo "  --platform   Frontend target (web, linux; default: web)"
    echo "  --openapi    Export the backend OpenAPI spec to openapi.json"
    echo "  --frontend   Setup and run only the Flutter frontend"
    echo "  --build-web  Compile the Flutter Web GUI for production"
    echo "  --observability Start Prometheus observability services"
    echo "  --web        Run the Flutter frontend as a web application"
    echo "  --linux      Run the Flutter frontend as a native Linux app"
    echo "  --android    Build the Android APK (Release)"
    echo "  --all        Setup and run both backend and frontend (default)"
    echo "  --help, -h   Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  NAS_HOST     Listening IP (default: 0.0.0.0)"
    echo "  NAS_PORT     Listening port (default: 9026)"
    echo "  FRONTEND_PORT Listening port for GUI (default: 8080)"
    echo "  ENABLE_AI    Enable AI features (true/false, default: false)"
}

setup_python() {
    echo "Step: Setting up Python Backend..."

    # conda install -c conda-forge openssl libgomp

    if ! command -v uv &> /dev/null; then
        echo "uv not found. Installing..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        # shellcheck source=/dev/null
        [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
    fi

    if [[ -n "$VIRTUAL_ENV" ]]; then
        echo "Notice: An external virtual environment is currently active: $VIRTUAL_ENV"
    fi

    cd "$PROJECT_ROOT/backend"
    if [[ ! -d ".venv" ]]; then
        echo "Step: Synchronizing dependencies with uv sync..."
        uv sync
    fi
    cd "$PROJECT_ROOT"
}

upgrade_deps() {
    echo "Step: Upgrading dependencies..."
    setup_python
    
    FLUTTER_HOME="$PROJECT_ROOT/vendor/flutter"
    export PATH="$FLUTTER_HOME/bin:$PATH"
    
    cd "$PROJECT_ROOT/frontend"
    echo "Cleaning Flutter build cache..."
    flutter clean
    echo "Upgrading Flutter packages (including major versions to resolve conflicts)..."
    # This fixes the 'Member not found: platform' error by allowing file_picker 
    # and others to move to their latest compatible major versions.
    flutter pub upgrade --major-versions
    cd "$PROJECT_ROOT"
}

check_outdated() {
    echo "Step: Checking for outdated Flutter dependencies..."
    FLUTTER_HOME="$PROJECT_ROOT/vendor/flutter"
    export PATH="$FLUTTER_HOME/bin:$PATH"
    
    cd "$PROJECT_ROOT/frontend"
    flutter pub outdated
    cd "$PROJECT_ROOT"
}

ensure_linux_deps() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v dpkg >/dev/null 2>&1; then
            if ! dpkg -s libnm-dev libgtk-3-dev >/dev/null 2>&1; then
                echo "Step: Installing missing Linux development libraries..."
                sudo apt update && sudo apt install -y libnm-dev libgtk-3-dev
            fi
        fi
    fi
}

setup_flutter() {
    echo "Step: Flutter..."
    ensure_linux_deps

    FLUTTER_HOME="$PROJECT_ROOT/vendor/flutter"
    export PATH="$FLUTTER_HOME/bin:$PATH"

    if [[ ! -d "$FLUTTER_HOME/bin" ]]; then
        echo "Step: Initializing Flutter SDK submodule (this may take a while)..."
        git submodule update --init --recursive vendor/flutter
    fi

    cd "$PROJECT_ROOT/frontend"
    
    echo "Step: Fetching Flutter dependencies and generating localization classes..."
    # We always run pub get here to ensure that the synthetic package (flutter_gen) 
    # is generated. This is required for internationalization (i18n) to work 
    # when 'generate: true' is set in pubspec.yaml.
    flutter clean
    flutter pub get

    # Ensure the project is configured for the target platforms
    if [[ ! -d "web" ]]; then
        echo "Step: Configuring Flutter project platforms..."
        flutter create . --platforms web,linux,android --description "A Flutter-based GUI for the AI-NAS."
    fi

    # Patch CMake to avoid RPATH relinking issues with Ninja on some Linux environments
    if [[ -f "linux/CMakeLists.txt" ]] && ! grep -q "CMAKE_BUILD_WITH_INSTALL_RPATH" linux/CMakeLists.txt; then
        echo "Step: Applying CMake RPATH fix..."
        sed -i '1i set(CMAKE_BUILD_WITH_INSTALL_RPATH TRUE)' linux/CMakeLists.txt
    fi

    cd "$PROJECT_ROOT"
}

build_web() {
    echo "Step: Building Flutter Web GUI..."
    setup_flutter
    cd "$PROJECT_ROOT/frontend"
    flutter build web \
        --dart-define=NAS_HOST="$NAS_HOST" \
        --dart-define=NAS_PORT="$NAS_PORT" \
        --dart-define=ENABLE_AI="$ENABLE_AI"
    cd "$PROJECT_ROOT"
}

run_observability() {
    if [[ ! -d "$PROJECT_ROOT/observability" ]]; then
        echo "Notice: Observability directory not found. Skipping."
        return
    fi
    echo "Step: Launching Observability Services (Prometheus)..."
    cd "$PROJECT_ROOT/observability"
    
    # Attempt to start via docker compose plugin or standalone docker-compose
    if docker compose version &> /dev/null; then
        docker compose up -d
    elif command -v docker-compose &> /dev/null; then
        docker-compose up -d
    else
        echo "Warning: docker compose not found. Please install Docker to use Prometheus."
    fi
    
    cd "$PROJECT_ROOT"
}

run_backend() {
    local is_bg="${1:-true}"
    echo "Step: Launching Backend..."
    mkdir -p "$PROJECT_ROOT/logs"
    # Use the local virtual environment created by uv sync
    # Include the AMD GPU override for your gfx1100 architecture
    # Redirect output to logs/backend.log for persistence
    if [[ "$is_bg" == "true" ]]; then
        HSA_OVERRIDE_GFX_VERSION=11.0.0 \
        PYTHONUNBUFFERED=1 \
        NAS_ADVERTISE_ADDR="$NAS_ADVERTISE_ADDR" \
        "$PROJECT_ROOT/backend/.venv/bin/python" -m uvicorn backend.main:app \
            --host "$NAS_HOST" \
            --port "$NAS_PORT" &
        BACKEND_PID=$!
    else
        HSA_OVERRIDE_GFX_VERSION=11.0.0 \
        PYTHONUNBUFFERED=1 \
        NAS_ADVERTISE_ADDR="$NAS_ADVERTISE_ADDR" \
        "$PROJECT_ROOT/backend/.venv/bin/python" -m uvicorn backend.main:app \
            --host "$NAS_HOST" \
            --port "$NAS_PORT"
    fi
}

run_frontend() {
    local is_bg="${1:-true}"
    unset http_proxy
    unset https_proxy
    unset HTTP_PROXY
    unset HTTPS_PROXY
    unset NO_PROXY

    cd "$PROJECT_ROOT/frontend"
    if [[ "$FRONTEND_PLATFORM" == "linux" ]]; then
        echo "Step: Launching Frontend (Native Linux)..."
        if [[ "$is_bg" == "true" ]]; then
            flutter run -d linux \
                --dart-define=NAS_HOST="$NAS_HOST" \
                --dart-define=NAS_PORT="$NAS_PORT" \
                --dart-define=ENABLE_AI="$ENABLE_AI" &
            FRONTEND_PID=$!
        else
            flutter run -d linux \
                --dart-define=NAS_HOST="$NAS_HOST" \
                --dart-define=NAS_PORT="$NAS_PORT" \
                --dart-define=ENABLE_AI="$ENABLE_AI"
        fi
    else
        echo "Step: Launching Frontend (Web Server)..."
        # Use 'web-server' instead of 'chrome' to allow remote access and prevent 
        # failures in headless or remote environments.
        if [[ "$is_bg" == "true" ]]; then
            flutter run -d web-server \
                --web-port "$FRONTEND_PORT" \
                --web-hostname "$NAS_HOST" \
                --dart-define=NAS_HOST="$NAS_HOST" \
                --dart-define=NAS_PORT="$NAS_PORT" \
                --dart-define=ENABLE_AI="$ENABLE_AI" &
            FRONTEND_PID=$!
        else
            flutter run -d web-server \
                --web-port "$FRONTEND_PORT" \
                --web-hostname "$NAS_HOST" \
                --dart-define=NAS_HOST="$NAS_HOST" \
                --dart-define=NAS_PORT="$NAS_PORT" \
                --dart-define=ENABLE_AI="$ENABLE_AI"
        fi
    fi
    cd "$PROJECT_ROOT"
}

build_android() {
    echo "Step: Building Android APK..."
    setup_flutter
    cd "$PROJECT_ROOT/frontend"
    flutter build apk --release
    echo "Build Complete. APK located at: $PROJECT_ROOT/frontend/build/app/outputs/flutter-apk/app-release.apk"
    cd "$PROJECT_ROOT"
}

case "$1" in
    --help|-h)
        show_usage
        exit 0
        ;;
    --upgrade)
        upgrade_deps
        ;;
    --outdated)
        check_outdated
        ;;
    --setup)
        setup_python
        setup_flutter
        ;;
    --observability)
        run_observability
        ;;
    --backend)
        setup_python
        run_backend false
        ;;
    --frontend)
        setup_flutter
        run_frontend false
        ;;
    --linux)
        setup_flutter
        FRONTEND_PLATFORM="linux"
        run_frontend false
        ;;
    --web)
        setup_flutter
        FRONTEND_PLATFORM="web"
        run_frontend false
        ;;
    --android)
        build_android
        ;;
    --build-web)
        build_web
        ;;
    --openapi)
        setup_python
        echo "Step: Exporting OpenAPI Schema..."
        PYTHONPATH="$PROJECT_ROOT" "$PROJECT_ROOT/backend/.venv/bin/python" -m backend.export_openapi
        ;;
    --all|*)
        run_observability
        setup_python
        setup_flutter
        run_backend true
        run_frontend true
        
        # Wait for backend to be ready
        echo "Waiting for backend services to initialize..."
        until curl -s "http://$NAS_HOST:$NAS_PORT/docs" > /dev/null; do
            sleep 2
        done

        if [ "$NAS_HOST" == "0.0.0.0" ] || [ -z "$NAS_HOST" ]; then
            URL_HOST="${NAS_ADVERTISE_ADDR:-localhost}"
        else
            URL_HOST="$NAS_HOST"
        fi

        echo "AI-NAS is running."
        echo "Backend API:  http://$URL_HOST:$NAS_PORT"
        echo "Swagger UI:   http://$URL_HOST:$NAS_PORT/docs"
        echo "Prometheus:   http://localhost:9090"
        echo "Backend Logs: $PROJECT_ROOT/logs/backend.log"
        
        if [[ "$FRONTEND_PLATFORM" == "linux" ]]; then
            echo "Frontend GUI: Native Linux App (Launching...)"
        else
            echo "Frontend GUI: http://$URL_HOST:$FRONTEND_PORT (Waiting for compilation...)"
            echo "Note: It may take up to a minute for the frontend to become reachable."
        fi
        
        trap "kill $BACKEND_PID $FRONTEND_PID 2>/dev/null; (cd observability && docker compose down 2>/dev/null); exit" INT TERM
        wait
        ;;
esac