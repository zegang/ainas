#include "ainas/logging/Logger.hpp"
#include "ainas/service/FileService.hpp"

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <ctime>
#include <fstream>
#include <iomanip>
#include <random>
#include <sstream>

namespace ainas {

namespace {

std::string str(const oatpp::String& s) {
    return s ? std::string(s->c_str(), s->size()) : "";
}

std::string normalizeRelative(const std::string& rel) {
    if (rel.empty() || rel.front() != '/') return "/" + rel;
    return rel;
}

} // anonymous namespace

FileService::FileService(std::shared_ptr<Config> config,
                         Database& database)
    : m_config(std::move(config))
    , m_repo(database)
{
    std::error_code ec;
    std::filesystem::create_directories(m_config->dataPath, ec);
    m_repo.migrate();
}

std::filesystem::path FileService::resolvePath(const std::string& relativePath) const {
    std::string cleanPath = relativePath;
    while (!cleanPath.empty() && cleanPath.front() == '/') {
        cleanPath.erase(0, 1);
    }

    auto input = std::filesystem::path(cleanPath).lexically_normal();
    auto fullPath = (m_config->dataPath / input).lexically_normal();
    if (fullPath.string().empty()) {
        fullPath = m_config->dataPath;
    }

    auto rootStr = m_config->dataPath.lexically_normal().string();
    auto fullStr = fullPath.string();

    LOG_INFO("resolvePath: relativePath {}, rootStr {}, fullStr {}",
              relativePath, rootStr, fullStr);
    if (fullStr.size() < rootStr.size() ||
        fullStr.compare(0, rootStr.size(), rootStr) != 0 ||
        (fullStr.size() > rootStr.size() &&
         fullStr[rootStr.size()] != '/' && fullStr[rootStr.size()] != '\\')) {
        throw FileServiceError(FileServiceError::Kind::BadRequest,
                               "Path traversal detected");
    }

    return fullPath;
}

std::filesystem::path FileService::resolveExistingPath(const std::string& relativePath) const {
    auto path = resolvePath(relativePath);
    std::error_code ec;
    if (!std::filesystem::exists(path, ec)) {
        throw FileServiceError(FileServiceError::Kind::NotFound,
                               "Path does not exist: " + relativePath);
    }
    return path;
}

v_int64 FileService::formatTime(std::filesystem::file_time_type ftime) const {
    auto sctp = std::chrono::time_point_cast<std::chrono::system_clock::duration>(
        ftime - std::filesystem::file_time_type::clock::now() + std::chrono::system_clock::now());
    return static_cast<v_int64>(std::chrono::system_clock::to_time_t(sctp));
}

std::string FileService::generateRandomString(size_t length) {
    static constexpr char chars[] =
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    static thread_local std::mt19937 gen(std::random_device{}());
    std::uniform_int_distribution<> dist(0, static_cast<int>(sizeof(chars) - 2));
    std::string result(length, '\0');
    for (size_t i = 0; i < length; ++i) {
        result[i] = chars[dist(gen)];
    }
    return result;
}

oatpp::Object<FileItemDto> FileService::recordToDto(
    const FileRepository::Record& record) const
{
    auto item = FileItemDto::createShared();
    item->id = record.id;
    item->name = oatpp::String(record.name);
    item->path = oatpp::String(record.path);
    item->size = record.size;
    item->isDirectory = record.isDirectory;
    item->createdAt = record.createdAt;
    item->updatedAt = record.updatedAt;
    auto tags = oatpp::Vector<oatpp::String>::createShared();
    for (const auto& t : record.tags) {
        tags->push_back(oatpp::String(t));
    }
    item->tags = tags;
    return item;
}

oatpp::Object<FileItemDto> FileService::makeFileItem(
    const std::filesystem::directory_entry& entry,
    const std::filesystem::path& relPath) const
{
    auto item = FileItemDto::createShared();
    item->name = oatpp::String(entry.path().filename().string());
    item->path = oatpp::String("/" + relPath.generic_string());
    std::error_code ec;

    if (entry.is_regular_file(ec)) {
        item->size = static_cast<v_int64>(entry.file_size(ec));
        item->isDirectory = false;
    } else if (entry.is_directory(ec)) {
        item->size = v_int64(0);
        item->isDirectory = true;
    }

    if (!ec) {
        auto ftime = entry.last_write_time(ec);
        if (!ec) {
            item->createdAt = formatTime(ftime);
            item->updatedAt = formatTime(ftime);
        }
    }

    item->tags = oatpp::Vector<oatpp::String>::createShared();

    return item;
}

int64_t FileService::syncDirectory(const std::filesystem::path& fullPath,
                                    const std::string& relPath,
                                    std::optional<int64_t> parentId) {
    auto existing = m_repo.findByPath(relPath);
    if (existing) return existing->id;

    std::error_code ec;
    auto ftime = std::filesystem::last_write_time(fullPath, ec);
    auto now = static_cast<int64_t>(std::chrono::system_clock::to_time_t(
        std::chrono::system_clock::now()));

    FileRepository::Record record;
    record.name = fullPath.filename().string();
    record.path = relPath;
    record.size = 0;
    record.isDirectory = true;
    record.createdAt = ec ? now : formatTime(ftime);
    record.updatedAt = ec ? now : formatTime(ftime);
    record.parentId = parentId;

    return m_repo.insert(record);
}

oatpp::Object<FileListResponseDto> FileService::listFiles(const oatpp::String& pathStr) {
    LOG_DEBUG("listFiles(path=\"{}\")", str(pathStr));
    auto response = FileListResponseDto::createShared();

    std::string relativePath = pathStr ? str(pathStr) : "/";
    if (relativePath.empty()) relativePath = "/";
    relativePath = normalizeRelative(relativePath);

    std::filesystem::path fullPath;
    try {
        fullPath = resolveExistingPath(relativePath);
    } catch (const FileServiceError& e) {
        LOG_WARN("listFiles: {}", e.what());
        response->success = false;
        response->message = oatpp::String(e.what());
        return response;
    }

    response->path = oatpp::String(relativePath);
    response->success = true;
    response->items = oatpp::Vector<oatpp::Object<FileItemDto>>::createShared();

    std::error_code ec;
    if (!std::filesystem::is_directory(fullPath, ec)) {
        LOG_WARN("listFiles: path is not a directory: {}", relativePath);
        response->success = false;
        response->message = "Path is not a directory";
        return response;
    }

    // Ensure parent directory is synced to DB
    auto parentRecord = m_repo.findByPath(relativePath);
    std::optional<int64_t> parentId;
    if (parentRecord) {
        parentId = parentRecord->id;
    } else {
        // Sync the target directory itself first
        auto grandparentRel = std::filesystem::path(relativePath).parent_path().generic_string();
        if (grandparentRel.empty()) grandparentRel = "/";
        auto grandparentRec = m_repo.findByPath(grandparentRel);
        std::optional<int64_t> gpId;
        if (grandparentRec) gpId = grandparentRec->id;

        std::filesystem::path parentFull;
        if (relativePath == "/") {
            parentFull = m_config->dataPath;
        } else {
            parentFull = m_config->dataPath / relativePath.substr(1);
        }
        parentId = syncDirectory(parentFull, relativePath, gpId);
    }

    // Iterate filesystem and sync each entry to DB
    auto now = static_cast<int64_t>(std::chrono::system_clock::to_time_t(
        std::chrono::system_clock::now()));

    for (const auto& entry : std::filesystem::directory_iterator(fullPath, ec)) {
        auto relPathObj = entry.path().lexically_relative(m_config->dataPath);
        if (relPathObj.empty()) {
            relPathObj = entry.path().filename();
        }
        auto entryRel = normalizeRelative(relPathObj.generic_string());

        auto existing = m_repo.findByPath(entryRel);
        if (existing) {
            response->items->push_back(recordToDto(*existing));
            continue;
        }

        auto fsize = entry.is_regular_file(ec)
            ? static_cast<int64_t>(entry.file_size(ec)) : int64_t(0);
        auto ftime = entry.last_write_time(ec);
        auto ts = ec ? now : formatTime(ftime);

        FileRepository::Record rec;
        rec.name = entry.path().filename().string();
        rec.path = entryRel;
        rec.size = fsize;
        rec.isDirectory = entry.is_directory(ec);
        rec.createdAt = ts;
        rec.updatedAt = ts;
        rec.parentId = parentId;

        auto id = m_repo.insert(rec);
        rec.id = id;
        response->items->push_back(recordToDto(rec));
    }

    std::sort(response->items->begin(), response->items->end(),
        [](const auto& a, const auto& b) {
            return str(a->name) < str(b->name);
        });

    LOG_DEBUG("listFiles: found {} entries in \"{}\"",
              response->items->size(), relativePath);
    return response;
}

oatpp::Object<UploadResponseDto> FileService::uploadFile(
    const std::string& tmpPath,
    const oatpp::String& filename,
    const oatpp::String& targetDir)
{
    LOG_INFO("uploadFile: filename=\"{}\" targetDir=\"{}\"",
             str(filename), str(targetDir));
    auto response = UploadResponseDto::createShared();

    if (!filename || filename->empty()) {
        LOG_WARN("uploadFile: no filename provided");
        response->success = false;
        response->message = "No filename provided";
        return response;
    }

    std::string dir = targetDir ? str(targetDir) : "/";
    if (!dir.empty() && dir.front() != '/') dir = "/" + dir;

    std::filesystem::path targetDirPath;
    try {
        targetDirPath = resolvePath(dir);
    } catch (const FileServiceError& e) {
        LOG_WARN("uploadFile: {}", e.what());
        response->success = false;
        response->message = oatpp::String(e.what());
        return response;
    }

    std::error_code ec;
    std::filesystem::create_directories(targetDirPath, ec);
    if (ec) {
        LOG_ERROR("uploadFile: failed to create directory '{}': {}",
                  targetDirPath.string(), ec.message());
        response->success = false;
        response->message = "Failed to create directory: " + ec.message();
        return response;
    }

    auto targetPath = targetDirPath / str(filename);
    auto targetStr = targetPath.lexically_normal().string();
    auto rootStr = m_config->dataPath.lexically_normal().string();
    if (targetStr.size() < rootStr.size() ||
        targetStr.compare(0, rootStr.size(), rootStr) != 0) {
        LOG_WARN("uploadFile: path traversal detected: {}", targetStr);
        response->success = false;
        response->message = "Path traversal detected";
        return response;
    }

    std::filesystem::rename(tmpPath, targetPath, ec);
    if (ec) {
        LOG_DEBUG("uploadFile: rename failed ({}), trying copy+remove", ec.message());
        std::filesystem::copy_file(tmpPath, targetPath,
            std::filesystem::copy_options::overwrite_existing, ec);
        if (!ec) {
            std::filesystem::remove(tmpPath, ec);
        }
    }

    if (ec) {
        LOG_ERROR("uploadFile: failed to save file: {}", ec.message());
        response->success = false;
        response->message = "Failed to save file: " + ec.message();
        return response;
    }

    auto fileSize = std::filesystem::file_size(targetPath, ec);
    // Sync to database
    {
        auto uploadRelPath = normalizeRelative(dir + "/" + str(filename));
        auto parentRecord = m_repo.findByPath(normalizeRelative(dir));
        std::optional<int64_t> parentId;
        if (parentRecord) parentId = parentRecord->id;

        auto ftime = std::filesystem::last_write_time(targetPath, ec);
        auto ts = ec ? static_cast<int64_t>(std::chrono::system_clock::to_time_t(
            std::chrono::system_clock::now())) : formatTime(ftime);

        FileRepository::Record rec;
        rec.name = str(filename);
        rec.path = uploadRelPath;
        rec.size = static_cast<int64_t>(fileSize);
        rec.isDirectory = false;
        rec.createdAt = ts;
        rec.updatedAt = ts;
        rec.parentId = parentId;

        // If a record with the same path already exists, update it instead of
        // inserting - avoids SQLITE_CONSTRAINT on the UNIQUE path column when
        // re-uploading a file with the same name.
        auto existing = m_repo.findByPath(uploadRelPath);
        if (existing) {
            rec.id = existing->id;
            rec.createdAt = existing->createdAt; // preserve original creation time
            m_repo.update(rec);
        } else {
            m_repo.insert(rec);
        }
    }

    LOG_INFO("uploadFile: saved \"{}\" ({} bytes)",
             targetPath.string(), fileSize);

    response->success = true;
    response->message = "File uploaded successfully";
    response->name = oatpp::String(filename);
    response->path = oatpp::String(dir + "/" + str(filename));
    response->size = static_cast<v_int64>(fileSize);

    return response;
}

oatpp::Object<ApiResponseDto> FileService::deleteFile(const oatpp::String& pathStr) {
    LOG_INFO("deleteFile(path=\"{}\")", str(pathStr));
    auto response = ApiResponseDto::createShared();

    if (!pathStr || pathStr->empty()) {
        LOG_WARN("deleteFile: path is required");
        response->success = false;
        response->message = "Path is required";
        return response;
    }

    std::filesystem::path fullPath;
    try {
        fullPath = resolveExistingPath(str(pathStr));
    } catch (const FileServiceError& e) {
        LOG_WARN("deleteFile: {}", e.what());
        response->success = false;
        response->message = oatpp::String(e.what());
        return response;
    }

    std::error_code ec;
    auto count = std::filesystem::remove_all(fullPath, ec);
    if (ec) {
        LOG_ERROR("deleteFile: failed to delete '{}': {}", fullPath.string(), ec.message());
        response->success = false;
        response->message = "Failed to delete: " + ec.message();
        return response;
    }

    // Delete from database
    {
        auto relPath = normalizeRelative(str(pathStr));
        m_repo.deleteByPath(relPath);
    }

    LOG_INFO("deleteFile: removed {} item(s) from \"{}\"", count, str(pathStr));
    response->success = true;
    response->message = oatpp::String(
        "Deleted " + std::to_string(count) + " item(s)");
    response->path = pathStr;
    return response;
}

oatpp::Object<ApiResponseDto> FileService::moveFile(const oatpp::Object<MoveRequestDto>& body) {
    auto response = ApiResponseDto::createShared();

    // Resolve source path - by id, id string, or path
    std::filesystem::path srcPath;
    std::string srcRel;
    std::string fileName;

    auto resolveSource = [&]() -> bool {
        if (body->id) {
            auto rec = m_repo.findById(*body->id);
            if (!rec) {
                response->success = false;
                response->message = "Source file not found by id";
                return false;
            }
            srcPath = resolvePath(rec->path);
            srcRel = rec->path;
            fileName = rec->name;
            return true;
        }
        if (body->itemId && !body->itemId->empty()) {
            auto idStr = str(body->itemId);
            char* end{};
            int64_t parsed = std::strtoll(idStr.c_str(), &end, 10);
            if (*end == '\0' && parsed > 0) {
                auto rec = m_repo.findById(parsed);
                if (!rec) {
                    response->success = false;
                    response->message = "Source file not found by item_id";
                    return false;
                }
                srcPath = resolvePath(rec->path);
                srcRel = rec->path;
                fileName = rec->name;
                return true;
            }
        }
        // Fallback to path
        if (!body->path || body->path->empty()) {
            response->success = false;
            response->message = "Provide path, id, or item_id";
            return false;
        }
        try {
            srcPath = resolveExistingPath(str(body->path));
        } catch (const FileServiceError& e) {
            response->success = false;
            response->message = oatpp::String(e.what());
            return false;
        }
        srcRel = normalizeRelative(str(body->path));
        fileName = srcPath.filename().string();
        return true;
    };

    if (!resolveSource()) return response;

    // Resolve destination - by target_parent_id, target_parent_path, or newPath
    std::filesystem::path dstPath;
    std::string dstRel;

    auto resolveDest = [&]() -> bool {
        // Target parent by id
        if (body->targetParentId) {
            auto parentRec = m_repo.findById(*body->targetParentId);
            if (!parentRec || !parentRec->isDirectory) {
                response->success = false;
                response->message = "Target parent not found or not a directory";
                return false;
            }
            auto parentFull = resolvePath(parentRec->path);
            dstPath = parentFull / fileName;
            dstRel = normalizeRelative(parentRec->path + "/" + fileName);
            return true;
        }
        // Target parent by path
        if (body->targetParentPath && !body->targetParentPath->empty()) {
            auto parentRel = normalizeRelative(str(body->targetParentPath));
            try {
                auto parentFull = resolvePath(parentRel);
                dstPath = parentFull / fileName;
                dstRel = normalizeRelative(parentRel + "/" + fileName);
                return true;
            } catch (const FileServiceError& e) {
                response->success = false;
                response->message = oatpp::String(e.what());
                return false;
            }
        }
        // Full new path
        if (body->newPath && !body->newPath->empty()) {
            try {
                dstPath = resolvePath(str(body->newPath));
            } catch (const FileServiceError& e) {
                response->success = false;
                response->message = oatpp::String(e.what());
                return false;
            }
            dstRel = normalizeRelative(str(body->newPath));
            return true;
        }
        response->success = false;
        response->message = "Provide newPath, target_parent_id, or target_parent_path";
        return false;
    };

    if (!resolveDest()) return response;

    // Ensure parent exists
    std::error_code ec;
    std::filesystem::create_directories(dstPath.parent_path(), ec);

    LOG_INFO("moveFile: \"{}\" -> \"{}\"", srcRel, dstRel);

    std::filesystem::rename(srcPath, dstPath, ec);
    if (ec) {
        LOG_DEBUG("moveFile: rename failed ({}), falling back to copy+remove", ec.message());
        if (std::filesystem::is_directory(srcPath, ec)) {
            std::filesystem::copy(srcPath, dstPath,
                std::filesystem::copy_options::recursive |
                std::filesystem::copy_options::overwrite_existing, ec);
            if (!ec) std::filesystem::remove_all(srcPath, ec);
        } else {
            std::filesystem::copy_file(srcPath, dstPath,
                std::filesystem::copy_options::overwrite_existing, ec);
            if (!ec) std::filesystem::remove(srcPath, ec);
        }
    }

    if (ec) {
        LOG_ERROR("moveFile: failed: {}", ec.message());
        response->success = false;
        response->message = "Failed to move: " + ec.message();
        return response;
    }

    // Update database paths
    {
        auto srcRecord = m_repo.findByPath(srcRel);
        if (srcRecord) {
            srcRecord->path = dstRel;
            srcRecord->name = dstPath.filename().string();

            auto parentRel2 = std::filesystem::path(dstRel).parent_path().generic_string();
            if (parentRel2.empty()) parentRel2 = "/";
            auto parentRecord = m_repo.findByPath(parentRel2);
            srcRecord->parentId = parentRecord ? std::optional(parentRecord->id) : std::nullopt;

            m_repo.update(*srcRecord);
        }
    }

    response->success = true;
    response->message = "Moved successfully";
    response->path = oatpp::String(dstRel);
    return response;
}

oatpp::Object<ApiResponseDto> FileService::copyFile(const oatpp::Object<CopyRequestDto>& body) {
    auto response = ApiResponseDto::createShared();

    // Resolve target directory - by id or path
    std::filesystem::path targetDirPath;
    std::string targetDirRel;

    auto resolveTarget = [&]() -> bool {
        if (body->targetDirId) {
            auto rec = m_repo.findById(*body->targetDirId);
            if (!rec || !rec->isDirectory) {
                response->success = false;
                response->message = "Target directory not found by target_dir_id";
                return false;
            }
            targetDirRel = rec->path;
            targetDirPath = resolvePath(rec->path);
            return true;
        }
        if (body->targetDir && !body->targetDir->empty()) {
            targetDirRel = normalizeRelative(str(body->targetDir));
            try {
                targetDirPath = resolvePath(targetDirRel);
            } catch (const FileServiceError& e) {
                response->success = false;
                response->message = oatpp::String(e.what());
                return false;
            }
            return true;
        }
        response->success = false;
        response->message = "Provide targetDir or target_dir_id";
        return false;
    };

    if (!resolveTarget()) return response;

    // Collect source paths - by ids or paths
    struct SourceItem {
        std::filesystem::path fullPath;
        std::string relPath;
    };
    std::vector<SourceItem> sources;

    auto collectByIds = [&]() -> bool {
        if (!body->ids || body->ids->empty()) return false;
        for (auto id : *body->ids) {
            auto idVal = static_cast<int64_t>(id);
            auto rec = m_repo.findById(idVal);
            if (!rec) {
                LOG_WARN("copyFile: source id={} not found, skipping", idVal);
                continue;
            }
            sources.push_back({resolvePath(rec->path), rec->path});
        }
        return true;
    };

    auto collectByPaths = [&]() -> bool {
        if (!body->paths || body->paths->empty()) return false;
        for (const auto& p : *body->paths) {
            std::string pStr = str(p);
            try {
                sources.push_back({resolveExistingPath(pStr), normalizeRelative(pStr)});
            } catch (const FileServiceError&) {
                LOG_WARN("copyFile: source path not found, skipping: {}", pStr);
            }
        }
        return true;
    };

    bool hasSources = collectByIds() || collectByPaths();

    if (!hasSources || sources.empty()) {
        response->success = false;
        response->message = "No valid source files provided (provide ids or paths)";
        return response;
    }

    LOG_INFO("copyFile: {} items -> targetDir=\"{}\"", sources.size(), targetDirRel);

    response->files = oatpp::Vector<oatpp::String>::createShared();
    response->sources = oatpp::Vector<oatpp::String>::createShared();

    std::error_code ec;
    std::filesystem::create_directories(targetDirPath, ec);

    // Sync target directory to DB so parent_id is set
    auto targetRelForDb = targetDirRel;
    auto targetRecord = m_repo.findByPath(targetRelForDb);

    int copied = 0;
    for (const auto& src : sources) {
        auto dest = targetDirPath / src.fullPath.filename();

        if (std::filesystem::is_directory(src.fullPath, ec)) {
            std::filesystem::copy(src.fullPath, dest,
                std::filesystem::copy_options::recursive |
                std::filesystem::copy_options::overwrite_existing, ec);
            if (!ec) ++copied;
        } else {
            std::filesystem::copy_file(src.fullPath, dest,
                std::filesystem::copy_options::overwrite_existing, ec);
            if (!ec) ++copied;
        }
        if (ec) {
            LOG_ERROR("copyFile: failed to copy '{}': {}", src.relPath, ec.message());
            ec.clear();
        } else {
            auto newRel = normalizeRelative(targetDirRel + "/" + src.fullPath.filename().string());
            response->files->push_back(oatpp::String(newRel));
            response->sources->push_back(oatpp::String(src.relPath));

            // Insert copied file metadata into DB
            if (!m_repo.findByPath(newRel)) {
                std::error_code fec;
                auto fsize = std::filesystem::file_size(dest, fec) ;
                auto ftime = std::filesystem::last_write_time(dest, fec);
                auto now = static_cast<int64_t>(std::chrono::system_clock::to_time_t(
                    std::chrono::system_clock::now()));
                FileRepository::Record rec;
                rec.name = src.fullPath.filename().string();
                rec.path = newRel;
                rec.size = fec ? 0 : static_cast<int64_t>(fsize);
                rec.isDirectory = std::filesystem::is_directory(dest, fec);
                rec.createdAt = fec ? now : formatTime(ftime);
                rec.updatedAt = fec ? now : formatTime(ftime);
                rec.parentId = targetRecord ? std::optional(targetRecord->id) : std::nullopt;
                m_repo.insert(rec);
            }
        }
    }

    LOG_INFO("copyFile: copied {} item(s)", copied);
    response->success = copied > 0;
    response->message = oatpp::String("Copied " + std::to_string(copied) + " item(s)");
    response->path = oatpp::String(targetDirRel);
    return response;
}

oatpp::Object<ApiResponseDto> FileService::renameFile(const oatpp::Object<RenameRequestDto>& body) {
    LOG_INFO("renameFile(path=\"{}\" newName=\"{}\")",
             str(body->path), str(body->newName));
    auto response = ApiResponseDto::createShared();

    if (!body->path || body->path->empty() || !body->newName || body->newName->empty()) {
        LOG_WARN("renameFile: both path and newName are required");
        response->success = false;
        response->message = "Both path and newName are required";
        return response;
    }

    std::filesystem::path srcPath;
    try {
        srcPath = resolveExistingPath(str(body->path));
    } catch (const FileServiceError& e) {
        LOG_WARN("renameFile: {}", e.what());
        response->success = false;
        response->message = oatpp::String(e.what());
        return response;
    }

    auto newName = str(body->newName);
    if (newName.find('/') != std::string::npos) {
        LOG_WARN("renameFile: newName contains path separator");
        response->success = false;
        response->message = "newName cannot contain path separators";
        return response;
    }

    auto dstPath = srcPath.parent_path() / newName;

    std::error_code ec;
    std::filesystem::rename(srcPath, dstPath, ec);
    if (ec) {
        LOG_ERROR("renameFile: failed to rename: {}", ec.message());
        response->success = false;
        response->message = "Failed to rename: " + ec.message();
        return response;
    }

    // Update database
    {
        auto oldRel = normalizeRelative(str(body->path));
        auto newRel = normalizeRelative(
            std::filesystem::path(str(body->path)).parent_path().generic_string() + "/" + newName);

        auto record = m_repo.findByPath(oldRel);
        if (record) {
            record->name = newName;
            record->path = newRel;
            m_repo.update(*record);
        }
    }

    LOG_INFO("renameFile: renamed to \"{}\"",
             (std::filesystem::path(str(body->path)).parent_path() / newName).string());
    response->success = true;
    response->message = "Renamed successfully";
    auto parentPath = std::filesystem::path(str(body->path)).parent_path().generic_string();
    response->path = oatpp::String(parentPath + "/" + newName);
    return response;
}

oatpp::Object<ApiResponseDto> FileService::createFolder(const oatpp::String& pathStr) {
    LOG_INFO("createFolder(path=\"{}\")", str(pathStr));
    auto response = ApiResponseDto::createShared();

    if (!pathStr || pathStr->empty()) {
        LOG_WARN("createFolder: path is required");
        response->success = false;
        response->message = "Path is required";
        return response;
    }

    std::filesystem::path fullPath;
    try {
        fullPath = resolvePath(str(pathStr));
    } catch (const FileServiceError& e) {
        LOG_WARN("createFolder: {}", e.what());
        response->success = false;
        response->message = oatpp::String(e.what());
        return response;
    }

    std::error_code ec;
    bool created = std::filesystem::create_directories(fullPath, ec);
    if (ec) {
        LOG_ERROR("createFolder: failed to create '{}': {}",
                  fullPath.string(), ec.message());
        response->success = false;
        response->message = "Failed to create folder: " + ec.message();
        return response;
    }

    // Sync to database
    if (created) {
        auto relPath = normalizeRelative(str(pathStr));
        auto parentRel = std::filesystem::path(relPath).parent_path().generic_string();
        if (parentRel.empty()) parentRel = "/";

        auto parentRecord = m_repo.findByPath(parentRel);
        std::optional<int64_t> parentId;
        if (parentRecord) parentId = parentRecord->id;

        auto ftime = std::filesystem::last_write_time(fullPath, ec);
        auto now = static_cast<int64_t>(std::chrono::system_clock::to_time_t(
            std::chrono::system_clock::now()));
        auto ts = ec ? now : formatTime(ftime);

        FileRepository::Record rec;
        rec.name = fullPath.filename().string();
        rec.path = relPath;
        rec.size = 0;
        rec.isDirectory = true;
        rec.createdAt = ts;
        rec.updatedAt = ts;
        rec.parentId = parentId;
        m_repo.insert(rec);
    }

    LOG_INFO("createFolder: {} \"{}\"",
             created ? "created" : "already exists", str(pathStr));
    response->success = true;
    response->message = created ? "Folder created" : "Folder already exists";
    response->path = pathStr;
    return response;
}

//===----------------------------------------------------------------------===//
//  ID-based operations
//===----------------------------------------------------------------------===//

oatpp::Object<FileDetailResponseDto> FileService::getFileById(int64_t id) {
    auto response = FileDetailResponseDto::createShared();

    auto record = m_repo.findById(id);
    if (!record) {
        response->success = false;
        response->message = oatpp::String("File not found");
        return response;
    }

    response->success = true;
    response->file = recordToDto(*record);
    return response;
}

oatpp::Object<FileDetailResponseDto> FileService::updateFile(
    int64_t id, const oatpp::Object<UpdateFileRequestDto>& body)
{
    auto response = FileDetailResponseDto::createShared();

    auto record = m_repo.findById(id);
    if (!record) {
        response->success = false;
        response->message = "File not found";
        return response;
    }

    // Update name
    if (body->name && !body->name->empty()) {
        auto newName = str(body->name);
        auto oldPath = std::filesystem::path(record->path);

        // Rename on filesystem
        auto fullPath = resolvePath(record->path);
        auto newFullPath = fullPath.parent_path() / newName;
        std::error_code ec;
        std::filesystem::rename(fullPath, newFullPath, ec);
        if (ec) {
            response->success = false;
            response->message = oatpp::String("Failed to rename: " + ec.message());
            return response;
        }

        record->name = newName;
        record->path = normalizeRelative(
            oldPath.parent_path().generic_string() + "/" + newName);
    }

    // Move to new parent
    if (body->parentId && *body->parentId != record->parentId.value_or(0)) {
        auto newParent = m_repo.findById(*body->parentId);
        if (!newParent || !newParent->isDirectory) {
            response->success = false;
            response->message = "Parent not found or not a directory";
            return response;
        }

        auto oldFullPath = resolvePath(record->path);
        auto newFullPath = resolvePath(newParent->path) / record->name;

        std::error_code ec;
        std::filesystem::rename(oldFullPath, newFullPath, ec);
        if (ec) {
            response->success = false;
            response->message = oatpp::String("Failed to move: " + ec.message());
            return response;
        }

        record->parentId = *body->parentId;
        record->path = normalizeRelative(newParent->path + "/" + record->name);
    }

    m_repo.update(*record);

    if (body->tags) {
        std::vector<std::string> tags;
        for (const auto& t : *body->tags) {
            tags.push_back(str(t));
        }
        m_repo.setTags(id, tags);
        record->tags = tags;
    }

    response->success = true;
    response->file = recordToDto(*record);
    return response;
}

oatpp::Object<ApiResponseDto> FileService::deleteFileById(int64_t id) {
    auto response = ApiResponseDto::createShared();

    auto record = m_repo.findById(id);
    if (!record) {
        response->success = false;
        response->message = "File not found";
        return response;
    }

    // Delete from filesystem
    try {
        auto fullPath = resolvePath(record->path);
        std::error_code ec;
        std::filesystem::remove_all(fullPath, ec);
        if (ec) {
            LOG_ERROR("deleteFileById: filesystem removal failed: {}", ec.message());
        }
    } catch (const FileServiceError& e) {
        LOG_WARN("deleteFileById: path resolution failed: {}", e.what());
    }

    m_repo.deleteById(id);

    response->success = true;
    response->message = "Deleted successfully";
    response->path = oatpp::String(record->path);
    return response;
}

} // namespace ainas
