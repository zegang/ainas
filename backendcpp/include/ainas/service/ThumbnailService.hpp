#pragma once

#include "ainas/config/Config.hpp"
#include "ainas/logging/Logger.hpp"

#include <filesystem>
#include <memory>
#include <string>

namespace ainas {

class ThumbnailService {
public:
    explicit ThumbnailService(std::shared_ptr<Config> config);

    bool generate(const std::filesystem::path& relPath);

    bool exists(const std::filesystem::path& relPath) const;

    std::filesystem::path thumbnailPath(const std::filesystem::path& relPath) const;

    bool remove(const std::filesystem::path& relPath) const;

    bool move(const std::filesystem::path& oldRelPath,
              const std::filesystem::path& newRelPath);

    bool copy(const std::filesystem::path& srcRelPath,
              const std::filesystem::path& dstRelPath);

    static bool isSupportedImage(const std::filesystem::path& path);

private:
    std::shared_ptr<Config> m_config;
};

} // namespace ainas
