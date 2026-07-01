#pragma once

#include <filesystem>
#include <string>
#include <cstdint>

namespace ainas {

struct Config {
    std::string addr{"0.0.0.0"};
    uint16_t port{9026};
    std::filesystem::path storageRoot{"./storage"};
    std::filesystem::path dataPath;
    std::filesystem::path dbPath;
    std::filesystem::path nasmetadataPath;
    int64_t maxUploadSize{0};

    bool aiEnabled{false};
    int cllamaPort{9027};
    std::filesystem::path cllamaModelsFolder{"./models"};
    std::filesystem::path cllamaBinary{"cllama"};

    std::filesystem::path thumbnailPath() const { return nasmetadataPath / "thumbnails"; }
    std::filesystem::path aiPath() const { return nasmetadataPath / "ai"; }

    void rebase(const std::filesystem::path& newRoot);

    static Config load();
};

} // namespace ainas
