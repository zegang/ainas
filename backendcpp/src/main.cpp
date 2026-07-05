#include "ainas/config/Config.hpp"
#include "ainas/database/Database.hpp"
#include "ainas/database/ConfigRepository.hpp"
#include "ainas/database/FileRepository.hpp"
#include "ainas/database/UserRepository.hpp"
#include "ainas/dto/DTOs.hpp"
#include "ainas/logging/Logger.hpp"
#include "ainas/platform/Platform.hpp"
#include "ainas/service/FileService.hpp"
#include "ainas/service/PdfService.hpp"
#include "ainas/service/ThumbnailService.hpp"
#include "ainas/service/AiService.hpp"
#include "ainas/controller/ConfigController.hpp"
#include "ainas/controller/FilesController.hpp"
#include "ainas/controller/SystemController.hpp"
#include "ainas/controller/AiController.hpp"
#include "ainas/controller/UserController.hpp"
#include "ainas/database/SyncConfigRepository.hpp"
#include "ainas/database/SyncFileManifestRepository.hpp"
#include "ainas/service/SyncService.hpp"
#include "ainas/controller/SyncController.hpp"
#include "ainas/mdns/MdnsService.hpp"
#include "ainas/util/cflag.hpp"

#include "oatpp/network/Server.hpp"
#include "oatpp/network/tcp/server/ConnectionProvider.hpp"
#include "oatpp/web/server/HttpConnectionHandler.hpp"
#include "oatpp/web/server/HttpRouter.hpp"
#include "oatpp/web/server/interceptor/AllowCorsGlobal.hpp"
#include "oatpp/json/ObjectMapper.hpp"

#include <atomic>
#include <csignal>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <fcntl.h>
#include <iostream>
#include <memory>

namespace {

std::atomic<bool>& running() {
    static std::atomic<bool> r{true};
    return r;
}

void signalHandler(int sig) {
    LOG_INFO("Received signal {}, shutting down...", sig);
    running() = false;
}

// Global pointer so termination handlers can stop cllama on crash.
std::shared_ptr<ainas::AiService> g_aiService;

void stopAiService() {
    if (auto svc = g_aiService) {
        svc->stop();
    }
}

// ── Crash-safe logging helpers ──────────────────────────────────────
// These avoid the Logger (mutex, std::format) to work even in corrupt state.

static void crashLog(const char* msg) {
    ainas::platform::safeWrite(2, msg);
    ainas::platform::safeWrite(2, "\n");

    // Also append to the log file if the Logger is alive
    try {
        auto& logger = ainas::Logger::instance();
        auto path = logger.getLogFilePath();
        if (!path.empty()) {
            int fd = ainas::platform::safeOpen(path.c_str(), O_WRONLY | O_APPEND | O_CREAT, 0644);
            if (fd >= 0) {
                ainas::platform::safeWrite(fd, msg);
                ainas::platform::safeWrite(fd, "\n");
                ainas::platform::safeClose(fd);
            }
        }
    } catch (...) {
        // Logger not yet initialised — ignore
    }
}

// ── Termination / crash handlers ────────────────────────────────────

void terminateHandler() {
    crashLog("=== UNEXPECTED TERMINATION ===");

    // Try to extract exception info
    try {
        if (auto exc = std::current_exception()) {
            try {
                std::rethrow_exception(exc);
            } catch (const std::exception& e) {
                crashLog("Exception type: std::exception");
                crashLog(e.what());
            } catch (const std::string& s) {
                crashLog("Exception type: std::string");
                crashLog(s.c_str());
            } catch (const char* s) {
                crashLog("Exception type: char*");
                crashLog(s);
            } catch (...) {
                crashLog("Exception type: unknown (not derived from std::exception)");
            }
        } else {
            crashLog("No active exception (likely stack overflow / pure virtual call)");
        }
    } catch (...) {
        crashLog("Failed to query exception info");
    }

    crashLog("Stopping services...");
    stopAiService();
    crashLog("Aborting...");

    // Restore default SIGABRT so the core dump / process kill works
    signal(SIGABRT, SIG_DFL);
    abort();
}

void sigabrtHandler(int) {
    crashLog("FATAL: SIGABRT received (direct abort() or assertion failure)");

    stopAiService();

    // Restore default and re-raise to get a core dump / OS termination
    signal(SIGABRT, SIG_DFL);
    raise(SIGABRT);
}

void setEnvVar(const char* name, const char* value) {
    ainas::platform::setEnv(name, value);
}

void applyFlags(const ainas::util::FlagParser& flags) {
    if (flags.has("addr")) {
        setEnvVar("AINAS_ADDR", flags.get("addr").c_str());
    }
    if (flags.has("port")) {
        setEnvVar("AINAS_PORT", flags.get("port").c_str());
    }
    if (flags.has("storage")) {
        setEnvVar("AINAS_STORAGE_ROOT", flags.get("storage").c_str());
    }
    if (flags.has("storage-root-path")) {
        setEnvVar("AINAS_STORAGE_ROOT", flags.get("storage-root-path").c_str());
    }
    if (flags.has("log-level")) {
        setEnvVar("AINAS_LOG_LEVEL", flags.get("log-level").c_str());
    }
    if (flags.has("log-file")) {
        setEnvVar("AINAS_LOG_FILE", flags.get("log-file").c_str());
    }
}

void daemonize() {
    if (!ainas::platform::daemonize()) {
        std::cerr << "Daemon: failed to daemonize\n";
        exit(EXIT_FAILURE);
    }
}

ainas::LogLevel parseLogLevel() {
    if (auto* env = std::getenv("AINAS_LOG_LEVEL")) {
        std::string_view lvl(env);
        if (lvl == "trace") return ainas::LogLevel::Trace;
        if (lvl == "debug") return ainas::LogLevel::Debug;
        if (lvl == "warn")  return ainas::LogLevel::Warn;
        if (lvl == "error") return ainas::LogLevel::Error;
    }
    return ainas::LogLevel::Info;
}

} // anonymous namespace

int main(int argc, const char* argv[]) {
    ainas::util::FlagParser flags(argc, argv);

    applyFlags(flags);

    bool isDaemon = flags.has("daemon");

    if (isDaemon) {
        if (!ainas::platform::daemonize()) {
            std::cerr << "Warning: --daemon is not supported on this platform, running in foreground\n";
            isDaemon = false;
        }
    }

    oatpp::Environment::init();

    auto config = std::make_shared<ainas::Config>(ainas::Config::load());

    {
        ainas::Logger::Config logCfg;
        logCfg.level = parseLogLevel();
        logCfg.console = !isDaemon;
        if (auto* env = std::getenv("AINAS_LOG_FILE")) {
            logCfg.filePath = env;
        } else {
            logCfg.filePath = (std::filesystem::path(argv[0]).parent_path() / "ainas_backend.log").string();
        }
        ainas::Logger::init(std::move(logCfg));
    }

    std::error_code ec2;
    auto binaryPath = std::filesystem::canonical(argv[0], ec2);
    LOG_INFO("Binary path: {}", ec2 ? argv[0] : binaryPath.string());
    LOG_INFO("Starting AINAS C++ backend on {}:{}", config->addr, config->port);
    LOG_INFO("Data path: {}", config->dataPath.string());
    LOG_INFO("DB path: {}", config->dbPath.string());
    LOG_INFO("Nasmetadata path: {} (thumbnails: {}, ai: {})",
             config->nasmetadataPath.string(),
             config->thumbnailPath().string(),
             config->aiPath().string());

    std::error_code ec;
    std::filesystem::create_directories(config->thumbnailPath(), ec);
    std::filesystem::create_directories(config->aiPath(), ec);

    // Register crash handler to stop cllama on unhandled exceptions / terminate
    std::set_terminate(terminateHandler);

    auto objectMapper = std::make_shared<oatpp::json::ObjectMapper>();

    auto database = std::make_unique<ainas::Database>(
        config->dbPath / "metadata.db");
    auto fileService = std::make_shared<ainas::FileService>(
        config, *database);
    auto router = oatpp::web::server::HttpRouter::createShared();

    auto thumbnailService = std::make_shared<ainas::ThumbnailService>(config);
    auto pdfService = std::make_shared<ainas::PdfService>(config);
    auto filesController = ainas::FilesController::createShared(
        objectMapper, fileService, config, pdfService, thumbnailService);

    auto aiService = std::make_shared<ainas::AiService>(config);
    g_aiService = aiService;
    aiService->start();

    router->addController(filesController);
    router->addController(ainas::SystemController::createShared(objectMapper, config, aiService->state()));
    router->addController(ainas::AiController::createShared(objectMapper, config, aiService->state(), aiService));

    auto configRepo = std::make_shared<ainas::ConfigRepository>(*database);
    configRepo->migrate();
    router->addController(ainas::ConfigController::createShared(objectMapper, configRepo));

    auto userRepo = std::make_shared<ainas::UserRepository>(*database);
    userRepo->migrate();
    router->addController(ainas::UserController::createShared(objectMapper, userRepo));

    auto syncRepo = std::make_shared<ainas::SyncConfigRepository>(*database);
    syncRepo->migrate();
    fileService->setSyncConfigRepo(syncRepo.get());
    auto syncManifestRepo = std::make_shared<ainas::SyncFileManifestRepository>(*database);
    syncManifestRepo->migrate();
    auto syncService = std::make_shared<ainas::SyncService>(config, *syncRepo, *syncManifestRepo);
    router->addController(ainas::SyncController::createShared(objectMapper, syncRepo, syncService));

    oatpp::network::Address address(
        config->addr.c_str(),
        config->port,
        oatpp::network::Address::IP_4);

    auto connectionProvider =
        oatpp::network::tcp::server::ConnectionProvider::createShared(address);
    auto connectionHandler =
        oatpp::web::server::HttpConnectionHandler::createShared(router);

    auto corsMethods = oatpp::String("GET, POST, PUT, DELETE, PATCH, OPTIONS");
    connectionHandler->addRequestInterceptor(
        std::make_shared<oatpp::web::server::interceptor::AllowOptionsGlobal>());
    connectionHandler->addResponseInterceptor(
        std::make_shared<oatpp::web::server::interceptor::AllowCorsGlobal>("*", corsMethods));

    auto mdnsService = std::make_shared<ainas::MdnsService>(config->addr, config->port);
    mdnsService->start();

    oatpp::network::Server server(connectionProvider, connectionHandler);

    signal(SIGINT, signalHandler);
    signal(SIGTERM, signalHandler);
    signal(SIGABRT, sigabrtHandler);

    LOG_INFO("Server running. Press Ctrl+C to stop.");
    server.run([&]() { return running().load(); });

    LOG_INFO("Server stopped.");
    aiService->stop();
    mdnsService->stop();
    oatpp::Environment::destroy();
    return 0;
}
