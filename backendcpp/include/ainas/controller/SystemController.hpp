#pragma once

#include "ainas/config/Config.hpp"
#include "ainas/dto/DTOs.hpp"
#include "ainas/logging/Logger.hpp"

#include "oatpp/web/server/api/ApiController.hpp"
#include "oatpp/json/ObjectMapper.hpp"
#include "oatpp/macro/codegen.hpp"

#include <filesystem>
#include <memory>

#include OATPP_CODEGEN_BEGIN(ApiController)

namespace ainas {

class SystemController : public oatpp::web::server::api::ApiController {
private:
    std::shared_ptr<Config> m_config;

public:
    SystemController(const std::shared_ptr<ObjectMapper>& objectMapper,
                     std::shared_ptr<Config> config)
        : oatpp::web::server::api::ApiController(objectMapper)
        , m_config(std::move(config))
    {}

    static std::shared_ptr<SystemController> createShared(
        const std::shared_ptr<ObjectMapper>& objectMapper,
        std::shared_ptr<Config> config)
    {
        return std::make_shared<SystemController>(objectMapper, std::move(config));
    }

    ENDPOINT("GET", "/api/status", status) {
        LOG_INFO("GET /api/status");
        auto response = StatusResponseDto::createShared();
        response->status = "running";
        response->aiStatus = "disabled";
        response->aiEnabled = false;
        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("GET", "/api/system/usage", getSystemUsage) {
        LOG_INFO("GET /api/system/usage");
        auto response = SystemUsageDto::createShared();
        std::error_code ec;
        auto space = std::filesystem::space(m_config->dataPath);
        auto total = static_cast<double>(space.capacity) / (1024.0 * 1024.0 * 1024.0);
        auto free = static_cast<double>(space.available) / (1024.0 * 1024.0 * 1024.0);
        auto used = total - free;
        auto pct = total > 0.0 ? (used / total * 100.0) : 0.0;
        response->total_gb = total;
        response->free_gb = free;
        response->percent_used = pct;
        response->percent = pct;
        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("PATCH", "/api/system/storage-root", updateStorageRoot,
             BODY_DTO(Object<UpdateStorageRootDto>, body)) {
        if (!body->path || body->path->empty()) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "path is required";
            return createDtoResponse(Status::CODE_400, error);
        }

        auto newRoot = std::string(body->path->data(), body->path->size());
        std::error_code ec;
        if (!std::filesystem::exists(newRoot, ec)) {
            std::filesystem::create_directories(newRoot, ec);
        }
        if (ec) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = oatpp::String("Failed to create directory: " + ec.message());
            return createDtoResponse(Status::CODE_400, error);
        }

        auto oldDb = m_config->dbPath.string();
        m_config->rebase(newRoot);

        LOG_INFO("Storage root updated: {} -> {}", oldDb, m_config->dbPath.string());
        if (m_config->dbPath.string() != oldDb) {
            LOG_WARN("DB path changed from {} to {} — restart required to pick up new database",
                     oldDb, m_config->dbPath.string());
        }

        auto response = ApiResponseDto::createShared();
        response->success = true;
        response->message = oatpp::String(
            "Storage root updated to " + m_config->storageRoot.string());
        response->path = oatpp::String(m_config->storageRoot.string());
        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("GET", "/api/system/config", getSystemConfig) {
        LOG_INFO("GET /api/system/config");
        auto response = SystemConfigResponseDto::createShared();
        response->storageRoot = oatpp::String(m_config->storageRoot.string());
        response->dataPath = oatpp::String(m_config->dataPath.string());
        response->dbPath = oatpp::String(m_config->dbPath.string());
        response->nasmetadataPath = oatpp::String(m_config->nasmetadataPath.string());
        return createDtoResponse(Status::CODE_200, response);
    }
};

} // namespace ainas

#include OATPP_CODEGEN_END(ApiController)
