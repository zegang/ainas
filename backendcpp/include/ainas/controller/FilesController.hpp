#pragma once

#include "ainas/config/Config.hpp"
#include "ainas/dto/DTOs.hpp"
#include "ainas/logging/Logger.hpp"
#include "ainas/service/FileService.hpp"
#include "ainas/service/ThumbnailService.hpp"

#include <memory>
#include <thread>

#include "oatpp/web/mime/multipart/FileProvider.hpp"
#include "oatpp/web/mime/multipart/InMemoryDataProvider.hpp"
#include "oatpp/web/mime/multipart/Reader.hpp"
#include "oatpp/web/mime/multipart/PartList.hpp"
#include "oatpp/web/protocol/http/outgoing/BufferBody.hpp"
#include "oatpp/web/protocol/http/outgoing/ResponseFactory.hpp"
#include "oatpp/web/server/api/ApiController.hpp"
#include "oatpp/json/ObjectMapper.hpp"
#include "oatpp/macro/codegen.hpp"

#include <fstream>

#include OATPP_CODEGEN_BEGIN(ApiController)

namespace ainas {

// Strip leading '/' from relative path for thumbnail service
inline std::filesystem::path stripLeadingSlash(const std::string& p) {
    if (p.empty()) return {};
    if (p[0] == '/') return std::filesystem::path(p.substr(1));
    return std::filesystem::path(p);
}

namespace detail {
inline std::string str(const oatpp::String& s) {
    if (!s) return "";
    return {s->data(), static_cast<size_t>(s->size())};
}

inline std::string urlDecode(const std::string& encoded) {
    std::string result;
    result.reserve(encoded.size());
    for (size_t i = 0; i < encoded.size(); ++i) {
        if (encoded[i] == '%' && i + 2 < encoded.size()) {
            auto hexVal = [](char c) -> int {
                if (c >= '0' && c <= '9') return c - '0';
                if (c >= 'a' && c <= 'f') return c - 'a' + 10;
                if (c >= 'A' && c <= 'F') return c - 'A' + 10;
                return 0;
            };
            char hi = static_cast<char>(encoded[i + 1]);
            char lo = static_cast<char>(encoded[i + 2]);
            bool valid = (hi >= '0' && hi <= '9') || (hi >= 'a' && hi <= 'f') || (hi >= 'A' && hi <= 'F');
            valid = valid && ((lo >= '0' && lo <= '9') || (lo >= 'a' && lo <= 'f') || (lo >= 'A' && lo <= 'F'));
            if (valid) {
                result += static_cast<char>((hexVal(hi) << 4) | hexVal(lo));
                i += 2;
                continue;
            }
        }
        result += encoded[i];
    }
    return result;
}

inline std::string mimeType(const std::filesystem::path& path) {
    auto ext = path.extension().string();
    if (ext == ".pdf") return "application/pdf";
    if (ext == ".jpg" || ext == ".jpeg") return "image/jpeg";
    if (ext == ".png") return "image/png";
    if (ext == ".gif") return "image/gif";
    if (ext == ".webp") return "image/webp";
    if (ext == ".svg") return "image/svg+xml";
    if (ext == ".bmp") return "image/bmp";
    if (ext == ".mp4") return "video/mp4";
    if (ext == ".webm") return "video/webm";
    if (ext == ".mov") return "video/quicktime";
    if (ext == ".mp3") return "audio/mpeg";
    if (ext == ".wav") return "audio/wav";
    if (ext == ".ogg") return "audio/ogg";
    if (ext == ".doc" || ext == ".docx") return "application/msword";
    if (ext == ".xls" || ext == ".xlsx") return "application/vnd.ms-excel";
    if (ext == ".ppt" || ext == ".pptx") return "application/vnd.ms-powerpoint";
    if (ext == ".zip") return "application/zip";
    if (ext == ".tar") return "application/x-tar";
    if (ext == ".gz") return "application/gzip";
    if (ext == ".json") return "application/json";
    if (ext == ".xml") return "application/xml";
    if (ext == ".txt" || ext == ".md") return "text/plain";
    if (ext == ".html" || ext == ".htm") return "text/html";
    if (ext == ".css") return "text/css";
    if (ext == ".js") return "application/javascript";
    return "application/octet-stream";
}
} // namespace detail

class FilesController : public oatpp::web::server::api::ApiController {
private:
    std::shared_ptr<FileService> m_fileService;
    std::shared_ptr<Config> m_config;
    std::shared_ptr<ThumbnailService> m_thumbnailService;

public:
    FilesController(const std::shared_ptr<ObjectMapper>& objectMapper,
                    const std::shared_ptr<FileService>& fileService,
                    std::shared_ptr<Config> config,
                    std::shared_ptr<ThumbnailService> thumbnailService)
        : oatpp::web::server::api::ApiController(objectMapper)
        , m_fileService(fileService)
        , m_config(std::move(config))
        , m_thumbnailService(std::move(thumbnailService))
    {}

    static std::shared_ptr<FilesController> createShared(
        const std::shared_ptr<ObjectMapper>& objectMapper,
        const std::shared_ptr<FileService>& fileService,
        std::shared_ptr<Config> config,
        std::shared_ptr<ThumbnailService> thumbnailService)
    {
        return std::make_shared<FilesController>(objectMapper, fileService, std::move(config),
                                                 std::move(thumbnailService));
    }

    ENDPOINT("GET", "/api/files", listFiles,
             QUERY(String, path, "path", "/")) {
        auto decodedPath = oatpp::String(detail::urlDecode(detail::str(path)));
        LOG_INFO("GET /api/files?path=\"{}\"", detail::str(decodedPath));
        auto result = m_fileService->listFiles(decodedPath);
        if (result->success) {
            return createDtoResponse(Status::CODE_200, result);
        }
        return createDtoResponse(Status::CODE_404, result);
    }

    ENDPOINT("POST", "/api/files/upload", upload,
             REQUEST(std::shared_ptr<IncomingRequest>, request)) {
        LOG_INFO("POST /api/files/upload");
        auto multipart = std::make_shared<oatpp::web::mime::multipart::PartList>(
            request->getHeaders());

        oatpp::web::mime::multipart::Reader reader(multipart.get());

        auto tmpPath = std::filesystem::temp_directory_path() /
            ("ainas_upload_" + FileService::generateRandomString(16));

        reader.setPartReader("file",
            oatpp::web::mime::multipart::createFilePartReader(
                tmpPath.string(), m_config->maxUploadSize));
        reader.setPartReader("path",
            oatpp::web::mime::multipart::createInMemoryPartReader(1024));

        request->transferBody(&reader);

        auto filePart = multipart->getNamedPart("file");
        if (!filePart) {
            std::error_code ec;
            std::filesystem::remove(tmpPath, ec);
            auto error = UploadResponseDto::createShared();
            error->success = false;
            error->message = "No file uploaded";
            return createDtoResponse(Status::CODE_400, error);
        }

        auto filename = filePart->getFilename();
        auto pathPart = multipart->getNamedPart("path");
        auto targetDir = pathPart ? pathPart->getPayload()->getInMemoryData()
                                  : oatpp::String("/");

        try {
            auto result = m_fileService->uploadFile(
                tmpPath.string(), filename, targetDir);
            if (result->success) {
                if (result->path && !result->path->empty()) {
                    auto relPath = stripLeadingSlash(detail::str(result->path));
                    auto thumbSvc = m_thumbnailService;
                    std::thread([relPath=std::move(relPath), thumbSvc=std::move(thumbSvc)]() {
                        try {
                            if (ThumbnailService::isSupportedImage(relPath)) {
                                thumbSvc->generate(relPath);
                            }
                        } catch (const std::exception& e) {
                            LOG_ERROR("Thumbnail generation failed: {}", e.what());
                        }
                    }).detach();
                }
                return createDtoResponse(Status::CODE_200, result);
            }
            return createDtoResponse(Status::CODE_400, result);
        } catch (const std::exception& e) {
            std::error_code ec;
            std::filesystem::remove(tmpPath, ec);
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = oatpp::String(e.what());
            return createDtoResponse(Status::CODE_500, error);
        }
    }

    ENDPOINT("POST", "/api/files/folder", createFolder,
             BODY_DTO(Object<CreateFolderRequestDto>, body)) {
        LOG_INFO("POST /api/files/folder (path=\"{}\")", detail::str(body->path));
        auto result = m_fileService->createFolder(body->path);
        auto status = result->success ? Status::CODE_200 : Status::CODE_400;
        return createDtoResponse(status, result);
    }

    ENDPOINT("DELETE", "/api/files", deleteFile,
             BODY_DTO(Object<DeleteRequestDto>, body)) {
        LOG_INFO("DELETE /api/files (path=\"{}\")", detail::str(body->path));
        auto result = m_fileService->deleteFile(body->path);
        if (result->success && body->path && !body->path->empty()) {
            m_thumbnailService->remove(stripLeadingSlash(detail::str(body->path)));
        }
        auto status = Status::CODE_200;
        if (!result->success) {
            status = result->message &&
                     result->message->find("does not exist") != std::string::npos
                     ? Status::CODE_404 : Status::CODE_400;
        }
        return createDtoResponse(status, result);
    }

    ENDPOINT("PATCH", "/api/files/move", moveFile,
             BODY_DTO(Object<MoveRequestDto>, body)) {
        auto idVal = body->id ? static_cast<int64_t>(*body->id) : int64_t(0);
        LOG_INFO("PATCH /api/files/move (path=\"{}\" id={})",
                 detail::str(body->path), idVal);
        auto result = m_fileService->moveFile(body);
        if (result->success && result->path && !result->path->empty()
            && body->path && !body->path->empty()) {
            auto oldRel = stripLeadingSlash(detail::str(body->path));
            auto newRel = stripLeadingSlash(detail::str(result->path));
            if (ThumbnailService::isSupportedImage(oldRel)
                || ThumbnailService::isSupportedImage(newRel)) {
                m_thumbnailService->move(oldRel, newRel);
            }
        }
        auto status = result->success ? Status::CODE_200 : Status::CODE_400;
        return createDtoResponse(status, result);
    }

    ENDPOINT("POST", "/api/files/copy", copyFile,
             BODY_DTO(Object<CopyRequestDto>, body)) {
        auto dirId = body->targetDirId ? static_cast<int64_t>(*body->targetDirId) : int64_t(0);
        LOG_INFO("POST /api/files/copy (targetDir=\"{}\" targetDirId={})",
                 detail::str(body->targetDir), dirId);
        auto result = m_fileService->copyFile(body);
        if (result->success && result->files && result->sources
            && result->files->size() == result->sources->size()) {
            for (size_t i = 0; i < result->files->size(); ++i) {
                auto dstRel = stripLeadingSlash(detail::str(result->files[i]));
                if (!ThumbnailService::isSupportedImage(dstRel)) continue;
                auto srcRel = stripLeadingSlash(detail::str(result->sources[i]));
                m_thumbnailService->copy(srcRel, dstRel);
            }
        }
        auto status = result->success ? Status::CODE_200 : Status::CODE_400;
        return createDtoResponse(status, result);
    }

    ENDPOINT("PATCH", "/api/files/rename", renameFile,
             BODY_DTO(Object<RenameRequestDto>, body)) {
        LOG_INFO("PATCH /api/files/rename (\"{}\" -> \"{}\")",
                 detail::str(body->path), detail::str(body->newName));
        auto result = m_fileService->renameFile(body);
        if (result->success && result->path && !result->path->empty()
            && body->path && !body->path->empty()) {
            auto oldRel = stripLeadingSlash(detail::str(body->path));
            auto newRel = stripLeadingSlash(detail::str(result->path));
            if (ThumbnailService::isSupportedImage(oldRel)
                || ThumbnailService::isSupportedImage(newRel)) {
                m_thumbnailService->move(oldRel, newRel);
            }
        }
        auto status = result->success ? Status::CODE_200 : Status::CODE_400;
        return createDtoResponse(status, result);
    }

    ENDPOINT("GET", "/api/files/download", downloadFile,
             QUERY(String, path, "path"),
             QUERY(Boolean, thumbnail, "thumbnail", false)) {
        LOG_INFO("GET /api/files/download?path=\"{}\"", detail::str(path));

        if (!path || path->empty()) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "path is required";
            return createDtoResponse(Status::CODE_400, error);
        }

        auto relPath = detail::urlDecode(detail::str(path));
        std::filesystem::path fullPath;

        // When thumbnail is requested, generate on-the-fly if missing, then serve
        if (thumbnail) {
            if (!m_thumbnailService->exists(relPath)) {
                try {
                    m_fileService->resolveExistingPath(relPath);
                    if (ThumbnailService::isSupportedImage(relPath)) {
                        m_thumbnailService->generate(relPath);
                    }
                } catch (...) {}
            }
            if (m_thumbnailService->exists(relPath)) {
                fullPath = m_thumbnailService->thumbnailPath(relPath);
            } else {
                try {
                    fullPath = m_fileService->resolveExistingPath(relPath);
                } catch (const FileServiceError& e) {
                    auto error = ApiResponseDto::createShared();
                    error->success = false;
                    error->message = oatpp::String(e.what());
                    auto status = e.kind == FileServiceError::Kind::NotFound
                                  ? Status::CODE_404 : Status::CODE_400;
                    return createDtoResponse(status, error);
                }
            }
        } else {
            try {
                fullPath = m_fileService->resolveExistingPath(relPath);
            } catch (const FileServiceError& e) {
                auto error = ApiResponseDto::createShared();
                error->success = false;
                error->message = oatpp::String(e.what());
                auto status = e.kind == FileServiceError::Kind::NotFound
                              ? Status::CODE_404 : Status::CODE_400;
                return createDtoResponse(status, error);
            }
        }

        std::error_code ec;
        if (!std::filesystem::is_regular_file(fullPath, ec)) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "Not a file";
            return createDtoResponse(Status::CODE_400, error);
        }

        std::ifstream file(fullPath, std::ios::binary | std::ios::ate);
        if (!file) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "Failed to open file";
            return createDtoResponse(Status::CODE_500, error);
        }

        auto size = file.tellg();
        file.seekg(0, std::ios::beg);

        auto buffer = std::make_shared<std::string>(static_cast<size_t>(size), '\0');
        file.read(buffer->data(), size);

        auto body = oatpp::web::protocol::http::outgoing::BufferBody::createShared(
            oatpp::String(buffer->data(), buffer->size()),
            oatpp::String(detail::mimeType(fullPath)));

        auto response = oatpp::web::protocol::http::outgoing::Response::createShared(
            Status::CODE_200, body);

        if (thumbnail) {
            response->putHeader("Content-Disposition", "inline");
        } else {
            response->putHeader("Content-Disposition",
                "attachment; filename=\"" + fullPath.filename().string() + "\"");
        }

        return response;
    }

    ENDPOINT("GET", "/api/files/{id}", getFileById,
             PATH(Int64, id, "id")) {
        LOG_INFO("GET /api/files/{}", *id);
        auto result = m_fileService->getFileById(*id);
        auto status = result->success ? Status::CODE_200 : Status::CODE_404;
        return createDtoResponse(status, result);
    }

    ENDPOINT("DELETE", "/api/files/{id}", deleteFileById,
             PATH(Int64, id, "id")) {
        LOG_INFO("DELETE /api/files/{}", *id);
        auto result = m_fileService->deleteFileById(*id);
        if (result->success && result->path && !result->path->empty()) {
            m_thumbnailService->remove(stripLeadingSlash(detail::str(result->path)));
        }
        auto status = result->success ? Status::CODE_200 : Status::CODE_404;
        return createDtoResponse(status, result);
    }

    ENDPOINT("PATCH", "/api/files/{id}", updateFile,
             PATH(Int64, id, "id"),
             BODY_DTO(Object<UpdateFileRequestDto>, body)) {
        LOG_INFO("PATCH /api/files/{}", *id);
        auto old = m_fileService->getFileById(*id);
        auto result = m_fileService->updateFile(*id, body);
        if (result->success && result->file && old->success && old->file) {
            auto oldPath = stripLeadingSlash(detail::str(old->file->path));
            auto newPath = stripLeadingSlash(detail::str(result->file->path));
            if (oldPath != newPath && (ThumbnailService::isSupportedImage(oldPath)
                                       || ThumbnailService::isSupportedImage(newPath))) {
                m_thumbnailService->move(oldPath, newPath);
            }
        }
        auto status = result->success ? Status::CODE_200 : Status::CODE_404;
        return createDtoResponse(status, result);
    }
};

} // namespace ainas

#include OATPP_CODEGEN_END(ApiController)
