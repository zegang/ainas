#include "ainas/config/Config.hpp"

#include <cstdlib>
#include <stdexcept>

namespace ainas {

namespace {

std::string getEnv(const char* key, const std::string& defaultVal) {
    const char* val = std::getenv(key);
    return val ? std::string(val) : defaultVal;
}

} // anonymous namespace

Config Config::load() {
    Config config;
    config.addr = getEnv("AINAS_ADDR", "0.0.0.0");

    auto portStr = getEnv("AINAS_PORT", "9026");
    try {
        auto portVal = std::stoi(portStr);
        if (portVal < 1 || portVal > 65535) {
            throw std::out_of_range("port out of range");
        }
        config.port = static_cast<uint16_t>(portVal);
    } catch (...) {
        config.port = 9026;
    }

    config.storageRoot = std::filesystem::absolute(
        getEnv("AINAS_STORAGE_ROOT", "./storage"));

    config.dataPath = std::filesystem::absolute(
        getEnv("AINAS_DATA_PATH", (config.storageRoot / "nasdata").string()));
    config.dbPath = std::filesystem::absolute(
        getEnv("AINAS_DB_PATH", (config.storageRoot / ".db").string()));
    config.nasmetadataPath = std::filesystem::absolute(
        getEnv("AINAS_NASMETADATA_PATH", (config.storageRoot / ".nasmetadata").string()));

    auto maxUploadStr = getEnv("AINAS_MAX_UPLOAD_SIZE", "0");
    try {
        config.maxUploadSize = std::stoll(maxUploadStr);
    } catch (...) {
        config.maxUploadSize = 0;
    }

    auto aiEnabledStr = getEnv("AINAS_ENABLE_AI", "false");
    config.aiEnabled = (aiEnabledStr == "1" || aiEnabledStr == "true" || aiEnabledStr == "yes");

    auto cllamaPortStr = getEnv("CLLAMA_PORT", "9027");
    try {
        config.cllamaPort = std::stoi(cllamaPortStr);
    } catch (...) {
        config.cllamaPort = 9027;
    }

    config.cllamaModelsFolder = std::filesystem::absolute(
        getEnv("CLLAMA_MODELS_FOLDER", config.aiPath() / "models"));
    config.cllamaBinary = getEnv("CLLAMA_BINARY", "bin/cllama");

    return config;
}

void Config::rebase(const std::filesystem::path& newRoot) {
    storageRoot = std::filesystem::absolute(newRoot);
    dataPath = storageRoot / "nasdata";
    dbPath = storageRoot / ".db";
    nasmetadataPath = storageRoot / ".nasmetadata";

    std::error_code ec;
    std::filesystem::create_directories(dataPath, ec);
    std::filesystem::create_directories(dbPath, ec);
    std::filesystem::create_directories(thumbnailPath(), ec);
    std::filesystem::create_directories(aiPath(), ec);
    std::filesystem::create_directories(aiPath() / "models", ec);
}

} // namespace ainas
