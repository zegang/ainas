#pragma once

#include "ainas/config/Config.hpp"
#include "ainas/dto/DTOs.hpp"
#include "ainas/lic/lic.h"
#include "ainas/logging/Logger.hpp"
#include "ainas/service/AiService.hpp"
#include "ainas/string_util.hpp"

#include <httplib.h>
#include <nlohmann/json.hpp>

#include "oatpp/web/protocol/http/outgoing/Body.hpp"
#include "oatpp/web/protocol/http/outgoing/BufferBody.hpp"
#include "oatpp/web/protocol/http/outgoing/ResponseFactory.hpp"
#include "oatpp/web/protocol/http/outgoing/StreamingBody.hpp"
#include "oatpp/web/server/api/ApiController.hpp"
#include "oatpp/json/ObjectMapper.hpp"
#include "oatpp/macro/codegen.hpp"

#include <algorithm>
#include <condition_variable>
#include <cstring>
#include <fstream>
#include <memory>
#include <mutex>
#include <queue>
#include <thread>
#include <unordered_set>

#include OATPP_CODEGEN_BEGIN(ApiController)

namespace ainas {

namespace {

httplib::Client makeCli(int port) {
    httplib::Client cli("127.0.0.1", port);
    cli.set_connection_timeout(5);
    cli.set_read_timeout(120);
    return cli;
}

oatpp::String forwardPost(const std::string& path, const oatpp::String& body,
                          const std::string& contentType, int port) {
    auto cli = makeCli(port);
    auto res = cli.Post(path, body ? body->c_str() : "", contentType.c_str());
    if (!res) {
        auto err = nlohmann::json{{"error", "Failed to connect to AI server"}};
        return oatpp::String(err.dump());
    }
    return oatpp::String(res->body);
}

/// Reads text file content from storage, returns empty string on failure.
std::string readTextFile(const std::filesystem::path& fullPath, size_t maxSize = 1024 * 1024) {
    std::error_code ec;
    if (!std::filesystem::exists(fullPath, ec)) return {};
    auto size = std::filesystem::file_size(fullPath, ec);
    if (ec || size > maxSize) return {};
    std::ifstream ifs(fullPath);
    if (!ifs) return {};
    return {std::istreambuf_iterator<char>(ifs), std::istreambuf_iterator<char>()};
}

/// Appends file contents as context to the last user message in cllamaReq.
void attachFilesToRequest(const nlohmann::json& reqJson,
                          nlohmann::json& cllamaReq,
                          const std::filesystem::path& storageRoot) {
    if (!reqJson.contains("files") || !reqJson["files"].is_array() || reqJson["files"].empty())
        return;

    std::string fileContext;
    for (const auto& f : reqJson["files"]) {
        std::string filePath = f.get<std::string>();
        auto fullPath = storageRoot / std::filesystem::path(filePath).relative_path();

        static const std::unordered_set<std::string> textExts = {
            ".txt", ".md", ".json", ".csv", ".log", ".xml", ".yaml", ".yml",
            ".ini", ".cfg", ".conf", ".py", ".js", ".ts", ".html", ".css",
            ".sh", ".bat", ".ps1", ".sql", ".java", ".cpp", ".h", ".hpp",
            ".c", ".rs", ".go", ".rb", ".php"
        };
        std::string ext;
        auto p = fullPath.extension().string();
        std::transform(p.begin(), p.end(), std::back_inserter(ext), ::tolower);

        if (textExts.count(ext)) {
            auto content = readTextFile(fullPath);
            if (!content.empty()) {
                fileContext += "\n[Attached file: " + filePath + "]\n" + content + "\n";
            } else {
                fileContext += "\n[Attached file: " + filePath + " (unreadable or too large)]\n";
            }
        } else {
            fileContext += "\n[File: " + filePath + " (binary, content not included)]\n";
        }
    }

    if (fileContext.empty()) return;

    auto& messages = cllamaReq["messages"];
    if (!messages.empty() && messages.back()["role"] == "user") {
        messages.back()["content"] = messages.back()["content"].get<std::string>() + "\n\n" + fileContext;
    } else {
        nlohmann::json fileMsg;
        fileMsg["role"] = "user";
        fileMsg["content"] = fileContext;
        messages.push_back(fileMsg);
    }
}

} // anonymous namespace

// ReadCallback that parses cllama SSE response and streams chunks through oatpp.
class SseProxyCallback : public oatpp::data::stream::ReadCallback {
private:
    std::queue<std::string> m_chunks;
    std::mutex m_mtx;
    bool m_done = false;

public:
    SseProxyCallback(const std::string& jsonBody, int port) {
        httplib::Client cli("127.0.0.1", port);
        cli.set_connection_timeout(5);
        cli.set_read_timeout(120);
        auto res = cli.Post("/v1/chat/completions", jsonBody, "application/json");
        if (!res) {
            m_chunks.push("{\"error\":\"AI server unreachable\"}");
            m_done = true;
            return;
        }
        std::string body = res->body;
        size_t pos = 0;
        while (pos < body.size()) {
            size_t nl = body.find('\n', pos);
            if (nl == std::string::npos) break;
            std::string line(body, pos, nl - pos);
            pos = nl + 1;
            if (line.empty()) continue;
            if (line.back() == '\r') line.pop_back();
            if (line.empty()) continue;
            if (line.rfind("data: ", 0) == 0) {
                std::string jsonStr = line.substr(6);
                if (jsonStr == "[DONE]") break;
                jsonStr = sanitizeUtf8(jsonStr);
                try {
                    auto j = nlohmann::json::parse(jsonStr);
                    auto& choices = j["choices"];
                    if (!choices.empty() && choices[0].contains("delta")) {
                        auto& delta = choices[0]["delta"];
                        if (delta.contains("content")) {
                            auto content = delta["content"].get<std::string>();
                            m_chunks.push(sanitizeUtf8(content));
                        }
                    }
                } catch (...) {}
            }
        }
        m_done = true;
    }

    int64_t read(void* buffer, intptr_t count, oatpp::async::Action& action) override {
        (void)action;
        std::lock_guard<std::mutex> lock(m_mtx);
        if (!m_chunks.empty()) {
            auto& chunk = m_chunks.front();
            size_t toCopy = std::min(chunk.size(), static_cast<size_t>(count));
            std::memcpy(buffer, chunk.data(), toCopy);
            if (toCopy == chunk.size()) {
                m_chunks.pop();
            } else {
                chunk = chunk.substr(toCopy);
            }
            return static_cast<int64_t>(toCopy);
        }
        return m_done ? 0 : -1;
    }
};

class AiController : public oatpp::web::server::api::ApiController {
private:
    std::shared_ptr<Config> m_config;
    std::shared_ptr<AiState> m_aiState;
    std::shared_ptr<AiService> m_aiService;

public:
    AiController(const std::shared_ptr<ObjectMapper>& objectMapper,
                 std::shared_ptr<Config> config,
                 std::shared_ptr<AiState> aiState,
                 std::shared_ptr<AiService> aiService)
        : oatpp::web::server::api::ApiController(objectMapper)
        , m_config(std::move(config))
        , m_aiState(std::move(aiState))
        , m_aiService(std::move(aiService))
    {}

    /// Returns nullptr if AI permission is granted, or a 403 error response.
    std::shared_ptr<OutgoingResponse> _licGate() {
        if (!lic::hasPermission("ai")) {
            auto json = oatpp::String(
                "{\"error\":\"AI features require a license with ai permission\"}");
            auto body = oatpp::web::protocol::http::outgoing::BufferBody::createShared(
                json, "application/json");
            return OutgoingResponse::createShared(Status::CODE_403, body);
        }
        return nullptr;
    }

    static std::shared_ptr<AiController> createShared(
        const std::shared_ptr<ObjectMapper>& objectMapper,
        std::shared_ptr<Config> config,
        std::shared_ptr<AiState> aiState,
        std::shared_ptr<AiService> aiService)
    {
        return std::make_shared<AiController>(objectMapper, std::move(config), std::move(aiState), std::move(aiService));
    }

    // ── GET /api/ai/status ────────────────────────────────────────
    ENDPOINT("GET", "/api/ai/status", getAiStatus) {
        LOG_INFO("GET /api/ai/status");
        if (auto err = _licGate()) return err;
        auto body = oatpp::String(m_aiService->getStatus());
        auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(body, "application/json");
        return OutgoingResponse::createShared(Status::CODE_200, respBody);
    }

    // ── POST /api/ai/enable ───────────────────────────────────────
    ENDPOINT("POST", "/api/ai/enable", enableAi) {
        LOG_INFO("POST /api/ai/enable");
        if (auto err = _licGate()) return err;
        if (m_aiState->enabled.load()) {
            auto response = ApiResponseDto::createShared();
            response->success = true;
            response->message = "AI already enabled";
            return createDtoResponse(Status::CODE_200, response);
        }
        m_config->aiEnabled = true;
        if (m_aiService->start()) {
            auto response = ApiResponseDto::createShared();
            response->success = true;
            response->message = "AI enabled";
            return createDtoResponse(Status::CODE_200, response);
        }
        m_config->aiEnabled = false;
        auto response = ApiResponseDto::createShared();
        response->success = false;
        response->message = "Failed to enable AI";
        return createDtoResponse(Status::CODE_500, response);
    }

    // ── POST /api/ai/disable ──────────────────────────────────────
    ENDPOINT("POST", "/api/ai/disable", disableAi) {
        LOG_INFO("POST /api/ai/disable");
        if (!m_aiState->enabled.load()) {
            auto response = ApiResponseDto::createShared();
            response->success = true;
            response->message = "AI already disabled";
            return createDtoResponse(Status::CODE_200, response);
        }
        m_aiService->stop();
        m_config->aiEnabled = false;
        auto response = ApiResponseDto::createShared();
        response->success = true;
        response->message = "AI disabled";
        return createDtoResponse(Status::CODE_200, response);
    }

    // ── GET /api/ai/features ─────────────────────────────────────
    ENDPOINT("GET", "/api/ai/features", getAiFeatures) {
        LOG_INFO("GET /api/ai/features");
        if (auto err = _licGate()) return err;
        if (!m_aiState->enabled.load()) {
            auto json = oatpp::String("{\"features\":[]}");
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
            return OutgoingResponse::createShared(Status::CODE_200, respBody);
        }
        auto json = oatpp::String(m_aiService->listFeatures());
        auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
        return OutgoingResponse::createShared(Status::CODE_200, respBody);
    }

    // ── POST /api/ai/features/{name}/model ────────────────────────
    ENDPOINT("POST", "/api/ai/features/{name}/model", setAiFeatureModel,
             PATH(String, name, "name"),
             REQUEST(std::shared_ptr<IncomingRequest>, request)) {
        auto featureName = name ? *name : "";
        LOG_INFO("POST /api/ai/features/{}/model", featureName);
        if (auto err = _licGate()) return err;
        auto bodyStr = request->readBodyToString();
        if (!m_aiState->enabled.load() || featureName.empty()) {
            auto json = oatpp::String("{\"success\":false,\"message\":\"AI features are disabled\"}");
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
            return OutgoingResponse::createShared(Status::CODE_200, respBody);
        }
        try {
            auto reqJson = nlohmann::json::parse(sanitizeUtf8(bodyStr ? *bodyStr : ""));
            std::string modelName = reqJson.value("model_name", "");
            if (modelName.empty()) {
                auto json = oatpp::String("{\"success\":false,\"message\":\"model_name is required\"}");
                auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
                return OutgoingResponse::createShared(Status::CODE_200, respBody);
            }
            m_aiService->updateFeatureState(featureName, modelName, "loading", "");
            auto json = oatpp::String(
                (nlohmann::json{{"success",true},{"message","Model '" + modelName + "' is being set for feature '" + featureName + "' in background."}}).dump());
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
            return OutgoingResponse::createShared(Status::CODE_202, respBody);
        } catch (const std::exception& e) {
            LOG_ERROR("POST /api/ai/features/{}/model parse error: {}", featureName, e.what());
            auto json = oatpp::String("{\"success\":false,\"message\":\"parse error\"}");
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
            return OutgoingResponse::createShared(Status::CODE_500, respBody);
        }
    }

    // ── GET /api/ai/models ────────────────────────────────────────
    ENDPOINT("GET", "/api/ai/models", getAiModels) {
        LOG_INFO("GET /api/ai/models");
        if (!m_aiState->enabled.load()) {
            auto json = oatpp::String("{\"models\":[]}");
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
            return OutgoingResponse::createShared(Status::CODE_200, respBody);
        }
        auto json = oatpp::String(m_aiService->listModels());
        auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
        return OutgoingResponse::createShared(Status::CODE_200, respBody);
    }

    // ── GET /api/ai/models/{name} ─────────────────────────────────
    ENDPOINT("GET", "/api/ai/models/{modelName}", showAiModel,
             PATH(String, modelName, "modelName")) {
        LOG_INFO("GET /api/ai/models/{}", modelName ? *modelName : "");
        if (!m_aiState->enabled.load()) {
            auto json = oatpp::String("{\"error\":\"AI features are disabled\"}");
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
            return OutgoingResponse::createShared(Status::CODE_200, respBody);
        }
        auto json = oatpp::String(m_aiService->showModel(modelName ? *modelName : ""));
        auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
        return OutgoingResponse::createShared(Status::CODE_200, respBody);
    }

    // ── GET /api/ai/runners ───────────────────────────────────────
    ENDPOINT("GET", "/api/ai/runners", listRunners) {
        LOG_INFO("GET /api/ai/runners");
        if (!m_aiState->enabled.load()) {
            auto json = oatpp::String("{\"object\":\"list\",\"data\":[]}");
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
            return OutgoingResponse::createShared(Status::CODE_200, respBody);
        }
        auto json = oatpp::String(m_aiService->listRunners());
        auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
        return OutgoingResponse::createShared(Status::CODE_200, respBody);
    }

    // ── POST /api/ai/runners ──────────────────────────────────────
    ENDPOINT("POST", "/api/ai/runners", startRunner,
             REQUEST(std::shared_ptr<IncomingRequest>, request)) {
        LOG_INFO("POST /api/ai/runners");
        auto bodyStr = request->readBodyToString();
        if (!m_aiState->enabled.load()) {
            auto json = oatpp::String("{\"status\":\"error\",\"error\":\"AI features are disabled\"}");
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
            return OutgoingResponse::createShared(Status::CODE_200, respBody);
        }
        try {
            auto reqJson = nlohmann::json::parse(sanitizeUtf8(bodyStr ? *bodyStr : ""));
            std::string modelName  = reqJson.value("model", "");
            std::string runnerName = reqJson.value("name", "");
            std::string runnerType = reqJson.value("type", "");
            if (modelName.empty()) {
                auto json = oatpp::String("{\"status\":\"error\",\"error\":\"model is required\"}");
                auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
                return OutgoingResponse::createShared(Status::CODE_200, respBody);
            }
            auto result = m_aiService->startRunner(modelName, runnerName, runnerType);
            nlohmann::json resp;
            if (result.success) {
                resp["status"] = "started";
                resp["name"]   = result.name;
            } else {
                resp["status"] = "error";
                resp["error"]  = result.error;
            }
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(
                oatpp::String(resp.dump()), "application/json");
            return OutgoingResponse::createShared(Status::CODE_200, respBody);
        } catch (const std::exception& e) {
            LOG_ERROR("POST /api/ai/runners parse error: {}", e.what());
            auto json = oatpp::String("{\"status\":\"error\",\"error\":\"parse error\"}");
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
            return OutgoingResponse::createShared(Status::CODE_200, respBody);
        }
    }

    // ── DELETE /api/ai/runners ────────────────────────────────────
    ENDPOINT("DELETE", "/api/ai/runners", deleteRunner,
             REQUEST(std::shared_ptr<IncomingRequest>, request)) {
        LOG_INFO("DELETE /api/ai/runners");
        auto bodyStr = request->readBodyToString();
        if (!m_aiState->enabled.load()) {
            auto response = ApiResponseDto::createShared();
            response->success = true;
            response->message = "AI features are disabled";
            return createDtoResponse(Status::CODE_200, response);
        }
        try {
            auto reqJson = nlohmann::json::parse(sanitizeUtf8(bodyStr ? *bodyStr : ""));
            std::string name = reqJson.value("name", "");
            bool ok;
            if (name.empty()) {
                ok = m_aiService->stopAllRunners();
            } else {
                ok = m_aiService->stopRunner(name);
            }
            auto response = ApiResponseDto::createShared();
            response->success = ok;
            response->message = ok ? "Runner stopped" : "Failed to stop runner";
            return createDtoResponse(Status::CODE_200, response);
        } catch (const std::exception& e) {
            LOG_ERROR("DELETE /api/ai/runners parse error: {}", e.what());
            auto response = ApiResponseDto::createShared();
            response->success = false;
            response->message = "parse error";
            return createDtoResponse(Status::CODE_500, response);
        }
    }

    // ── POST /api/ai/models/hf ────────────────────────────────────
    ENDPOINT("POST", "/api/ai/models/hf", searchHfModels,
             REQUEST(std::shared_ptr<IncomingRequest>, request)) {
        LOG_INFO("POST /api/ai/models/hf");
        (void)request;
        auto json = oatpp::String("[]");
        auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
        return OutgoingResponse::createShared(Status::CODE_200, respBody);
    }

    // ── POST /api/ai/models/check ─────────────────────────────────
    ENDPOINT("POST", "/api/ai/models/check", checkAiModel,
             REQUEST(std::shared_ptr<IncomingRequest>, request)) {
        LOG_INFO("POST /api/ai/models/check");
        if (auto err = _licGate()) return err;
        auto bodyStr = request->readBodyToString();
        if (!m_aiState->enabled.load()) {
            auto json = oatpp::String("{\"available\":false}");
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
            return OutgoingResponse::createShared(Status::CODE_200, respBody);
        }
        // Request cllama models, check if requested model exists
        auto cli = makeCli(m_config->cllamaPort);
        auto modelsRes = cli.Get("/v1/models");
        if (!modelsRes) {
            auto json = oatpp::String("{\"available\":false,\"error\":\"AI server unreachable\"}");
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
            return OutgoingResponse::createShared(Status::CODE_200, respBody);
        }
        try {
            auto reqJson = nlohmann::json::parse(sanitizeUtf8(bodyStr ? *bodyStr : ""));
            std::string repoId = reqJson.value("repo_id", "");
            auto modelsJson = nlohmann::json::parse(sanitizeUtf8(modelsRes->body));
            bool found = false;
            if (modelsJson.contains("data")) {
                for (const auto& m : modelsJson["data"]) {
                    if (m.value("id", "") == repoId) {
                        found = true;
                        break;
                    }
                }
            }
            nlohmann::json result;
            result["available"] = found;
            result["repo_id"] = repoId;
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(
                oatpp::String(result.dump()), "application/json");
            return OutgoingResponse::createShared(Status::CODE_200, respBody);
        } catch (...) {
            auto json = oatpp::String("{\"available\":false,\"error\":\"parse error\"}");
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
            return OutgoingResponse::createShared(Status::CODE_200, respBody);
        }
    }

    // ── POST /api/ai/models/download ──────────────────────────────
    ENDPOINT("POST", "/api/ai/models/download", downloadAiModel,
             REQUEST(std::shared_ptr<IncomingRequest>, request)) {
        LOG_INFO("POST /api/ai/models/download");
        if (auto err = _licGate()) return err;
        auto bodyStr = request->readBodyToString();
        if (!m_aiState->enabled.load()) {
            auto response = ApiResponseDto::createShared();
            response->success = true;
            response->message = "AI features are disabled";
            return createDtoResponse(Status::CODE_200, response);
        }
        // Forward to cllama POST /v1/pull
        auto cli = makeCli(m_config->cllamaPort);
        try {
            auto reqJson = nlohmann::json::parse(sanitizeUtf8(bodyStr ? *bodyStr : ""));
            std::string modelName = reqJson.value("repo_id", reqJson.value("name", ""));
            nlohmann::json pullReq;
            pullReq["model"] = modelName;
            auto res = cli.Post("/v1/pull", pullReq.dump(), "application/json");
            if (res && res->status == 200) {
                auto response = ApiResponseDto::createShared();
                response->success = true;
                response->message = oatpp::String("Download queued for " + modelName);
                return createDtoResponse(Status::CODE_200, response);
            }
        } catch (...) {}
        auto response = ApiResponseDto::createShared();
        response->success = false;
        response->message = "Failed to queue download";
        return createDtoResponse(Status::CODE_500, response);
    }

    // ── POST /api/ai/models/sync ──────────────────────────────────
    ENDPOINT("POST", "/api/ai/models/sync", syncAiModels) {
        LOG_INFO("POST /api/ai/models/sync");
        auto json = oatpp::String("{\"message\":\"Sync complete\",\"added\":0,\"already_present\":0,\"errors\":[]}");
        auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
        return OutgoingResponse::createShared(Status::CODE_200, respBody);
    }

    // ── DELETE /api/ai/models (body-based, matching Python API) ───
    ENDPOINT("DELETE", "/api/ai/models", deleteAiModelBody,
             REQUEST(std::shared_ptr<IncomingRequest>, request)) {
        LOG_INFO("DELETE /api/ai/models");
        auto bodyStr = request->readBodyToString();
        if (!m_aiState->enabled.load()) {
            auto json = oatpp::String("{\"message\":\"AI features are disabled\"}");
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
            return OutgoingResponse::createShared(Status::CODE_200, respBody);
        }
        try {
            auto reqJson = nlohmann::json::parse(sanitizeUtf8(bodyStr ? *bodyStr : ""));
            std::string name = reqJson.value("name", "");
            if (name.empty()) {
                auto json = oatpp::String("{\"message\":\"name is required\"}");
                auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
                return OutgoingResponse::createShared(Status::CODE_200, respBody);
            }
            bool ok = m_aiService->deleteModel(name);
            auto json = oatpp::String(
                ok ? (nlohmann::json{{"message","Successfully deleted " + name}}).dump()
                   : (nlohmann::json{{"message","Failed to delete " + name}}).dump());
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
            return OutgoingResponse::createShared(Status::CODE_200, respBody);
        } catch (const std::exception& e) {
            LOG_ERROR("DELETE /api/ai/models parse error: {}", e.what());
            auto json = oatpp::String("{\"message\":\"parse error\"}");
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
            return OutgoingResponse::createShared(Status::CODE_500, respBody);
        }
    }

    // ── DELETE /api/ai/models/{name} ──────────────────────────────
    ENDPOINT("DELETE", "/api/ai/models/{modelName}", deleteAiModel,
             PATH(String, modelName, "modelName")) {
        LOG_INFO("DELETE /api/ai/models/{}", modelName ? *modelName : "");
        std::string name = modelName ? *modelName : "";
        if (!m_aiState->enabled.load() || name.empty()) {
            auto response = ApiResponseDto::createShared();
            response->success = false;
            response->message = name.empty() ? "model name is required" : "AI features are disabled";
            return createDtoResponse(Status::CODE_200, response);
        }
        bool ok = m_aiService->deleteModel(name);
        auto response = ApiResponseDto::createShared();
        response->success = ok;
        response->message = ok ? "Model removal requested" : "Failed to delete model";
        return createDtoResponse(Status::CODE_200, response);
    }

    // ── POST /api/ai/chat ─────────────────────────────────────────
    ENDPOINT("POST", "/api/ai/chat", chat,
             REQUEST(std::shared_ptr<IncomingRequest>, request)) {
        LOG_INFO("POST /api/ai/chat");
        if (auto err = _licGate()) return err;
        auto bodyStr = request->readBodyToString();
        if (!m_aiState->enabled.load()) {
            auto json = oatpp::String("{\"text\":\"AI assistant is disabled.\"}");
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
            return OutgoingResponse::createShared(Status::CODE_200, respBody);
        }
        try {
            std::string raw = bodyStr ? *bodyStr : "";
            auto reqJson = nlohmann::json::parse(sanitizeUtf8(raw));
            std::string text = reqJson.value("text", "");
            nlohmann::json cllamaReq;
            cllamaReq["model"] = reqJson.value("model", m_aiService->getFeatureModel("chat"));

            if (reqJson.contains("messages") && reqJson["messages"].is_array() && !reqJson["messages"].empty()) {
                cllamaReq["messages"] = reqJson["messages"];
            } else {
                cllamaReq["messages"] = nlohmann::json::array();
                nlohmann::json msg;
                msg["role"] = "user";
                msg["content"] = text;
                cllamaReq["messages"].push_back(msg);
            }

            attachFilesToRequest(reqJson, cllamaReq, m_config->storageRoot);
            cllamaReq["max_tokens"] = reqJson.value("max_tokens", 512);
            cllamaReq["stream"] = false;

            auto respBodyStr = m_aiService->chatCompletions(cllamaReq.dump());
            auto respJson = nlohmann::json::parse(sanitizeUtf8(respBodyStr));
            if (respJson.contains("error")) {
                auto json = oatpp::String(respBodyStr);
                auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
                return OutgoingResponse::createShared(Status::CODE_200, respBody);
            }
            std::string content;
            if (respJson.contains("choices") && !respJson["choices"].empty()) {
                content = respJson["choices"][0]["message"]["content"];
            }
            nlohmann::json result;
            result["text"] = content;
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(
                oatpp::String(result.dump()), "application/json");
            return OutgoingResponse::createShared(Status::CODE_200, respBody);
        } catch (const std::exception& e) {
            LOG_ERROR("Chat proxy error: {}", e.what());
        }
        auto json = oatpp::String("{\"text\":\"AI request failed.\"}");
        auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
        return OutgoingResponse::createShared(Status::CODE_200, respBody);
    }

    // ── POST /api/ai/chat/stream ──────────────────────────────────
    ENDPOINT("POST", "/api/ai/chat/stream", chatStream,
             REQUEST(std::shared_ptr<IncomingRequest>, request)) {
        LOG_INFO("POST /api/ai/chat/stream");
        if (auto err = _licGate()) return err;
        if (!m_aiState->enabled.load()) {
            auto response = oatpp::web::protocol::http::outgoing::Response::createShared(
                Status::CODE_200,
                oatpp::web::protocol::http::outgoing::BufferBody::createShared(
                    oatpp::String("AI assistant is disabled."),
                    oatpp::String("text/plain")));
            return response;
        }
        auto bodyStr = request->readBodyToString();
        try {
            std::string raw = bodyStr ? *bodyStr : "";
            auto reqJson = nlohmann::json::parse(sanitizeUtf8(raw));
            std::string text = reqJson.value("text", "");
            nlohmann::json cllamaReq;
            cllamaReq["model"] = reqJson.value("model", m_aiService->getFeatureModel("chat"));

            if (reqJson.contains("messages") && reqJson["messages"].is_array() && !reqJson["messages"].empty()) {
                cllamaReq["messages"] = reqJson["messages"];
            } else {
                cllamaReq["messages"] = nlohmann::json::array();
                nlohmann::json msg;
                msg["role"] = "user";
                msg["content"] = text;
                cllamaReq["messages"].push_back(msg);
            }

            attachFilesToRequest(reqJson, cllamaReq, m_config->storageRoot);
            cllamaReq["max_tokens"] = reqJson.value("max_tokens", 512);
            cllamaReq["stream"] = true;

            auto cb = std::make_shared<SseProxyCallback>(cllamaReq.dump(), m_config->cllamaPort);
            auto body = std::make_shared<oatpp::web::protocol::http::outgoing::StreamingBody>(cb);
            auto response = OutgoingResponse::createShared(Status::CODE_200, body);
            response->putHeader("Content-Type", "text/plain; charset=utf-8");
            response->putHeader("Cache-Control", "no-cache");
            return response;
        } catch (const std::exception& e) {
            LOG_ERROR("Stream proxy error: {}", e.what());
        }
        auto response = oatpp::web::protocol::http::outgoing::Response::createShared(
            Status::CODE_200,
            oatpp::web::protocol::http::outgoing::BufferBody::createShared(
                oatpp::String("AI request failed."), oatpp::String("text/plain")));
        return response;
    }

    // ── POST /api/ai/completions ───────────────────────────────────
    ENDPOINT("POST", "/api/ai/completions", completions,
             REQUEST(std::shared_ptr<IncomingRequest>, request)) {
        LOG_INFO("POST /api/ai/completions");
        if (auto err = _licGate()) return err;
        auto bodyStr = request->readBodyToString();
        if (!m_aiState->enabled.load()) {
            auto json = oatpp::String("{\"error\":\"AI features are disabled\"}");
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
            return OutgoingResponse::createShared(Status::CODE_200, respBody);
        }
        auto respBodyStr = m_aiService->completions(bodyStr ? *bodyStr : "{}");
        auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(
            oatpp::String(respBodyStr), "application/json");
        return OutgoingResponse::createShared(Status::CODE_200, respBody);
    }

    // ── POST /api/ai/chat/cancel/{requestId} ──────────────────────
    ENDPOINT("POST", "/api/ai/chat/cancel/{requestId}", cancelChat,
             PATH(String, requestId, "requestId")) {
        auto rid = requestId ? *requestId : "";
        LOG_INFO("POST /api/ai/chat/cancel/{}", rid);
        if (auto err = _licGate()) return err;
        if (!m_aiState->enabled.load()) {
            auto json = oatpp::String("{\"message\":\"AI Engine not enabled\"}");
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
            return OutgoingResponse::createShared(Status::CODE_400, respBody);
        }
        auto json = oatpp::String((nlohmann::json{{"message","Cancellation requested for AI request " + rid}}).dump());
        auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
        return OutgoingResponse::createShared(Status::CODE_200, respBody);
    }

    // ── GET /api/ai/rag ───────────────────────────────────────────
    ENDPOINT("GET", "/api/ai/rag", getRagStatus) {
        LOG_INFO("GET /api/ai/rag");
        if (auto err = _licGate()) return err;
        auto response = RagStatusDto::createShared();
        response->status = "disconnected";
        response->address = "";
        response->index = "";
        response->usage_docs = 0;
        return createDtoResponse(Status::CODE_200, response);
    }

    // ── GET /api/ai/rag/documents ─────────────────────────────────
    ENDPOINT("GET", "/api/ai/rag/documents", getRagDocuments) {
        LOG_INFO("GET /api/ai/rag/documents");
        if (auto err = _licGate()) return err;
        auto json = oatpp::String("{\"files\":[],\"total\":0}");
        auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
        return OutgoingResponse::createShared(Status::CODE_200, respBody);
    }

    // ── DELETE /api/ai/rag ────────────────────────────────────────
    ENDPOINT("DELETE", "/api/ai/rag", resetRag) {
        LOG_INFO("DELETE /api/ai/rag");
        if (auto err = _licGate()) return err;
        auto json = oatpp::String("{\"deleted\":0,\"message\":\"RAG index cleared successfully.\"}");
        auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
        return OutgoingResponse::createShared(Status::CODE_200, respBody);
    }

    // ── DELETE /api/ai/rag/documents ──────────────────────────────
    ENDPOINT("DELETE", "/api/ai/rag/documents", deleteRagDocument,
             QUERY(String, path, "path")) {
        LOG_INFO("DELETE /api/ai/rag/documents");
        if (auto err = _licGate()) return err;
        auto docPath = path ? *path : "";
        if (docPath.empty()) {
            auto json = oatpp::String("{\"message\":\"path parameter is required\"}");
            auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
            return OutgoingResponse::createShared(Status::CODE_400, respBody);
        }
        auto json = oatpp::String(
            (nlohmann::json{{"deleted",0},{"message","Document '" + docPath + "' deleted."}}).dump());
        auto respBody = oatpp::web::protocol::http::outgoing::BufferBody::createShared(json, "application/json");
        return OutgoingResponse::createShared(Status::CODE_200, respBody);
    }
};

} // namespace ainas

#include OATPP_CODEGEN_END(ApiController)
