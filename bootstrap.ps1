$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$ContainerTool = "docker"
$ReleasePlatform = ""
$BackendImageVariant = "cpu"
$TargetWindowsVer = "0x0A00"

# Load .env
$envFile = "$ProjectRoot\.env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^([^#=]+)=(.*)') {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2])
        }
    }
}

if (-not $env:NAS_HOST) { $env:NAS_HOST = "0.0.0.0" }
if (-not $env:NAS_PORT) { $env:NAS_PORT = "9026" }
if (-not $env:FRONTEND_PORT) { $env:FRONTEND_PORT = "8080" }

# Resolve advertise address
if ($env:NAS_HOST -eq "0.0.0.0") {
    $ip = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -eq "Dhcp" -or $_.PrefixOrigin -eq "Manual" } | Select-Object -First 1 -ExpandProperty IPAddress
    if (-not $ip) { $ip = "127.0.0.1" }
    $env:NAS_ADVERTISE_ADDR = $ip
} else {
    $env:NAS_ADVERTISE_ADDR = $env:NAS_HOST
}

if (-not $env:ENABLE_AI) { $env:ENABLE_AI = "false" }
if ($env:TARGET_WINDOWS_VER) { $TargetWindowsVer = $env:TARGET_WINDOWS_VER }

function Show-Usage {
    Write-Host @"
AI-NAS Bootstrap Script (PowerShell)
Usage: .\bootstrap.ps1 [OPTIONS]

Options:
  --upgrade      Upgrade Python and Flutter dependencies to latest allowed versions
  --outdated     Check for outdated Flutter dependencies
  --setup        Install Python dependencies and Flutter SDK submodule
  --backend      Setup and run only the FastAPI backend
  --backendcpp   Build and run the C++ (oatpp) backend
  --build-cpp    Build the C++ backend binary without running
  --platform     Frontend target (web, windows; default: auto)
  --openapi      Export the backend OpenAPI spec to openapi.json
  --container-tool Tool for services (docker; default: docker)
  --winver       Windows target version (0x0A00=Win10/11, 0x0601=Win7; default: 0x0A00)
  --frontend     Setup and run only the Flutter frontend
  --build-web    Compile the Flutter Web GUI for production
  --build-backend-image [cpu|cuda|rocm] Build frontend web + backend Docker image (default: cpu)
  --rag          Start RAG services (Elasticsearch/Kibana)
  --check-rag-health Check RAG services health (Elasticsearch)
  --logs-rag     View RAG service logs
  --stop-rag     Stop RAG services
  --observability Start Prometheus observability services
  --logs-observability View observability logs
  --stop-observability Stop observability services
  --web          Run the Flutter frontend as a web application
  --windows      Run the Flutter frontend as a native Windows app
  --android      Build the Android APK (Release)
  --release      Build full release bundle for platform (windows|android); use --winver to set Windows target version
  --all          Setup and run both backend and frontend (default)
  --help, -h     Show this help message

Environment Variables:
   NAS_HOST     Listening IP (default: 0.0.0.0)
   NAS_PORT     Listening port (default: 9026)
   FRONTEND_PORT Listening port for GUI (default: 8080)
   ENABLE_AI    Enable AI features (true/false, default: false)
   TARGET_WINDOWS_VER Windows target version (0x0A00=Win10/11, 0x0601=Win7; default: 0x0A00)
"@
}

# Parse arguments (manual, since we need --* style)
$cmdArgs = @()
$Command = ""
$i = 0
while ($i -lt $args.Count) {
    switch -Wildcard ($args[$i]) {
        "--platform" {
            $i++
            $env:FRONTEND_PLATFORM = $args[$i]
            break
        }
        "--container-tool" {
            $i++
            $ContainerTool = $args[$i]
            break
        }
        "--winver" {
            $i++
            if ($args[$i] -notmatch '^0x[0-9a-fA-F]{4}$') {
                Write-Host "Error: Invalid Windows version '$($args[$i])'. Use format 0x0A00 (Win10/11) or 0x0601 (Win7)."
                exit 1
            }
            $TargetWindowsVer = $args[$i]
            break
        }
        "--build-backend-image" {
            $Command = $args[$i]
            $i++
            if ($i -lt $args.Count -and $args[$i] -notlike "--*") {
                $BackendImageVariant = $args[$i]
            }
            break
        }
        "--release" {
            $Command = $args[$i]
            $i++
            if ($i -lt $args.Count -and $args[$i] -notlike "--*") {
                $ReleasePlatform = $args[$i]
            } else {
                Write-Host "Error: --release requires a platform argument (windows|android)"
                exit 1
            }
            break
        }
        "--help" { Show-Usage; exit 0 }
        "-h" { Show-Usage; exit 0 }
        "--*" {
            if (-not $Command) { $Command = $args[$i] } else { Write-Host "Error: Only one command allowed"; exit 1 }
            break
        }
        default { Write-Host "Error: Invalid option '$($args[$i])'"; Show-Usage; exit 1 }
    }
    $i++
}

if (-not $Command) { $Command = "--all" }

# Auto-detect platform
if (-not $env:FRONTEND_PLATFORM) {
    $env:FRONTEND_PLATFORM = "windows"
}

# ─── Functions ──────────────────────────────────────────

function Setup-Python {
    Write-Host "Step: Setting up Python Backend..."

    $uv = Get-Command uv -ErrorAction SilentlyContinue
    if (-not $uv) {
        Write-Host "uv not found. Installing..."
        powershell -c "irm https://astral.sh/uv/install.ps1 | iex"
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";$env:Path"
    }

    Set-Location "$ProjectRoot/backend"
    if (-not (Test-Path ".venv")) {
        Write-Host "Step: Synchronizing dependencies with uv sync..."
        uv sync
    }
    Set-Location $ProjectRoot
}

function Setup-Flutter {
    Write-Host "Step: Flutter..."

    $FlutterHome = "$ProjectRoot/vendor/flutter"
    $NuGetDir = "$ProjectRoot/vendor/nuget"
    $env:Path = "$FlutterHome/bin;$NuGetDir;$env:Path"

    if (-not (Test-Path "$FlutterHome/bin")) {
        Write-Host "Step: Initializing Flutter SDK submodule..."
        git submodule update --init --recursive vendor/flutter
    }

    if (-not (Test-Path "$NuGetDir/nuget.exe")) {
        Write-Host "Step: Downloading NuGet (required by flutter_tts plugin)..."
        New-Item -ItemType Directory -Force -Path $NuGetDir | Out-Null
        Invoke-WebRequest -Uri "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" -OutFile "$NuGetDir/nuget.exe"
    }

    Set-Location "$ProjectRoot/frontend"
    Write-Host "Step: Fetching Flutter dependencies..."
    flutter clean
    flutter pub get

    if (-not (Test-Path "windows")) {
        Write-Host "Step: Configuring Flutter project platforms..."
        flutter create . --platforms web,windows,android --description "A Flutter-based GUI for the AI-NAS."
    }
    Set-Location $ProjectRoot
}

function Build-Web {
    Write-Host "Step: Building Flutter Web GUI..."
    Setup-Flutter
    Set-Location "$ProjectRoot/frontend"
    flutter build web `
        --dart-define=NAS_HOST="$env:NAS_HOST" `
        --dart-define=NAS_PORT="$env:NAS_PORT" `
        --dart-define=ENABLE_AI="$env:ENABLE_AI" `
        --release
    Set-Location $ProjectRoot
}

function Run-Compose {
    param([string]$Action)
    $cmd = $null
    if ($ContainerTool -eq "docker") {
        if (Get-Command "docker" -ErrorAction SilentlyContinue) {
            $cmd = "docker"
        }
    }
    if ($cmd) {
        & $cmd compose $Action
    } else {
        Write-Host "Warning: $ContainerTool compose not found."
    }
}

function Run-Observability {
    if (-not (Test-Path "$ProjectRoot/observability")) { return }
    Write-Host "Step: Launching Observability Services (Prometheus)..."
    Set-Location "$ProjectRoot/observability"
    Run-Compose "up -d"
    Set-Location $ProjectRoot
}

function Stop-Observability {
    if (-not (Test-Path "$ProjectRoot/observability")) { return }
    Write-Host "Step: Stopping Observability Services (Prometheus)..."
    Set-Location "$ProjectRoot/observability"
    Run-Compose "down"
    Set-Location $ProjectRoot
}

function Run-Rag {
    if (-not (Test-Path "$ProjectRoot/thirdservices/rag")) { return }
    Write-Host "Step: Launching RAG Services (Elasticsearch/Kibana)..."
    Set-Location "$ProjectRoot/thirdservices/rag"
    Run-Compose "up -d"
    Set-Location $ProjectRoot
}

function Check-RagHealth {
    if (-not (Test-Path "$ProjectRoot/thirdservices/rag")) { return }
    Write-Host "Step: Checking RAG Services Health (Elasticsearch)..."
    curl.exe -s -X GET "http://localhost:9200/_cluster/health?pretty"
}

function Show-RagLogs {
    if (-not (Test-Path "$ProjectRoot/thirdservices/rag")) { return }
    Set-Location "$ProjectRoot/thirdservices/rag"
    Run-Compose "logs -f"
    Set-Location $ProjectRoot
}

function Stop-Rag {
    if (-not (Test-Path "$ProjectRoot/thirdservices/rag")) { return }
    Write-Host "Step: Stopping RAG Services (Elasticsearch/Kibana)..."
    Set-Location "$ProjectRoot/thirdservices/rag"
    Run-Compose "down"
    Set-Location $ProjectRoot
}

function Run-Backend {
    param([switch]$Background)
    Write-Host "Step: Launching Backend..."
    New-Item -ItemType Directory -Force -Path "$ProjectRoot/logs" | Out-Null

    $python = "$ProjectRoot/backend/.venv/Scripts/python.exe"
    $args = @("-m", "uvicorn", "backend.main:app", "--host", $env:NAS_HOST, "--port", $env:NAS_PORT)

    $env:NAS_ADVERTISE_ADDR = $env:NAS_ADVERTISE_ADDR
    $env:PYTHONUNBUFFERED = "1"

    if ($Background) {
        $script:BackendProcess = Start-Process -FilePath $python -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput "$ProjectRoot/logs/backend.log" -RedirectStandardError "$ProjectRoot/logs/backend.log"
        Write-Host "Backend PID: $($script:BackendProcess.Id)"
    } else {
        & $python $args
    }
}

function Setup-Cpp {
    param([string]$BuildType = "Release")
    Write-Host "Step: Building C++ Backend with CMake..."

    if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
        Write-Host "Error: cmake not found. Install CMake and ensure it is in PATH."
        exit 1
    }

    # Ensure oatpp submodule is initialized
    if (-not (Test-Path "$ProjectRoot/vendor/oatpp/CMakeLists.txt")) {
        Write-Host "Step: Initializing oatpp submodule..."
        git submodule update --init --recursive vendor/oatpp
    }

    $src = "$ProjectRoot/backendcpp"
    $build = "$ProjectRoot/backendcpp/build"
    $cmakeArgs = @("-S", $src, "-B", $build, "-DCMAKE_BUILD_TYPE=$BuildType", "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON", "-DTARGET_WINDOWS_VER=$TargetWindowsVer")

    # SQLite amalgamation fallback for Windows (where sqlite3-dev is typically unavailable)
    if (-not (Test-Path "$ProjectRoot/backendcpp/vendor/sqlite3.c")) {
        Write-Host "Step: Downloading SQLite amalgamation..."
        $sqliteUrl = "https://www.sqlite.org/2024/sqlite-amalgamation-3460100.zip"
        $zipPath = "$ProjectRoot/backendcpp/vendor/sqlite-amalgamation.zip"
        New-Item -ItemType Directory -Force -Path "$ProjectRoot/backendcpp/vendor" | Out-Null
        Invoke-WebRequest -Uri $sqliteUrl -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath "$ProjectRoot/backendcpp/vendor/" -Force
        Remove-Item -Path $zipPath -Force
        $extracted = Get-ChildItem "$ProjectRoot/backendcpp/vendor/sqlite-amalgamation-*" | Select-Object -First 1
        if ($extracted) {
            Copy-Item "$($extracted.FullName)/sqlite3.c" "$ProjectRoot/backendcpp/vendor/sqlite3.c"
            Copy-Item "$($extracted.FullName)/sqlite3.h" "$ProjectRoot/backendcpp/vendor/sqlite3.h"
            Remove-Item -Path $extracted.FullName -Recurse -Force
        }
    }

    # If amalgamation files exist, pass sqlite3.c as SQLite source.
    # CMakeLists.txt will detect the .c extension and compile it into a static library.
    if (Test-Path "$ProjectRoot/backendcpp/vendor/sqlite3.c") {
        $cmakeArgs += "-DSQLITE3_LIBRARIES=$ProjectRoot/backendcpp/vendor/sqlite3.c"
    }

    cmake @cmakeArgs
    if ($LASTEXITCODE -ne 0) { Write-Host "Error: CMake configuration failed"; exit 1 }

    cmake --build $build --config $BuildType
    if ($LASTEXITCODE -ne 0) { Write-Host "Error: CMake build failed"; exit 1 }
}

function Run-BackendCpp {
    param([switch]$Background)
    Write-Host "Step: Launching C++ Backend..."
    New-Item -ItemType Directory -Force -Path "$ProjectRoot/logs" | Out-Null

    $env:AINAS_ADDR = $env:NAS_HOST
    $env:AINAS_PORT = $env:NAS_PORT
    $env:AINAS_DATA_PATH = "$ProjectRoot/storage/nasdata"

    $binary = "$ProjectRoot/backendcpp/build/src/Release/ainas-backend-cpp.exe"
    if (-not (Test-Path $binary)) {
        $binary = "$ProjectRoot/backendcpp/build/src/ainas-backend-cpp.exe"
    }

    if ($Background) {
        $script:BackendCppProcess = Start-Process -FilePath $binary -NoNewWindow -PassThru
        Write-Host "C++ Backend PID: $($script:BackendCppProcess.Id)"
    } else {
        & $binary
    }
}

function Run-Frontend {
    param([switch]$Background)
    $env:NO_PROXY = ""

    Set-Location "$ProjectRoot/frontend"
    if ($env:FRONTEND_PLATFORM -eq "windows") {
        Write-Host "Step: Launching Frontend (Native Windows)..."
        if ($Background) {
            $script:FrontendProcess = Start-Process -FilePath "flutter" -ArgumentList @("run", "-d", "windows",
                "--dart-define=NAS_HOST=$env:NAS_HOST",
                "--dart-define=NAS_PORT=$env:NAS_PORT",
                "--dart-define=ENABLE_AI=$env:ENABLE_AI") -NoNewWindow -PassThru
        } else {
            flutter run -d windows `
                --dart-define=NAS_HOST="$env:NAS_HOST" `
                --dart-define=NAS_PORT="$env:NAS_PORT" `
                --dart-define=ENABLE_AI="$env:ENABLE_AI"
        }
    } else {
        Write-Host "Step: Launching Frontend (Web Server)..."
        if ($Background) {
            $script:FrontendProcess = Start-Process -FilePath "flutter" -ArgumentList @("run", "-d", "web-server",
                "--web-port", $env:FRONTEND_PORT,
                "--web-hostname", $env:NAS_HOST,
                "--dart-define=NAS_HOST=$env:NAS_HOST",
                "--dart-define=NAS_PORT=$env:NAS_PORT",
                "--dart-define=ENABLE_AI=$env:ENABLE_AI") -NoNewWindow -PassThru
        } else {
            flutter run -d web-server `
                --web-port "$env:FRONTEND_PORT" `
                --web-hostname "$env:NAS_HOST" `
                --dart-define=NAS_HOST="$env:NAS_HOST" `
                --dart-define=NAS_PORT="$env:NAS_PORT" `
                --dart-define=ENABLE_AI="$env:ENABLE_AI"
        }
    }
    Set-Location $ProjectRoot
}

function Build-Android {
    Write-Host "Step: Building Android APK..."
    Setup-Flutter
    Set-Location "$ProjectRoot/frontend"
    flutter build apk --release --android-skip-build-dependency-validation
    Write-Host "Build Complete. APK located at: $ProjectRoot/frontend/build/app/outputs/flutter-apk/app-release.apk"
    Set-Location $ProjectRoot
}

function Build-BackendImage {
    Write-Host "Step: Building Flutter Web (release)..."
    Build-Web

    Write-Host "Step: Building backend Docker image (variant: $BackendImageVariant)..."
    $tool = if ($ContainerTool -eq "podman") { "podman" } else { "docker" }
    
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "Error: $tool not found."
        exit 1
    }

    $baseImage = switch ($BackendImageVariant) {
        "cpu"  { "python:3.12-slim" }
        "cuda" { "nvidia/cuda:12.4.1-runtime-ubuntu22.04" }
        "rocm" { "rocm/pytorch:rocm7.2.4_ubuntu24.04_py3.12_pytorch_release_2.10.0" }
    }
    $torchIndex = switch ($BackendImageVariant) {
        "cuda" { "https://download.pytorch.org/whl/cu124" }
        "rocm" { "https://download.pytorch.org/whl/rocm7.2" }
        default { "" }
    }
    $cmakeArgs = switch ($BackendImageVariant) {
        "cuda" { "-DGGML_CUDA=ON" }
        "rocm" { "-DGGML_HIPBLAS=ON" }
        default { "" }
    }

    Set-Location $ProjectRoot
    & $tool build -t "ainas-backend:latest" -f backend/containerize/Dockerfile `
        --build-arg "BASE_IMAGE=$baseImage" `
        --build-arg "TORCH_INDEX_URL=$torchIndex" `
        --build-arg "LLAMA_CPP_CMAKE_ARGS=$cmakeArgs" .
}

function Build-ReleaseWindows {
    Write-Host "Step: Building Windows release bundle (WinVer=$TargetWindowsVer)..."
    Setup-Flutter

    Set-Location "$ProjectRoot/frontend"
    Write-Host "Step: Building Flutter Windows (release)..."
    if ($TargetWindowsVer -ne "0x0A00") {
        (Get-Content windows/CMakeLists.txt) -replace 'set\(TARGET_WINDOWS_VER "[^"]*"', 'set(TARGET_WINDOWS_VER "' + $TargetWindowsVer + '"' | Set-Content windows/CMakeLists.txt
    }
    flutter build windows --release; if (-not $?) { Write-Host "Error: Flutter Windows build failed"; exit 1 }
    Set-Location $ProjectRoot

    Write-Host "Step: Building C++ Backend..."
    Setup-Cpp

    $releaseDir = "$ProjectRoot/releases/ainas-full-windows"
    New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null

    Copy-Item "$ProjectRoot/frontend/build/windows/x64/runner/Release/*" -Destination $releaseDir -Recurse -Force
    $cppExe = "$ProjectRoot/backendcpp/build/src/Release/ainas-backend-cpp.exe"
    if (Test-Path $cppExe) {
        Copy-Item $cppExe -Destination $releaseDir -Force
    }

    Write-Host "Step: Creating archive..."
    $archive = "$releaseDir/ainas-full-windows.zip"
    Compress-Archive -Path "$releaseDir/*" -DestinationPath $archive -Force
    Write-Host "Release built:"
    Write-Host "  Directory: $releaseDir/"
    Write-Host "  Archive:   $archive"
}

function Build-ReleaseAndroid {
    Write-Host "Step: Building Android release bundle..."

    if (-not $env:ANDROID_SDK_ROOT -and -not $env:ANDROID_HOME) {
        Write-Host "Error: ANDROID_SDK_ROOT or ANDROID_HOME must be set"
        exit 1
    }

    Setup-Flutter

    Set-Location "$ProjectRoot/frontend"
    Write-Host "Step: Building APK (release)..."
    flutter build apk --release --android-skip-build-dependency-validation
    Set-Location $ProjectRoot

    # SQLite amalgamation
    if (-not (Test-Path "$ProjectRoot/backendcpp/vendor/sqlite3.c")) {
        Write-Host "Step: Downloading SQLite amalgamation..."
        Invoke-WebRequest -Uri "https://www.sqlite.org/2024/sqlite-amalgamation-3460100.zip" -OutFile "/tmp/sqlite-amal.zip"
        Expand-Archive -Path "/tmp/sqlite-amal.zip" -DestinationPath "/tmp/" -Force
        Copy-Item "/tmp/sqlite-amalgamation-*/sqlite3.c" "$ProjectRoot/backendcpp/vendor/"
        Copy-Item "/tmp/sqlite-amalgamation-*/sqlite3.h" "$ProjectRoot/backendcpp/vendor/"
    }

    Write-Host "Step: Building C++ backend for arm64-v8a (not supported on Windows host)..."
    Write-Host "  Skipping Android NDK cross-build on Windows."
}

function Build-Release {
    param([string]$Platform)
    switch ($Platform) {
        "windows" { Build-ReleaseWindows }
        "android" { Build-ReleaseAndroid }
        default { Write-Host "Error: Unsupported platform '$Platform' on Windows"; exit 1 }
    }
}

# ─── Command Dispatch ──────────────────────────────────

switch ($Command) {
    "--upgrade" {
        Setup-Python
        $env:Path = "$ProjectRoot/vendor/flutter/bin;$env:Path"
        Set-Location "$ProjectRoot/frontend"
        flutter clean
        flutter pub upgrade --major-versions
        Set-Location $ProjectRoot
    }
    "--outdated" {
        $env:Path = "$ProjectRoot/vendor/flutter/bin;$env:Path"
        Set-Location "$ProjectRoot/frontend"
        flutter pub outdated
        Set-Location $ProjectRoot
    }
    "--setup" {
        Setup-Python
        Setup-Flutter
    }
    "--observability" { Run-Observability }
    "--stop-observability" { Stop-Observability }
    "--rag" { Run-Rag }
    "--check-rag-health" { Check-RagHealth }
    "--logs-rag" { Show-RagLogs }
    "--stop-rag" { Stop-Rag }
    "--backend" {
        Setup-Python
        Run-Backend
    }
    "--build-cpp" { Setup-Cpp }
    "--backendcpp" {
        Setup-Cpp
        Run-BackendCpp
    }
    "--frontend" {
        Setup-Flutter
        Run-Frontend
    }
    "--windows" {
        Setup-Flutter
        $env:FRONTEND_PLATFORM = "windows"
        Run-Frontend
    }
    "--web" {
        Setup-Flutter
        $env:FRONTEND_PLATFORM = "web"
        Run-Frontend
    }
    "--android" { Build-Android }
    "--build-web" { Build-Web }
    "--build-backend-image" { Build-BackendImage }
    "--release" { Build-Release -Platform $ReleasePlatform }
    "--openapi" {
        Setup-Python
        Write-Host "Step: Exporting OpenAPI Schema..."
        & "$ProjectRoot/backend/.venv/Scripts/python.exe" -m backend.export_openapi
    }
    "--all" {
        Run-Rag
        Run-Observability
        Setup-Python
        Setup-Flutter
        Run-Backend -Background
        Run-Frontend -Background

        Start-Sleep -Seconds 5
        Write-Host @"
AI-NAS is running.
Backend API:  http://$env:NAS_ADVERTISE_ADDR:$env:NAS_PORT
Swagger UI:   http://$env:NAS_ADVERTISE_ADDR:$env:NAS_PORT/docs
Prometheus:   http://localhost:9090
Backend Logs: $ProjectRoot/logs/backend.log
Frontend GUI: http://$env:NAS_ADVERTISE_ADDR:$env:FRONTEND_PORT
"@

        Write-Host "Press Ctrl+C to stop..."
        while ($true) { Start-Sleep -Seconds 1 }
    }
    default {
        Write-Host "Error: Unknown command '$Command'"
        Show-Usage
        exit 1
    }
}
