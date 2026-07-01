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

export ENABLE_AI=${ENABLE_AI:-false}
export CONTAINER_TOOL=${CONTAINER_TOOL:-podman}
export TARGET_WINDOWS_VER=${TARGET_WINDOWS_VER:-0x0A00}
COMMAND=""

show_usage() {
    echo "AI-NAS Bootstrap Script"
    echo "Usage: ./bootstrap.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --upgrade      Upgrade Python and Flutter dependencies to latest allowed versions"
    echo "  --outdated     Check for outdated Flutter dependencies"
    echo "  --setup        Install Python dependencies and Flutter SDK submodule"
    echo "  --backend      Setup and run only the FastAPI backend"
    echo "  --backendcpp   Build and run the C++ (oatpp) backend"
    echo "  --build-cpp    Build the C++ backend binary without running"
    echo "  --platform     Frontend target (web, linux; default: web)"
    echo "  --openapi      Export the backend OpenAPI spec to openapi.json"
    echo "  --container-tool Tool for services (podman, docker; default: podman)"
    echo "  --winver       Windows target version (0x0A00=Win10/11, 0x0601=Win7; default: 0x0A00)"
    echo "  --frontend     Setup and run only the Flutter frontend"
    echo "  --build-web    Compile the Flutter Web GUI for production"
    echo "  --build-backend-image [cpu|cuda|rocm] Build frontend web + backend Docker image (default: cpu)"
    echo "  --rag          Start RAG services (Elasticsearch/Kibana)"
    echo "  --check-rag-health Check RAG services health (Elasticsearch)"
    echo "  --logs-rag     View RAG service logs"
    echo "  --stop-rag     Stop RAG services"
    echo "  --observability Start Prometheus observability services"
    echo "  --logs-observability View observability logs"
    echo "  --stop-observability Stop observability services"
    echo "  --web          Run the Flutter frontend as a web application"
    echo "  --linux        Run the Flutter frontend as a native Linux app"
    echo "  --android      Build the Android APK (Release)"
    echo "  --pyinstaller  Build a standalone binary with PyInstaller"
    echo "  --release      Build full release bundle for platform (linux|macos|windows|android|ios); use --winver to set Windows target version"
    echo "  --all          Setup and run both backend and frontend (default)"
    echo "  --help, -h     Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  NAS_HOST     Listening IP (default: 0.0.0.0)"
    echo "  NAS_PORT     Listening port (default: 9026)"
    echo "  FRONTEND_PORT Listening port for GUI (default: 8080)"
    echo "  ENABLE_AI    Enable AI features (true/false, default: false)"
    echo "  TARGET_WINDOWS_VER Windows target version (0x0A00=Win10/11, 0x0601=Win7; default: 0x0A00)"
}

# Parse Arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --platform)
            if [[ "$2" != "web" && "$2" != "linux" ]]; then
                echo "Error: Invalid platform '$2'. Supported: web, linux"
                exit 1
            fi
            export FRONTEND_PLATFORM="$2"; shift 2 ;;
        --container-tool)
            if [[ "$2" != "podman" && "$2" != "docker" ]]; then
                echo "Error: Invalid container tool '$2'. Supported: podman, docker"
                exit 1
            fi
            export CONTAINER_TOOL="$2"; shift 2 ;;
        --winver)
            if [[ ! "$2" =~ ^0x[0-9a-fA-F]{4}$ ]]; then
                echo "Error: Invalid Windows version '$2'. Use format 0x0A00 (Win10/11) or 0x0601 (Win7)."
                exit 1
            fi
            export TARGET_WINDOWS_VER="$2"; shift 2 ;;
        --build-backend-image)
            COMMAND="$1"; shift
            # Optional: cpu, cuda, rocm (default: cpu)
            if [[ $# -gt 0 && "$1" != --* ]]; then
                export BACKEND_IMAGE_VARIANT="$1"; shift
            else
                export BACKEND_IMAGE_VARIANT="cpu"
            fi ;;
        --release)
            COMMAND="$1"; shift
            if [[ $# -gt 0 && "$1" != --* ]]; then
                export RELEASE_PLATFORM="$1"; shift
            else
                echo "Error: --release requires a platform argument (linux|macos|windows|android|ios)"
                exit 1
            fi ;;
        --help|-h)
            show_usage; exit 0 ;;
        --*)
            if [[ -z "$COMMAND" ]]; then
                COMMAND="$1"; shift
            else
                echo "Error: Only one command can be executed at a time. Found $COMMAND and $1"
                exit 1
            fi ;;
        *)
            echo "Error: Invalid option '$1'"
            show_usage; exit 1 ;;
    esac
done

COMMAND=${COMMAND:-"--all"}

# Auto-detect GUI environment if not specified
if [ -z "$FRONTEND_PLATFORM" ]; then
    if [[ "$OSTYPE" == "linux-gnu"* ]] && [[ -n "$DISPLAY" || -n "$WAYLAND_DISPLAY" ]]; then
        export FRONTEND_PLATFORM="linux"
    else
        export FRONTEND_PLATFORM="web"
    fi
fi

# Validate release platform if set
if [ -n "$RELEASE_PLATFORM" ]; then
    case "$RELEASE_PLATFORM" in
        linux|macos|windows|android|ios) ;;
        *) echo "Error: Invalid release platform '$RELEASE_PLATFORM'. Supported: linux, macos, windows, android, ios"; exit 1 ;;
    esac
fi

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
            if ! dpkg -s libnm-dev libgtk-3-dev libpoppler-cpp-dev libqpdf-dev libboost-all-dev >/dev/null 2>&1; then
                echo "Step: Installing missing Linux development libraries..."
                sudo apt update && sudo apt install -y libnm-dev libgtk-3-dev libpoppler-cpp-dev libqpdf-dev libboost-all-dev
            fi
        fi
    fi
}

ensure_macos_deps() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew >/dev/null 2>&1; then
            if ! brew list poppler &>/dev/null || ! brew list qpdf &>/dev/null; then
                echo "Step: Installing PDF and Boost libraries via Homebrew..."
                brew install poppler qpdf boost
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
        --dart-define=ENABLE_AI="$ENABLE_AI" \
        --release
    cd "$PROJECT_ROOT"
}

run_compose() {
    local action="$1"
    local cmd=""
    
    if [[ "$CONTAINER_TOOL" == "podman" ]]; then
        if podman compose version &> /dev/null; then
            cmd="podman compose"
        elif command -v podman-compose &> /dev/null; then
            cmd="podman-compose"
        fi
    else
        if docker compose version &> /dev/null; then
            cmd="docker compose"
        elif command -v docker-compose &> /dev/null; then
            cmd="docker-compose"
        fi
    fi

    if [[ -n "$cmd" ]]; then $cmd $action; else echo "Warning: $CONTAINER_TOOL compose tool not found."; fi
}

run_observability() {
    if [[ ! -d "$PROJECT_ROOT/observability" ]]; then
        echo "Notice: Observability directory not found. Skipping."
        return
    fi
    echo "Step: Launching Observability Services (Prometheus)..."
    cd "$PROJECT_ROOT/observability"
    run_compose "up -d"
    cd "$PROJECT_ROOT"
}

stop_observability() {
    if [[ ! -d "$PROJECT_ROOT/observability" ]]; then
        return
    fi
    echo "Step: Stopping Observability Services (Prometheus)..."
    cd "$PROJECT_ROOT/observability"
    run_compose "down"
    cd "$PROJECT_ROOT"
}

run_rag() {
    if [[ ! -d "$PROJECT_ROOT/thirdservices/rag" ]]; then
        echo "Notice: RAG directory not found. Skipping."
        return
    fi
    echo "Step: Launching RAG Services (Elasticsearch/Kibana)..."
    cd "$PROJECT_ROOT/thirdservices/rag"
    run_compose "up -d"
    cd "$PROJECT_ROOT"
}

check_rag_health() {
    if [[ ! -d "$PROJECT_ROOT/thirdservices/rag" ]]; then
        echo "Notice: RAG directory not found. Skipping health check."
        return
    fi
    echo "Step: Checking RAG Services Health (Elasticsearch)..."
    # Use curl to check Elasticsearch health endpoint
    # The ES_URL is usually http://localhost:9200, but we need to ensure it's accessible from the host.
    # Assuming the docker-compose exposes 9200 to localhost.
    curl -s -X GET "http://localhost:9200/_cluster/health?pretty"
    echo "" # Add a newline for cleaner output
    echo "For more detailed health, check Kibana at http://localhost:5601 (if running) or logs with --logs-rag."
    cd "$PROJECT_ROOT"
}



show_rag_logs() {
    if [[ ! -d "$PROJECT_ROOT/thirdservices/rag" ]]; then
        return
    fi
    cd "$PROJECT_ROOT/thirdservices/rag"
    run_compose "logs -f"
}

stop_rag() {
    if [[ ! -d "$PROJECT_ROOT/thirdservices/rag" ]]; then
        return
    fi
    echo "Step: Stopping RAG Services (Elasticsearch/Kibana)..."
    cd "$PROJECT_ROOT/thirdservices/rag"
    run_compose "down"
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

setup_cpp() {
    local build_type="${1:-Release}"
    echo "Step: Building C++ Backend with CMake..."

    ensure_linux_deps
    ensure_macos_deps

    # Ensure all Git submodules (including nested ones like vendor/cllama/third_party/oatpp-swagger) are initialized
    local needs_reconfigure=false
    if [ ! -f "$PROJECT_ROOT/vendor/oatpp/CMakeLists.txt" ] || [ ! -f "$PROJECT_ROOT/vendor/cllama/third_party/oatpp-swagger/CMakeLists.txt" ]; then
        echo "Step: Initializing Git submodules (recursive)..."
        git submodule update --init --recursive
        needs_reconfigure=true
    fi

    local win_arg=()
    if [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "cygwin"* || "$OSTYPE" == "mingw"* ]]; then
        win_arg=(-DTARGET_WINDOWS_VER="$TARGET_WINDOWS_VER")
    fi
    if [ ! -d "$PROJECT_ROOT/backendcpp/build" ] || [ "$needs_reconfigure" = true ]; then
        cmake -S "$PROJECT_ROOT/backendcpp" -B "$PROJECT_ROOT/backendcpp/build" \
            -DCMAKE_BUILD_TYPE="$build_type" \
            -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
            "${win_arg[@]}"
    fi
    cmake --build "$PROJECT_ROOT/backendcpp/build" -j"$(nproc)"
}

run_backendcpp() {
    local is_bg="${1:-true}"
    echo "Step: Launching C++ Backend..."
    mkdir -p "$PROJECT_ROOT/logs"

    export AINAS_ADDR="$NAS_HOST"
    export AINAS_PORT="$NAS_PORT"
    export AINAS_DATA_PATH="$PROJECT_ROOT/storage/nasdata"

    if [[ "$is_bg" == "true" ]]; then
        "$PROJECT_ROOT/backendcpp/build/src/ainas-backend-cpp" &
        BACKENDCPP_PID=$!
    else
        "$PROJECT_ROOT/backendcpp/build/src/ainas-backend-cpp"
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
        # Ensure libpdfium.so and other bundled shared libraries are found
        export LD_LIBRARY_PATH="$PROJECT_ROOT/frontend/build/linux/x64/debug/bundle/lib:${LD_LIBRARY_PATH:-}"
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
    flutter build apk --release --android-skip-build-dependency-validation
    echo "Build Complete. APK located at: $PROJECT_ROOT/frontend/build/app/outputs/flutter-apk/app-release.apk"
    cd "$PROJECT_ROOT"
}

build_pyinstaller() {
    echo "Step: Building standalone binary with PyInstaller..."
    setup_python
    cd "$PROJECT_ROOT/backend"
    uv run pyinstaller ainas-backend.spec
    echo "Build Complete. Binary located at: $PROJECT_ROOT/backend/dist/ainas-backend"
    cd "$PROJECT_ROOT"
}

build_backend_image() {
    local variant="${BACKEND_IMAGE_VARIANT:-cpu}"

    # Derive version from git tag, or use commit hash as dev version
    local version
    if git describe --exact-match --tags HEAD &>/dev/null; then
        version="$(git describe --exact-match --tags HEAD)"
    else
        version="dev-$(git rev-parse --short HEAD)"
    fi

    echo "Step: Building Flutter Web (release)..."
    build_web

    echo "Step: Building backend Docker image (variant: $variant, version: $version)..."

    local tool
    if [[ "$CONTAINER_TOOL" == "podman" ]]; then
        tool="podman"
    else
        tool="docker"
    fi

    if ! command -v "$tool" &>/dev/null; then
        echo "Error: $tool not found. Install it or set --container-tool."
        exit 1
    fi

    local base_image torch_index cmake_args

    case "$variant" in
        cpu)
            base_image="python:3.12-slim"
            torch_index=""
            cmake_args=""
            ;;
        cuda)
            base_image="nvidia/cuda:12.4.1-runtime-ubuntu22.04"
            torch_index="https://download.pytorch.org/whl/cu124"
            cmake_args="-DGGML_CUDA=ON"
            ;;
        rocm)
            base_image="rocm/pytorch:rocm7.2.4_ubuntu24.04_py3.12_pytorch_release_2.10.0"
            torch_index="https://download.pytorch.org/whl/rocm7.2"
            cmake_args="-DGGML_HIPBLAS=ON"
            ;;
        *)
            echo "Error: Unknown variant '$variant'. Supported: cpu, cuda, rocm"
            exit 1
            ;;
    esac

    cd "$PROJECT_ROOT"
    $tool build \
        -t "ainas-backend:${version}-${variant}" \
        -t "ainas-backend:${variant}" \
        -f backend/containerize/Dockerfile \
        --build-arg "BASE_IMAGE=$base_image" \
        --build-arg "TORCH_INDEX_URL=$torch_index" \
        --build-arg "LLAMA_CPP_CMAKE_ARGS=$cmake_args" \
        .
    echo "Build Complete."
    echo "  ainas-backend:${version}-${variant}"
    echo "  ainas-backend:${variant}  (alias)"
    echo ""
    echo "Run with:"
    echo "  $tool run -p 9026:9026 -v ./storage:/app/storage ainas-backend:${variant}"
}

# ─── Release bundle builders ──────────────────────────────────────────

build_release_check_os() {
    local platform="$1"
    case "$platform" in
        linux)
            if [[ "$OSTYPE" != "linux-gnu"* ]]; then
                echo "Error: Linux release can only be built on Linux"; exit 1
            fi ;;
        macos|ios)
            if [[ "$OSTYPE" != "darwin"* ]]; then
                echo "Error: macOS/iOS release can only be built on macOS"; exit 1
            fi ;;
        windows)
            if [[ "$OSTYPE" != "msys"* && "$OSTYPE" != "cygwin"* && "$OSTYPE" != "mingw"* ]]; then
                echo "Error: Windows release can only be built on Windows"; exit 1
            fi ;;
        android)
            if [[ "$OSTYPE" != "linux-gnu"* && "$OSTYPE" != "darwin"* ]]; then
                echo "Error: Android release can only be built on Linux or macOS"; exit 1
            fi ;;
    esac
}

build_release_linux() {
    build_release_check_os linux
    echo "Step: Building Linux release bundle..."
    setup_flutter
    setup_cpp

    cd "$PROJECT_ROOT/frontend"
    echo "Step: Building Flutter Linux (release)..."
    flutter build linux --release
    cd "$PROJECT_ROOT"

    local release_dir="$PROJECT_ROOT/releases/ainas-full-linux"
    mkdir -p "$release_dir"

    cp -r "$PROJECT_ROOT/frontend/build/linux/x64/release/bundle/"* "$release_dir/"
    cp "$PROJECT_ROOT/backendcpp/build/src/ainas-backend-cpp" "$release_dir/"
    chmod +x "$release_dir/ainas-backend-cpp"

    echo "Step: Fixing RPATH in ELF binaries..."
    python3 -c "
import struct, os, sys

def vaddr_to_offset(segments, vaddr):
    for vs, off, sz in segments:
        if vs <= vaddr < vs + sz:
            return off + (vaddr - vs)
    return None

def fix_rpath(path):
    with open(path, 'r+b') as f:
        data = f.read()
        if data[:4] != b'\x7fELF' or data[4] != 2 or data[5] != 1:
            return
        e_phoff = struct.unpack_from('<Q', data, 0x20)[0]
        e_phnum = struct.unpack_from('<H', data, 0x38)[0]
        e_phentsize = struct.unpack_from('<H', data, 0x36)[0]
        segments = []
        phdr = e_phoff
        for _ in range(e_phnum):
            pt = struct.unpack_from('<I', data, phdr)[0]
            if pt == 1:
                po = struct.unpack_from('<Q', data, phdr + 8)[0]
                pv = struct.unpack_from('<Q', data, phdr + 0x10)[0]
                ps = struct.unpack_from('<Q', data, phdr + 0x20)[0]
                segments.append((pv, po, ps))
            phdr += e_phentsize
        phdr = e_phoff
        dv = ds = 0
        for _ in range(e_phnum):
            pt = struct.unpack_from('<I', data, phdr)[0]
            if pt == 2:
                dv = struct.unpack_from('<Q', data, phdr + 0x10)[0]
                ds = struct.unpack_from('<Q', data, phdr + 0x20)[0]
                break
            phdr += e_phentsize
        if not dv:
            return
        doff = vaddr_to_offset(segments, dv)
        if doff is None:
            return
        changed = False
        pos = doff
        while pos < doff + ds:
            tag = struct.unpack_from('<q', data, pos)[0]
            if tag == 0:
                break
            if tag == 29:  # DT_RUNPATH → DT_RPATH
                f.seek(pos)
                f.write(struct.pack('<q', 15))
                sys.stdout.write(f'  {path}: RUNPATH→RPATH\n')
                changed = True
                # If RPATH string is '\$ORIGIN/lib' and file is in lib/, fix to '\$ORIGIN'
            elif tag == 15 and b'\$ORIGIN/lib' in data:
                # Check if RPATH string has the wrong path
                pass
            pos += 16
        return changed

for root, dirs, files in os.walk('$release_dir'):
    for fn in files:
        fp = os.path.join(root, fn)
        try:
            fix_rpath(fp)
        except Exception:
            pass
" 2>&1 | grep -v '^$' || true

    echo "Step: Creating archive..."
    local archive="$release_dir/ainas-full-linux.tar.gz"
    tar czf "$archive" -C "$release_dir" .
    echo "Release built:"
    echo "  Directory: $release_dir/"
    echo "  Archive:   $archive"
}

build_release_macos() {
    build_release_check_os macos
    echo "Step: Building macOS release bundle..."
    setup_flutter

    cd "$PROJECT_ROOT/frontend"
    echo "Step: Building Flutter macOS (release)..."
    flutter build macos --release
    cd "$PROJECT_ROOT"

    echo "Step: Building C++ Backend..."
    setup_cpp

    local release_dir="$PROJECT_ROOT/releases/ainas-full-macos"
    mkdir -p "$release_dir"

    local app_path="$PROJECT_ROOT/frontend/build/macos/Build/Products/Release/Runner.app"
    if [ ! -d "$app_path" ]; then
        echo "Error: Flutter macOS app not found at $app_path"; exit 1
    fi

    cp -r "$app_path" "$release_dir/"
    cp "$PROJECT_ROOT/backendcpp/build/src/ainas-backend-cpp" \
       "$release_dir/Runner.app/Contents/MacOS/"
    chmod +x "$release_dir/Runner.app/Contents/MacOS/ainas-backend-cpp"

    echo "Step: Creating archive..."
    local archive="$release_dir/ainas-full-macos.zip"
    ditto -c -k --keepParent "Runner.app" "$archive"
    echo "Release built:"
    echo "  Directory: $release_dir/"
    echo "  Archive:   $archive"
}

build_release_windows() {
    build_release_check_os windows
    echo "Step: Building Windows release bundle (WinVer=$TARGET_WINDOWS_VER)..."

    setup_flutter

    cd "$PROJECT_ROOT/frontend"
    echo "Step: Building Flutter Windows (release)..."
    if [[ "$TARGET_WINDOWS_VER" != "0x0A00" ]]; then
        sed -i 's/set(TARGET_WINDOWS_VER "[^"]*"/set(TARGET_WINDOWS_VER "'"$TARGET_WINDOWS_VER"'"/' \
            windows/CMakeLists.txt
    fi
    flutter build windows --release
    cd "$PROJECT_ROOT"

    echo "Step: Building C++ Backend..."
    setup_cpp

    local release_dir="$PROJECT_ROOT/releases/ainas-full-windows"
    mkdir -p "$release_dir"

    cp -r "$PROJECT_ROOT/frontend/build/windows/x64/runner/Release/"* "$release_dir/"
    cp "$PROJECT_ROOT/backendcpp/build/src/Release/ainas-backend-cpp.exe" "$release_dir/" 2>/dev/null || \
    cp "$PROJECT_ROOT/backendcpp/build/src/ainas-backend-cpp.exe" "$release_dir/" 2>/dev/null || true

    echo "Step: Creating archive..."
    local archive="$release_dir/ainas-full-windows.zip"
    cd "$release_dir"
    # Prefer PowerShell Compress-Archive (Windows), fall back to zip
    powershell -Command "Compress-Archive -Path '*' -DestinationPath '$archive'" 2>/dev/null || \
    zip -r "$archive" .
    echo "Release built:"
    echo "  Directory: $release_dir/"
    echo "  Archive:   $archive"
}

build_release_android() {
    build_release_check_os android
    echo "Step: Building Android release bundle..."

    if [ -z "$ANDROID_SDK_ROOT" ] && [ -z "$ANDROID_HOME" ]; then
        echo "Error: ANDROID_SDK_ROOT or ANDROID_HOME must be set"
        exit 1
    fi

    setup_flutter

    cd "$PROJECT_ROOT/frontend"
    echo "Step: Building APK (release)..."
    flutter build apk --release --android-skip-build-dependency-validation
    cd "$PROJECT_ROOT"

    local ndk_path
    if [ -n "$ANDROID_SDK_ROOT" ]; then
        ndk_path=$(ls -d "$ANDROID_SDK_ROOT/ndk"/*/ 2>/dev/null | head -1)
    else
        ndk_path=$(ls -d "$ANDROID_HOME/ndk"/*/ 2>/dev/null | head -1)
    fi
    if [ -z "$ndk_path" ]; then
        echo "Error: Android NDK not found. Install it via sdkmanager: sdkmanager --install 'ndk;27.2.12479018'"
        exit 1
    fi
    echo "Step: Using NDK at $ndk_path"

    # SQLite amalgamation for cross-build
    if [ ! -f "$PROJECT_ROOT/backendcpp/vendor/sqlite3.c" ]; then
        echo "Step: Downloading SQLite amalgamation..."
        curl -fsSL https://www.sqlite.org/2024/sqlite-amalgamation-3460100.zip -o /tmp/sqlite-amal.zip
        unzip -q /tmp/sqlite-amal.zip -d /tmp
        cp /tmp/sqlite-amalgamation-*/sqlite3.{c,h} "$PROJECT_ROOT/backendcpp/vendor/"
        rm -rf /tmp/sqlite-amalgamation-* /tmp/sqlite-amal.zip
    fi

    local toolchain="$ndk_path/build/cmake/android.toolchain.cmake"
    local common_args="-DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE=$toolchain"
    common_args="$common_args -DANDROID_PLATFORM=android-24"
    common_args="$common_args -DSQLITE3_INCLUDE_DIRS=$PROJECT_ROOT/backendcpp/vendor"
    common_args="$common_args -DSQLITE3_LIBRARIES=$PROJECT_ROOT/backendcpp/vendor/sqlite3.c"

    echo "Step: Building C++ backend for arm64-v8a..."
    cmake -S "$PROJECT_ROOT/backendcpp" -B "$PROJECT_ROOT/build-android-arm64" \
        $common_args -DANDROID_ABI=arm64-v8a \
        -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
    cmake --build "$PROJECT_ROOT/build-android-arm64" --parallel --config Release

    echo "Step: Building C++ backend for x86_64..."
    cmake -S "$PROJECT_ROOT/backendcpp" -B "$PROJECT_ROOT/build-android-x86_64" \
        $common_args -DANDROID_ABI=x86_64 \
        -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
    cmake --build "$PROJECT_ROOT/build-android-x86_64" --parallel --config Release

    local apk="$PROJECT_ROOT/frontend/build/app/outputs/flutter-apk/app-release.apk"
    if [ ! -f "$apk" ]; then
        echo "Error: APK not found at $apk"; exit 1
    fi

    local release_dir="$PROJECT_ROOT/releases/ainas-full-android"
    mkdir -p "$release_dir"
    cp "$apk" "$release_dir/app-release.apk"

    echo "Step: Injecting backend binaries into APK..."
    local inject_dir="/tmp/apk-inject-$$"
    mkdir -p "$inject_dir/assets/backend/arm64-v8a"
    mkdir -p "$inject_dir/assets/backend/x86_64"

    cp "$PROJECT_ROOT/build-android-arm64/src/ainas-backend-cpp" \
       "$inject_dir/assets/backend/arm64-v8a/ainas-backend-cpp"
    cp "$PROJECT_ROOT/build-android-x86_64/src/ainas-backend-cpp" \
       "$inject_dir/assets/backend/x86_64/ainas-backend-cpp"

    cd "$inject_dir"
    zip -0 -r "$release_dir/app-release.apk" assets/
    cd "$PROJECT_ROOT"
    rm -rf "$inject_dir"

    echo "Release built:"
    echo "  APK: $release_dir/app-release.apk"
}

build_release_ios() {
    build_release_check_os ios
    echo "Step: Building iOS release bundle..."
    setup_flutter

    cd "$PROJECT_ROOT/frontend"
    echo "Step: Building Flutter iOS (release, no codesign)..."
    flutter build ios --release --no-codesign
    cd "$PROJECT_ROOT"

    # SQLite amalgamation for cross-build
    if [ ! -f "$PROJECT_ROOT/backendcpp/vendor/sqlite3.c" ]; then
        echo "Step: Downloading SQLite amalgamation..."
        curl -fsSL https://www.sqlite.org/2024/sqlite-amalgamation-3460100.zip -o /tmp/sqlite-amal.zip
        unzip -q /tmp/sqlite-amal.zip -d /tmp
        cp /tmp/sqlite-amalgamation-*/sqlite3.{c,h} "$PROJECT_ROOT/backendcpp/vendor/"
        rm -rf /tmp/sqlite-amalgamation-* /tmp/sqlite-amal.zip
    fi

    echo "Step: Building C++ backend for iOS (arm64)..."
    cmake -S "$PROJECT_ROOT/backendcpp" -B "$PROJECT_ROOT/build-ios-arm64" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
        -DCMAKE_OSX_SYSROOT="$(xcrun --sdk iphoneos --show-sdk-path)" \
        -DSQLITE3_INCLUDE_DIRS="$PROJECT_ROOT/backendcpp/vendor" \
        -DSQLITE3_LIBRARIES="$PROJECT_ROOT/backendcpp/vendor/sqlite3.c"
    cmake --build "$PROJECT_ROOT/build-ios-arm64" --parallel --config Release

    local app_path="$PROJECT_ROOT/frontend/build/ios/iphoneos/Runner.app"
    if [ ! -d "$app_path" ]; then
        echo "Error: iOS .app not found at $app_path"; exit 1
    fi

    local release_dir="$PROJECT_ROOT/releases/ainas-full-ios"
    mkdir -p "$release_dir"

    cp -r "$app_path" "$release_dir/"
    mkdir -p "$release_dir/Runner.app/Frameworks"
    cp "$PROJECT_ROOT/build-ios-arm64/src/ainas-backend-cpp" \
       "$release_dir/Runner.app/Frameworks/ainas-backend-cpp"
    chmod +x "$release_dir/Runner.app/Frameworks/ainas-backend-cpp"

    echo "Step: Creating archive..."
    local archive="$release_dir/ainas-full-ios.zip"
    ditto -c -k --keepParent "Runner.app" "$archive"
    echo "Release built:"
    echo "  Directory: $release_dir/"
    echo "  Archive:   $archive"
}

build_release() {
    local platform="${RELEASE_PLATFORM:-linux}"
    case "$platform" in
        linux)   build_release_linux ;;
        macos)   build_release_macos ;;
        windows) build_release_windows ;;
        android) build_release_android ;;
        ios)     build_release_ios ;;
    esac
}

case "$COMMAND" in
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
    --stop-observability)
        stop_observability
        ;;
    --rag)
        run_rag
        ;;
    --check-rag-health)
        check_rag_health
        ;;
    --logs-rag)
        show_rag_logs
        ;;
    --stop-rag)
        stop_rag
        ;;
    --backend)
        setup_python
        run_backend false
        ;;
    --build-cpp)
        setup_cpp
        ;;
    --backendcpp)
        setup_cpp
        run_backendcpp false
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
    --pyinstaller)
        build_pyinstaller
        ;;
    --build-web)
        build_web
        ;;
    --build-backend-image)
        build_backend_image
        ;;
    --release)
        build_release
        ;;
    --openapi)
        setup_python
        echo "Step: Exporting OpenAPI Schema..."
        PYTHONPATH="$PROJECT_ROOT" "$PROJECT_ROOT/backend/.venv/bin/python" -m backend.export_openapi
        ;;
    --all)
        run_rag
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
        
        trap "kill $BACKEND_PID $FRONTEND_PID 2>/dev/null; stop_observability; stop_rag; exit" INT TERM
        wait
        ;;
    *)
        echo "Error: Unknown command '$COMMAND'"
        show_usage
        exit 1
        ;;
esac