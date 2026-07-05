#pragma once

#include "ainas/config/Config.hpp"
#include "ainas/database/SyncConfigRepository.hpp"
#include "ainas/database/SyncFileManifestRepository.hpp"

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace ainas {

class SyncService {
public:
    SyncService(std::shared_ptr<Config> config,
                SyncConfigRepository& configRepo,
                SyncFileManifestRepository& manifestRepo);

    struct FileEntry {
        std::string path;
        int64_t size{0};
        std::string modifiedAt;
    };

    struct DiffResult {
        bool success{false};
        std::string message;
        std::vector<FileEntry> filesToUpload;
        std::vector<FileEntry> serverFiles;
    };

    DiffResult diffManifest(int64_t configId,
                            const std::vector<FileEntry>& clientFiles);

    void commitFiles(int64_t configId,
                     const std::vector<std::string>& paths);

    int64_t getTargetFileCount(int64_t configId) const;
    int64_t getSyncedFileCount(int64_t configId) const;

    std::string validateTargetPath(const std::string& targetPath,
                                   std::optional<int64_t> excludeId = std::nullopt) const;

    std::filesystem::path resolveTargetDir(int64_t configId) const;

private:
    std::shared_ptr<Config> m_config;
    SyncConfigRepository& m_configRepo;
    SyncFileManifestRepository& m_manifestRepo;
};

} // namespace ainas
