#include "ainas/service/SyncService.hpp"
#include "ainas/logging/Logger.hpp"

#include <filesystem>
#include <system_error>

namespace ainas {

SyncService::SyncService(std::shared_ptr<Config> config,
                          SyncConfigRepository& configRepo,
                          SyncFileManifestRepository& manifestRepo)
    : m_config(std::move(config))
    , m_configRepo(configRepo)
    , m_manifestRepo(manifestRepo)
{}

std::string SyncService::validateTargetPath(
    const std::string& targetPath,
    std::optional<int64_t> excludeId) const
{
    auto existing = m_configRepo.findByTargetPath(targetPath);
    for (const auto& e : existing) {
        if (excludeId && e.id == *excludeId) {
            continue;
        }
        LOG_WARN("validateTargetPath: target path '{}' already used by config id={} name='{}'",
                 targetPath, static_cast<long>(e.id), e.name);
        return "Target path is already in use by sync config \"" + e.name + "\"";
    }
    return {};
}

std::filesystem::path SyncService::resolveTargetDir(int64_t configId) const {
    auto config = m_configRepo.findById(configId);
    if (!config) {
        LOG_WARN("resolveTargetDir: config not found");
        return {};
    }
    std::string targetPath = config->targetPath;
    while (!targetPath.empty() && targetPath.front() == '/') {
        targetPath.erase(0, 1);
    }
    auto result = std::filesystem::path(m_config->dataPath) / targetPath;
    LOG_INFO("resolveTargetDir: dataPath='{}', targetPath='{}', result='{}'",
             m_config->dataPath.string(), targetPath, result.string());
    return result;
}

SyncService::DiffResult SyncService::diffManifest(
    int64_t configId,
    const std::vector<FileEntry>& clientFiles)
{
    LOG_INFO("diffManifest: configId={} clientFiles={}",
             static_cast<long>(configId), static_cast<long>(clientFiles.size()));

    auto config = m_configRepo.findById(configId);
    if (!config) {
        LOG_WARN("diffManifest: config not found id={}", static_cast<long>(configId));
        return {false, "Sync config not found", {}, {}};
    }

    auto serverEntries = m_manifestRepo.findByConfigId(configId);
    LOG_INFO("diffManifest: server has {} manifest entries", static_cast<long>(serverEntries.size()));

    DiffResult result;
    result.success = true;

    for (const auto& serverEntry : serverEntries) {
        FileEntry fe;
        fe.path = serverEntry.relativePath;
        fe.size = serverEntry.fileSize;
        fe.modifiedAt = serverEntry.modifiedAt;
        result.serverFiles.push_back(fe);
    }

    auto targetDir = resolveTargetDir(configId);
    LOG_INFO("diffManifest: targetDir='{}'", targetDir.string());

    for (const auto& clientFile : clientFiles) {
        auto serverEntry = m_manifestRepo.findByConfigIdAndPath(configId, clientFile.path);
        if (!serverEntry) {
            result.filesToUpload.push_back(clientFile);
            LOG_INFO("diffManifest: '{}' needs upload (not in manifest)", clientFile.path);
            continue;
        }

        auto fullPath = targetDir / clientFile.path;
        std::error_code ec;
        bool existsOnDisk = std::filesystem::exists(fullPath, ec);
        LOG_INFO("diffManifest: check '{}' -> exists={}, ec={}", fullPath.string(), existsOnDisk, ec.message());
        if (!existsOnDisk) {
            result.filesToUpload.push_back(clientFile);
            LOG_INFO("diffManifest: '{}' needs upload (file missing on server)", clientFile.path);
            continue;
        }

        if (serverEntry->fileSize != clientFile.size) {
            result.filesToUpload.push_back(clientFile);
            LOG_INFO("diffManifest: '{}' needs upload (changed)", clientFile.path);
        }
    }

    LOG_INFO("diffManifest: done, {} files to upload", static_cast<long>(result.filesToUpload.size()));
    return result;
}

int64_t SyncService::getTargetFileCount(int64_t configId) const {
    auto targetDir = resolveTargetDir(configId);
    if (targetDir.empty()) return 0;

    std::error_code ec;
    if (!std::filesystem::exists(targetDir, ec)) return 0;

    int64_t count = 0;
    for (auto& entry : std::filesystem::recursive_directory_iterator(targetDir, ec)) {
        if (entry.is_regular_file()) {
            ++count;
        }
    }
    return count;
}

int64_t SyncService::getSyncedFileCount(int64_t configId) const {
    auto entries = m_manifestRepo.findByConfigId(configId);
    return static_cast<int64_t>(entries.size());
}

void SyncService::commitFiles(int64_t configId,
                               const std::vector<std::string>& paths)
{
    LOG_INFO("commitFiles: configId={} paths={}",
             static_cast<long>(configId), static_cast<long>(paths.size()));

    auto targetDir = resolveTargetDir(configId);

    for (const auto& path : paths) {
        SyncFileManifestRepository::Entry entry;
        entry.syncConfigId = configId;
        entry.relativePath = path;

        auto fullPath = targetDir / path;
        std::error_code ec;
        auto fileSize = std::filesystem::file_size(fullPath, ec);
        if (!ec) {
            entry.fileSize = static_cast<int64_t>(fileSize);
        }

        m_manifestRepo.upsert(entry);
        LOG_INFO("commitFiles: recorded '{}' in manifest (size={})",
                 path, static_cast<long>(entry.fileSize));
    }

    m_configRepo.updateLastSyncedAt(configId);
    LOG_INFO("commitFiles: done");
}

} // namespace ainas
