#pragma once

#include "ainas/config/Config.hpp"
#include "ainas/dto/DTOs.hpp"
#include "ainas/logging/Logger.hpp"

#include "oatpp/web/protocol/http/outgoing/BufferBody.hpp"
#include "oatpp/web/protocol/http/outgoing/ResponseFactory.hpp"
#include "oatpp/web/server/api/ApiController.hpp"
#include "oatpp/json/ObjectMapper.hpp"
#include "oatpp/macro/codegen.hpp"

#include <memory>

#include OATPP_CODEGEN_BEGIN(ApiController)

namespace ainas {

class AiController : public oatpp::web::server::api::ApiController {
private:
    std::shared_ptr<Config> m_config;

public:
    AiController(const std::shared_ptr<ObjectMapper>& objectMapper,
                 std::shared_ptr<Config> config)
        : oatpp::web::server::api::ApiController(objectMapper)
        , m_config(std::move(config))
    {}

    static std::shared_ptr<AiController> createShared(
        const std::shared_ptr<ObjectMapper>& objectMapper,
        std::shared_ptr<Config> config)
    {
        return std::make_shared<AiController>(objectMapper, std::move(config));
    }

    ENDPOINT("GET", "/api/ai/status", getAiStatus) {
        LOG_INFO("GET /api/ai/status");
        auto response = AiStatusDto::createShared();
        response->status = "disabled";
        response->error = "AI features are not available in the C++ backend";
        response->elapsed = 0;
        response->models_available = 0;
        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("GET", "/api/ai/features", getAiFeatures) {
        LOG_INFO("GET /api/ai/features");
        auto json = oatpp::String("{\"status\":\"ready\",\"features\":[]}");
        auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
        return OutgoingResponse::createShared(Status::CODE_200, respBody);
    }

    ENDPOINT("POST", "/api/ai/features/{name}/model", setAiFeatureModel,
             PATH(String, name, "name"),
             BODY_DTO(Object<GenericJsonDto>, body)) {
        (void)body;
        LOG_INFO("POST /api/ai/features/{}/model (disabled)", name ? *name : "");
        auto response = ApiResponseDto::createShared();
        response->success = true;
        response->message = "AI features are disabled";
        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("GET", "/api/ai/models", getAiModels) {
        LOG_INFO("GET /api/ai/models");
        auto json = oatpp::String("{\"models\":[]}");
        auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
        return OutgoingResponse::createShared(Status::CODE_200, respBody);
    }

    ENDPOINT("POST", "/api/ai/models/hf", searchHfModels,
             BODY_DTO(Object<GenericJsonDto>, body)) {
        LOG_INFO("POST /api/ai/models/hf");
        (void)body;
        auto json = oatpp::String("[]");
        auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
        return OutgoingResponse::createShared(Status::CODE_200, respBody);
    }

    ENDPOINT("POST", "/api/ai/models/check", checkAiModel,
             BODY_DTO(Object<GenericJsonDto>, body)) {
        LOG_INFO("POST /api/ai/models/check");
        (void)body;
        auto json = oatpp::String("{\"available\":false}");
        auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
        return OutgoingResponse::createShared(Status::CODE_200, respBody);
    }

    ENDPOINT("POST", "/api/ai/models/download", downloadAiModel,
             BODY_DTO(Object<GenericJsonDto>, body)) {
        LOG_INFO("POST /api/ai/models/download");
        (void)body;
        auto response = ApiResponseDto::createShared();
        response->success = true;
        response->message = "AI model download not available";
        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("DELETE", "/api/ai/models", deleteAiModel,
             BODY_DTO(Object<GenericJsonDto>, body)) {
        LOG_INFO("DELETE /api/ai/models");
        (void)body;
        auto response = ApiResponseDto::createShared();
        response->success = true;
        response->message = "AI features are disabled";
        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("POST", "/api/ai/chat", chat,
             BODY_DTO(Object<GenericJsonDto>, body)) {
        LOG_INFO("POST /api/ai/chat");
        (void)body;
        auto json = oatpp::String("{\"text\":\"AI assistant is disabled in the C++ backend.\"}");
        auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
        return OutgoingResponse::createShared(Status::CODE_200, respBody);
    }

    ENDPOINT("POST", "/api/ai/chat/stream", chatStream,
             BODY_DTO(Object<GenericJsonDto>, body)) {
        LOG_INFO("POST /api/ai/chat/stream");
        (void)body;
        auto response = oatpp::web::protocol::http::outgoing::Response::createShared(
            Status::CODE_200,
            oatpp::web::protocol::http::outgoing::BufferBody::createShared(
                oatpp::String(""),
                oatpp::String("text/event-stream")));
        response->putHeader("Cache-Control", "no-cache");
        response->putHeader("Connection", "keep-alive");
        return response;
    }

    ENDPOINT("POST", "/api/ai/chat/cancel/{requestId}", cancelChat,
             PATH(String, requestId, "requestId")) {
        LOG_INFO("POST /api/ai/chat/cancel");
        auto response = ApiResponseDto::createShared();
        response->success = true;
        response->message = "No active chat to cancel";
        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("GET", "/api/ai/rag", getRagStatus) {
        LOG_INFO("GET /api/ai/rag");
        auto response = RagStatusDto::createShared();
        response->status = "disconnected";
        response->address = "";
        response->index = "";
        response->usage_docs = 0;
        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("GET", "/api/ai/rag/documents", getRagDocuments) {
        LOG_INFO("GET /api/ai/rag/documents");
        auto json = oatpp::String("{\"files\":[]}");
        auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
        return OutgoingResponse::createShared(Status::CODE_200, respBody);
    }

    ENDPOINT("DELETE", "/api/ai/rag", resetRag) {
        LOG_INFO("DELETE /api/ai/rag");
        auto response = ApiResponseDto::createShared();
        response->success = true;
        response->message = "RAG is not connected";
        return createDtoResponse(Status::CODE_200, response);
    }

    ENDPOINT("DELETE", "/api/ai/rag/documents", deleteRagDocument,
             QUERY(String, path, "path")) {
        LOG_INFO("DELETE /api/ai/rag/documents");
        auto response = ApiResponseDto::createShared();
        response->success = true;
        response->message = "RAG is not connected";
        return createDtoResponse(Status::CODE_200, response);
    }
};

} // namespace ainas

#include OATPP_CODEGEN_END(ApiController)
