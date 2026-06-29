#include "ainas/config/Config.hpp"
#include "ainas/database/Database.hpp"
#include "ainas/database/ConfigRepository.hpp"
#include "ainas/database/FileRepository.hpp"
#include "ainas/dto/DTOs.hpp"
#include "ainas/logging/Logger.hpp"
#include "ainas/service/FileService.hpp"
#include "ainas/service/ThumbnailService.hpp"
#include "ainas/controller/ConfigController.hpp"
#include "ainas/controller/FilesController.hpp"
#include "ainas/controller/SystemController.hpp"
#include "ainas/controller/AiController.hpp"
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
#include <iostream>

#if defined(__unix__) || defined(__APPLE__)
#include <fcntl.h>
#include <unistd.h>
#endif

namespace {

std::atomic<bool>& running() {
    static std::atomic<bool> r{true};
    return r;
}

void signalHandler(int sig) {
    LOG_INFO("Received signal {}, shutting down...", sig);
    running() = false;
}

void applyFlags(const ainas::util::FlagParser& flags) {
    if (flags.has("addr")) {
        setenv("AINAS_ADDR", flags.get("addr").c_str(), 1);
    }
    if (flags.has("port")) {
        setenv("AINAS_PORT", flags.get("port").c_str(), 1);
    }
    if (flags.has("storage")) {
        setenv("AINAS_STORAGE_ROOT", flags.get("storage").c_str(), 1);
    }
    if (flags.has("storage-root-path")) {
        setenv("AINAS_STORAGE_ROOT", flags.get("storage-root-path").c_str(), 1);
    }
    if (flags.has("log-level")) {
        setenv("AINAS_LOG_LEVEL", flags.get("log-level").c_str(), 1);
    }
    if (flags.has("log-file")) {
        setenv("AINAS_LOG_FILE", flags.get("log-file").c_str(), 1);
    }
}

#if defined(__unix__) || defined(__APPLE__)
void daemonize() {
    pid_t pid = fork();
    if (pid < 0) {
        std::cerr << "Daemon: fork failed\n";
        exit(EXIT_FAILURE);
    }
    if (pid > 0) {
        // Parent exits
        exit(EXIT_SUCCESS);
    }

    // Child: new session
    if (setsid() < 0) {
        std::cerr << "Daemon: setsid failed\n";
        exit(EXIT_FAILURE);
    }

    // Ignore SIGHUP
    signal(SIGHUP, SIG_IGN);

    // Second fork to fully detach
    pid = fork();
    if (pid < 0) {
        std::cerr << "Daemon: second fork failed\n";
        exit(EXIT_FAILURE);
    }
    if (pid > 0) {
        exit(EXIT_SUCCESS);
    }

    // Redirect stdio to /dev/null
    int fd = open("/dev/null", O_RDWR);
    if (fd >= 0) {
        dup2(fd, STDIN_FILENO);
        dup2(fd, STDOUT_FILENO);
        dup2(fd, STDERR_FILENO);
        if (fd > 2) close(fd);
    }
}
#endif

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

    // CLI flags override environment variables
    applyFlags(flags);

    bool isDaemon = flags.has("daemon");

    // Daemonize before logger init (stdio gets redirected to /dev/null)
#if defined(__unix__) || defined(__APPLE__)
    if (isDaemon) {
        daemonize();
    }
#else
    if (isDaemon) {
        std::cerr << "Warning: --daemon is not supported on this platform, running in foreground\n";
        isDaemon = false;
    }
#endif

    oatpp::Environment::init();

    auto config = std::make_shared<ainas::Config>(ainas::Config::load());

    // Initialize logging
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

    LOG_INFO("Starting AINAS C++ backend on {}:{}", config->addr, config->port);
    LOG_INFO("Data path: {}", config->dataPath.string());
    LOG_INFO("DB path: {}", config->dbPath.string());
    LOG_INFO("Nasmetadata path: {} (thumbnails: {}, ai: {})",
             config->nasmetadataPath.string(),
             config->thumbnailPath().string(),
             config->aiPath().string());

    // Ensure metadata subdirectories exist
    std::error_code ec;
    std::filesystem::create_directories(config->thumbnailPath(), ec);
    std::filesystem::create_directories(config->aiPath(), ec);

    auto objectMapper = std::make_shared<oatpp::json::ObjectMapper>();

    auto database = std::make_unique<ainas::Database>(
        config->dbPath / "metadata.db");
    auto fileService = std::make_shared<ainas::FileService>(
        config, *database);
    auto router = oatpp::web::server::HttpRouter::createShared();

    auto thumbnailService = std::make_shared<ainas::ThumbnailService>(config);
    auto filesController = ainas::FilesController::createShared(
        objectMapper, fileService, config, thumbnailService);
    router->addController(filesController);

    auto systemController = ainas::SystemController::createShared(
        objectMapper, config);
    router->addController(systemController);

    auto aiController = ainas::AiController::createShared(
        objectMapper, config);
    router->addController(aiController);

    auto configRepo = std::make_shared<ainas::ConfigRepository>(*database);
    configRepo->migrate();
    auto configController = ainas::ConfigController::createShared(
        objectMapper, configRepo);
    router->addController(configController);

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

    LOG_INFO("Server running. Press Ctrl+C to stop.");
    server.run([&]() { return running().load(); });

    LOG_INFO("Server stopped.");
    mdnsService->stop();
    oatpp::Environment::destroy();
    return 0;
}
