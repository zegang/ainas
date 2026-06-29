#pragma once

#include "ainas/database/ConfigRepository.hpp"
#include "ainas/dto/DTOs.hpp"
#include "ainas/logging/Logger.hpp"

#include "oatpp/web/server/api/ApiController.hpp"
#include "oatpp/json/ObjectMapper.hpp"
#include "oatpp/macro/codegen.hpp"

#include <memory>

#include OATPP_CODEGEN_BEGIN(ApiController)

namespace ainas {

class ConfigController : public oatpp::web::server::api::ApiController {
private:
    std::shared_ptr<ConfigRepository> m_repo;

public:
    ConfigController(const std::shared_ptr<ObjectMapper>& objectMapper,
                     std::shared_ptr<ConfigRepository> repo)
        : oatpp::web::server::api::ApiController(objectMapper)
        , m_repo(std::move(repo))
    {}

    static std::shared_ptr<ConfigController> createShared(
        const std::shared_ptr<ObjectMapper>& objectMapper,
        std::shared_ptr<ConfigRepository> repo)
    {
        return std::make_shared<ConfigController>(objectMapper, std::move(repo));
    }

    ENDPOINT("GET", "/api/config", listConfigs) {
        LOG_INFO("GET /api/config");
        auto response = ConfigListResponseDto::createShared();
        response->success = true;

        auto entries = m_repo->getAll();
        auto configs = oatpp::Vector<oatpp::Object<ConfigEntryDto>>::createShared();
        for (const auto& entry : entries) {
            auto dto = ConfigEntryDto::createShared();
            dto->key = oatpp::String(entry.key);
            dto->value = oatpp::String(entry.value);
            configs->push_back(dto);
        }
        response->configs = configs;
        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("GET", "/api/config/{key}", getConfig,
             PATH(String, key)) {
        LOG_INFO("GET /api/config/{}", key ? key->c_str() : "");
        auto response = ConfigListResponseDto::createShared();

        auto k = std::string(key->data(), key->size());
        auto entry = m_repo->get(k);
        if (!entry) {
            response->success = false;
            return createDtoResponse(Status::CODE_404, response);
        }

        response->success = true;
        auto dto = ConfigEntryDto::createShared();
        dto->key = oatpp::String(entry->key);
        dto->value = oatpp::String(entry->value);
        auto configs = oatpp::Vector<oatpp::Object<ConfigEntryDto>>::createShared();
        configs->push_back(dto);
        response->configs = configs;
        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("PUT", "/api/config/{key}", updateConfig,
             PATH(String, key),
             BODY_DTO(Object<ConfigUpdateRequestDto>, body)) {
        LOG_INFO("PUT /api/config/{}", key ? key->c_str() : "");

        if (!body->value || body->value->empty()) {
            auto error = ApiResponseDto::createShared();
            error->success = false;
            error->message = "value is required";
            return createDtoResponse(Status::CODE_400, error);
        }

        auto k = std::string(key->data(), key->size());
        auto v = std::string(body->value->data(), body->value->size());
        m_repo->set(k, v);

        // Dynamically apply runtime-configurable settings
        if (k == "log_level") {
            if (v == "trace") Logger::instance().setLevel(LogLevel::Trace);
            else if (v == "debug") Logger::instance().setLevel(LogLevel::Debug);
            else if (v == "info")  Logger::instance().setLevel(LogLevel::Info);
            else if (v == "warn")  Logger::instance().setLevel(LogLevel::Warn);
            else if (v == "error") Logger::instance().setLevel(LogLevel::Error);
            LOG_INFO("Log level changed to {}", v);
        } else if (k == "log_file") {
            Logger::instance().setLogFile(v);
            LOG_INFO("Log file changed to {}", v);
        }

        auto response = ApiResponseDto::createShared();
        response->success = true;
        response->message = oatpp::String("Config '" + k + "' updated");
        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("DELETE", "/api/config/{key}", deleteConfig,
             PATH(String, key)) {
        LOG_INFO("DELETE /api/config/{}", key ? key->c_str() : "");

        auto k = std::string(key->data(), key->size());
        auto deleted = m_repo->remove(k);

        if (!deleted) {
            auto response = ApiResponseDto::createShared();
            response->success = false;
            response->message = oatpp::String("Config '" + k + "' not found");
            return createDtoResponse(Status::CODE_404, response);
        }

        auto response = ApiResponseDto::createShared();
        response->success = true;
        response->message = oatpp::String("Config '" + k + "' deleted");
        return createDtoResponse(Status::CODE_200, response);
    }
};

} // namespace ainas

#include OATPP_CODEGEN_END(ApiController)
