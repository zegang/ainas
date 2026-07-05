#pragma once

#include "ainas/database/SyncConfigRepository.hpp"
#include "ainas/database/SyncFileManifestRepository.hpp"
#include "ainas/dto/DTOs.hpp"
#include "ainas/logging/Logger.hpp"
#include "ainas/service/SyncService.hpp"
#include "ainas/service/FileService.hpp"

#include "oatpp/web/server/api/ApiController.hpp"
#include "oatpp/json/ObjectMapper.hpp"
#include "oatpp/macro/codegen.hpp"
#include "oatpp/web/mime/multipart/FileProvider.hpp"
#include "oatpp/web/mime/multipart/InMemoryDataProvider.hpp"
#include "oatpp/web/mime/multipart/Reader.hpp"
#include "oatpp/web/mime/multipart/PartList.hpp"
#include "oatpp/web/protocol/http/outgoing/BufferBody.hpp"

#include <fstream>
#include <memory>
#include <string>
#include <vector>

#include OATPP_CODEGEN_BEGIN(ApiController)

namespace ainas {

class SyncController : public oatpp::web::server::api::ApiController {
private:
    std::shared_ptr<SyncConfigRepository> m_repo;
    std::shared_ptr<SyncService> m_syncService;

    oatpp::Object<SyncConfigDto> entryToDto(const SyncConfigRepository::Entry& entry) const {
        auto dto = SyncConfigDto::createShared();
        dto->id = entry.id;
        dto->name = oatpp::String(entry.name);
        dto->sourcePath = oatpp::String(entry.sourcePath);
        dto->targetPath = oatpp::String(entry.targetPath);
        dto->syncIntervalSecs = entry.syncIntervalSecs;
        dto->syncPolicy = oatpp::String(entry.syncPolicy);
        dto->syncTime = oatpp::String(entry.syncTime);
        if (!entry.lastSyncedAt.empty()) {
            dto->lastSyncedAt = oatpp::String(entry.lastSyncedAt);
        }
        dto->enabled = entry.enabled;
        dto->deleteAfterSync = entry.deleteAfterSync;
        dto->createdAt = oatpp::String(entry.createdAt);
        dto->updatedAt = oatpp::String(entry.updatedAt);
        return dto;
    }

public:
    SyncController(const std::shared_ptr<ObjectMapper>& objectMapper,
                   std::shared_ptr<SyncConfigRepository> repo,
                   std::shared_ptr<SyncService> syncService)
        : oatpp::web::server::api::ApiController(objectMapper)
        , m_repo(std::move(repo))
        , m_syncService(std::move(syncService))
    {}

    static std::shared_ptr<SyncController> createShared(
        const std::shared_ptr<ObjectMapper>& objectMapper,
        std::shared_ptr<SyncConfigRepository> repo,
        std::shared_ptr<SyncService> syncService)
    {
        return std::make_shared<SyncController>(objectMapper, std::move(repo), std::move(syncService));
    }

    ENDPOINT("GET", "/api/sync", listSyncConfigs) {
        LOG_INFO("GET /api/sync");
        auto entries = m_repo->findAll();
        auto response = SyncConfigListResponseDto::createShared();
        response->success = true;

        auto configs = oatpp::Vector<oatpp::Object<SyncConfigDto>>::createShared();
        for (const auto& entry : entries) {
            configs->push_back(entryToDto(entry));
        }
        response->configs = configs;

        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("GET", "/api/sync/{id}", getSyncConfig,
             PATH(Int64, id, "id")) {
        LOG_INFO("GET /api/sync/{}", static_cast<long>(id));
        auto entry = m_repo->findById(id);
        if (!entry) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "Sync config not found";
            return createDtoResponse(Status::CODE_404, error);
        }
        return createDtoResponse(Status::CODE_200, entryToDto(*entry));
    }

    ENDPOINT("POST", "/api/sync", createSyncConfig,
             BODY_DTO(Object<SyncConfigRequestDto>, body)) {
        LOG_INFO("POST /api/sync");

        if (!body->name || body->name->empty()) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "name is required";
            return createDtoResponse(Status::CODE_400, error);
        }
        if (!body->sourcePath || body->sourcePath->empty()) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "source_path is required";
            return createDtoResponse(Status::CODE_400, error);
        }
        if (!body->targetPath || body->targetPath->empty()) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "target_path is required";
            return createDtoResponse(Status::CODE_400, error);
        }

        auto targetPathStr = std::string(body->targetPath->data(), body->targetPath->size());
        {
            auto conflict = m_syncService->validateTargetPath(targetPathStr);
            if (!conflict.empty()) {
                auto error = ApiResponseDto::createShared();
                error->success = false;
                error->message = oatpp::String(conflict);
                return createDtoResponse(Status::CODE_409, error);
            }
        }

        SyncConfigRepository::Entry entry;
        entry.name = std::string(body->name->data(), body->name->size());
        entry.sourcePath = std::string(body->sourcePath->data(), body->sourcePath->size());
        entry.targetPath = targetPathStr;
        if (body->syncIntervalSecs) {
            entry.syncIntervalSecs = body->syncIntervalSecs;
        }
        if (body->deleteAfterSync) {
            entry.deleteAfterSync = body->deleteAfterSync;
        }
        if (body->syncPolicy && !body->syncPolicy->empty()) {
            entry.syncPolicy = std::string(body->syncPolicy->data(), body->syncPolicy->size());
        }
        if (body->syncTime) {
            entry.syncTime = std::string(body->syncTime->data(), body->syncTime->size());
        }

        auto id = m_repo->insert(entry);
        auto created = m_repo->findById(id);

        if (created) {
            return createDtoResponse(Status::CODE_200, entryToDto(*created));
        }

        auto error = ApiResponseDto::createShared();
        error->success = false;
        error->message = "Failed to create sync config";
        return createDtoResponse(Status::CODE_500, error);
    }

    ENDPOINT("PUT", "/api/sync/{id}", updateSyncConfig,
             PATH(Int64, id, "id"),
             BODY_DTO(Object<SyncConfigRequestDto>, body)) {
        LOG_INFO("PUT /api/sync/{}", static_cast<long>(id));

        auto existing = m_repo->findById(id);
        if (!existing) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "Sync config not found";
            return createDtoResponse(Status::CODE_404, error);
        }

        if (body->name && !body->name->empty()) {
            existing->name = std::string(body->name->data(), body->name->size());
        }
        if (body->sourcePath && !body->sourcePath->empty()) {
            existing->sourcePath = std::string(body->sourcePath->data(), body->sourcePath->size());
        }
        if (body->targetPath && !body->targetPath->empty()) {
            auto targetPathStr = std::string(body->targetPath->data(), body->targetPath->size());
            auto conflict = m_syncService->validateTargetPath(targetPathStr, id);
            if (!conflict.empty()) {
                auto error = ApiResponseDto::createShared();
                error->success = false;
                error->message = oatpp::String(conflict);
                return createDtoResponse(Status::CODE_409, error);
            }
            existing->targetPath = targetPathStr;
        }
        if (body->syncIntervalSecs) {
            existing->syncIntervalSecs = body->syncIntervalSecs;
        }
        if (body->deleteAfterSync != nullptr) {
            existing->deleteAfterSync = body->deleteAfterSync;
        }
        if (body->syncPolicy && !body->syncPolicy->empty()) {
            existing->syncPolicy = std::string(body->syncPolicy->data(), body->syncPolicy->size());
        }
        if (body->syncTime) {
            existing->syncTime = std::string(body->syncTime->data(), body->syncTime->size());
        }

        m_repo->update(*existing);
        auto updated = m_repo->findById(id);
        return createDtoResponse(Status::CODE_200, entryToDto(*updated));
    }

    ENDPOINT("DELETE", "/api/sync/{id}", deleteSyncConfig,
             PATH(Int64, id, "id")) {
        LOG_INFO("DELETE /api/sync/{}", static_cast<long>(id));

        bool deleted = m_repo->deleteById(id);
        if (!deleted) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "Sync config not found";
            return createDtoResponse(Status::CODE_404, error);
        }

        auto response = ApiResponseDto::createShared();
        response->success = true;
        response->message = "Sync config deleted";
        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("PATCH", "/api/sync/{id}/toggle", toggleSyncConfig,
             PATH(Int64, id, "id")) {
        LOG_INFO("PATCH /api/sync/{}/toggle", static_cast<long>(id));

        auto existing = m_repo->findById(id);
        if (!existing) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "Sync config not found";
            return createDtoResponse(Status::CODE_404, error);
        }

        existing->enabled = !existing->enabled;
        m_repo->update(*existing);

        auto response = ApiResponseDto::createShared();
        response->success = true;
        response->message = existing->enabled ? "Sync config enabled" : "Sync config disabled";
        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("POST", "/api/sync/{id}/sync", syncManifest,
             PATH(Int64, id, "id"),
             BODY_DTO(Object<SyncManifestRequestDto>, body)) {
        LOG_INFO("POST /api/sync/{}/sync", static_cast<long>(id));

        auto config = m_repo->findById(id);
        if (!config) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "Sync config not found";
            return createDtoResponse(Status::CODE_404, error);
        }

        std::vector<SyncService::FileEntry> clientFiles;
        if (body->files) {
            for (const auto& f : *body->files) {
                SyncService::FileEntry fe;
                fe.path = f->path ? std::string(f->path->data(), f->path->size()) : "";
                fe.size = f->size ? static_cast<int64_t>(f->size) : 0;
                fe.modifiedAt = f->modifiedAt ? std::string(f->modifiedAt->data(), f->modifiedAt->size()) : "";
                clientFiles.push_back(fe);
            }
        }

        auto result = m_syncService->diffManifest(id, clientFiles);

        auto response = SyncManifestResponseDto::createShared();
        response->success = result.success;
        response->message = oatpp::String(result.message);

        auto filesToUpload = oatpp::Vector<oatpp::Object<SyncFileEntryDto>>::createShared();
        for (const auto& fe : result.filesToUpload) {
            auto dto = SyncFileEntryDto::createShared();
            dto->path = oatpp::String(fe.path);
            dto->size = fe.size;
            dto->modifiedAt = oatpp::String(fe.modifiedAt);
            filesToUpload->push_back(dto);
        }
        response->filesToUpload = filesToUpload;

        auto serverFiles = oatpp::Vector<oatpp::Object<SyncFileEntryDto>>::createShared();
        for (const auto& fe : result.serverFiles) {
            auto dto = SyncFileEntryDto::createShared();
            dto->path = oatpp::String(fe.path);
            dto->size = fe.size;
            dto->modifiedAt = oatpp::String(fe.modifiedAt);
            serverFiles->push_back(dto);
        }
        response->serverFiles = serverFiles;

        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("POST", "/api/sync/{id}/upload", uploadFile,
             PATH(Int64, id, "id"),
             REQUEST(std::shared_ptr<IncomingRequest>, request)) {
        LOG_INFO("POST /api/sync/{}/upload", static_cast<long>(id));

        auto config = m_repo->findById(id);
        if (!config) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "Sync config not found";
            return createDtoResponse(Status::CODE_404, error);
        }

        if (!config->enabled) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "Sync config is disabled";
            return createDtoResponse(Status::CODE_400, error);
        }

        auto targetDir = m_syncService->resolveTargetDir(id);
        if (targetDir.empty()) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "Failed to resolve target directory";
            return createDtoResponse(Status::CODE_500, error);
        }

        auto multipart = std::make_shared<oatpp::web::mime::multipart::PartList>(
            request->getHeaders());

        oatpp::web::mime::multipart::Reader reader(multipart.get());

        auto tmpPath = std::filesystem::temp_directory_path() /
            ("ainas_sync_upload_" + FileService::generateRandomString(16));

        reader.setPartReader("file",
            oatpp::web::mime::multipart::createFilePartReader(
                tmpPath.string(), 1024LL * 1024 * 1024));
        reader.setPartReader("path",
            oatpp::web::mime::multipart::createInMemoryPartReader(4096));

        request->transferBody(&reader);

        auto filePart = multipart->getNamedPart("file");
        if (!filePart) {
            std::error_code ec;
            std::filesystem::remove(tmpPath, ec);
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "No file uploaded";
            return createDtoResponse(Status::CODE_400, error);
        }

        auto pathPart = multipart->getNamedPart("path");
        oatpp::String relativePath = pathPart
            ? pathPart->getPayload()->getInMemoryData()
            : oatpp::String("");

        if (!relativePath || relativePath->empty()) {
            std::error_code ec;
            std::filesystem::remove(tmpPath, ec);
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "path field is required";
            return createDtoResponse(Status::CODE_400, error);
        }

        std::string relPath(relativePath->data(), relativePath->size());
        auto destPath = targetDir / relPath;

        try {
            LOG_INFO("uploadFile: tmpPath='{}' destPath='{}'", tmpPath.string(), destPath.string());

            std::error_code ec;
            if (!std::filesystem::exists(tmpPath, ec)) {
                LOG_ERROR("uploadFile: temp file does not exist: {}", ec ? ec.message() : "no error");
                auto error = ApiResponseDto::createShared();
                error->success = false;
                error->message = "Upload temp file was not created by multipart reader";
                return createDtoResponse(Status::CODE_500, error);
            }

            std::filesystem::create_directories(destPath.parent_path(), ec);
            if (ec) {
                LOG_ERROR("uploadFile: create_directories '{}' failed: {}",
                          destPath.parent_path().string(), ec.message());
                auto error = ApiResponseDto::createShared();
                error->success = false;
                error->message = oatpp::String("Failed to create target directory: " + ec.message());
                return createDtoResponse(Status::CODE_500, error);
            }

            std::error_code ec2;
            std::filesystem::rename(tmpPath, destPath, ec2);
            if (ec2) {
                LOG_WARN("uploadFile: rename failed ({}), trying copy+remove", ec2.message());
                std::filesystem::copy_file(tmpPath, destPath,
                    std::filesystem::copy_options::overwrite_existing, ec2);
                std::filesystem::remove(tmpPath, ec);
                if (ec2) {
                    LOG_ERROR("uploadFile: copy_file failed: {}", ec2.message());
                    auto error = ApiResponseDto::createShared();
                    error->success = false;
                    error->message = oatpp::String("Failed to store file: " + ec2.message());
                    return createDtoResponse(Status::CODE_500, error);
                }
            }

            auto response = ApiResponseDto::createShared();
            response->success = true;
            response->message = oatpp::String("File uploaded: " + relPath);
            return createDtoResponse(Status::CODE_200, response);
        } catch (const std::exception& e) {
            LOG_ERROR("uploadFile: exception: {}", e.what());
            std::error_code ec;
            std::filesystem::remove(tmpPath, ec);
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = oatpp::String(e.what());
            return createDtoResponse(Status::CODE_500, error);
        }
    }

    ENDPOINT("GET", "/api/sync/{id}/stats", getSyncStats,
             PATH(Int64, id, "id")) {
        LOG_INFO("GET /api/sync/{}/stats", static_cast<long>(id));

        auto config = m_repo->findById(id);
        if (!config) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "Sync config not found";
            return createDtoResponse(Status::CODE_404, error);
        }

        auto response = SyncStatsResponseDto::createShared();
        response->success = true;
        response->targetFileCount = m_syncService->getTargetFileCount(id);
        response->syncedFileCount = m_syncService->getSyncedFileCount(id);
        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("POST", "/api/sync/{id}/commit", commitSync,
             PATH(Int64, id, "id"),
             BODY_DTO(Object<SyncCommitRequestDto>, body)) {
        LOG_INFO("POST /api/sync/{}/commit", static_cast<long>(id));

        auto config = m_repo->findById(id);
        if (!config) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "Sync config not found";
            return createDtoResponse(Status::CODE_404, error);
        }

        std::vector<std::string> paths;
        if (body->paths) {
            for (const auto& p : *body->paths) {
                if (p && !p->empty()) {
                    paths.push_back(std::string(p->data(), p->size()));
                }
            }
        }

        m_syncService->commitFiles(id, paths);

        auto response = ApiResponseDto::createShared();
        response->success = true;
        response->message = oatpp::String("Sync committed (" + std::to_string(paths.size()) + " files)");
        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("GET", "/api/sync/{id}/download", downloadFile,
             PATH(Int64, id, "id"),
             QUERY(String, path, "path")) {
        LOG_INFO("GET /api/sync/{}/download", static_cast<long>(id));

        auto config = m_repo->findById(id);
        if (!config) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "Sync config not found";
            return createDtoResponse(Status::CODE_404, error);
        }

        if (!path || path->empty()) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "path query parameter is required";
            return createDtoResponse(Status::CODE_400, error);
        }

        auto targetDir = m_syncService->resolveTargetDir(id);
        if (targetDir.empty()) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "Failed to resolve target directory";
            return createDtoResponse(Status::CODE_500, error);
        }

        std::string relPath(path->data(), path->size());
        auto filePath = targetDir / relPath;

        std::error_code ec;
        if (!std::filesystem::exists(filePath, ec) || !std::filesystem::is_regular_file(filePath, ec)) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = oatpp::String("File not found on server: " + relPath);
            return createDtoResponse(Status::CODE_404, error);
        }

        LOG_INFO("downloadFile: serving '{}'", filePath.string());

        std::ifstream file(filePath, std::ios::binary | std::ios::ate);
        if (!file) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "Failed to open file for reading";
            return createDtoResponse(Status::CODE_500, error);
        }

        auto size = file.tellg();
        file.seekg(0, std::ios::beg);

        auto buffer = std::make_shared<std::string>(static_cast<size_t>(size), '\0');
        file.read(buffer->data(), size);

        auto body = oatpp::web::protocol::http::outgoing::BufferBody::createShared(
            oatpp::String(buffer->data(), buffer->size()),
            "application/octet-stream");

        return oatpp::web::protocol::http::outgoing::Response::createShared(
            Status::CODE_200, body);
    }
};

} // namespace ainas

#include OATPP_CODEGEN_END(ApiController)
