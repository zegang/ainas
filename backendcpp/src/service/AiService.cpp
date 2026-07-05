#include "ainas/service/AiService.hpp"
#include "ainas/logging/Logger.hpp"
#include "ainas/platform/Platform.hpp"

#include <httplib.h>
#include <nlohmann/json.hpp>

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <sstream>
#include <thread>

namespace ainas {

AiService::AiService(std::shared_ptr<Config> config)
    : m_config(std::move(config))
    , m_aiState(std::make_shared<AiState>())
{
    // Resolve cllama binary relative to own location.
    // Config default is "bin/cllama", so this becomes <backend-dir>/bin/cllama.
    auto& binary = m_config->cllamaBinary;
    if (binary.is_relative()) {
        auto selfExe = ainas::platform::executablePath();
        if (!selfExe.empty()) {
            auto selfDir = std::filesystem::path(selfExe).parent_path();
            binary = selfDir / binary;
        }
    }
    LOG_INFO("Cllama binary resolved to: {}", binary.string());
}

AiService::~AiService() {
    stop();
}

void AiService::initFeatures() {
    static const std::vector<FeatureInfo> kFeatures = {
        {"chat",      "chat",      "Chat",     "Conversational AI assistant"},
        {"vision",    "vision",    "Vision",   "Image analysis and understanding"},
        {"embedding", "embedding", "Embedding","Text embedding and vectorization"},
    };

    std::lock_guard<std::mutex> lock(m_aiState->featureMutex);
    m_aiState->features = kFeatures;
    for (const auto& f : kFeatures) {
        FeatureState fs;
        fs.name  = f.name;
        fs.modelName = "";
        fs.status = "unknown";
        fs.error  = "";
        m_aiState->featureStates[f.name] = fs;
    }
}

void AiService::updateFeatureState(const std::string& name, const std::string& modelName,
                                    const std::string& status, const std::string& error) {
    std::lock_guard<std::mutex> lock(m_aiState->featureMutex);
    auto it = m_aiState->featureStates.find(name);
    if (it != m_aiState->featureStates.end()) {
        it->second.modelName = modelName;
        it->second.status = status;
        it->second.error = error;
    }
}

bool AiService::start() {
    if (!m_config->aiEnabled) {
        m_aiState->enabled = false;
        m_aiState->status = "disabled";
        return true;
    }

    m_aiState->enabled = true;
    m_aiState->status = "initializing";
    m_aiState->port = m_config->cllamaPort;
    m_aiState->binary = m_config->cllamaBinary.string();
    m_aiState->modelsFolder = m_config->cllamaModelsFolder.string();

    initFeatures();
    m_aiState->startedAt = static_cast<double>(std::time(nullptr));

    std::error_code ec;
    std::filesystem::create_directories(m_config->cllamaModelsFolder, ec);

    if (!spawnCllama()) {
        m_aiState->status = "error";
        LOG_ERROR("Failed to spawn cllama server");
        return false;
    }

    if (waitForReady(60)) {
        m_aiState->ready = true;
        m_aiState->status = "ready";

        // Mark features as ready with current model
        std::string modelName = "";
        {
            auto modelsJson = nlohmann::json::parse(listModels());
            if (modelsJson.contains("models") && !modelsJson["models"].empty()) {
                modelName = modelsJson["models"][0].value("id", "");
            }
        }
        updateFeatureState("chat",      modelName, "ready", "");
        updateFeatureState("vision",    modelName, "ready", "");
        updateFeatureState("embedding", modelName, "ready", "");

        LOG_INFO("Cllama server is ready on port {}", m_config->cllamaPort);
        return true;
    }

    m_aiState->status = "error";
    LOG_ERROR("Cllama server failed to start within 60 seconds");
    terminate();
    return false;
}

bool AiService::isAlive() const {
    httplib::Client cli("127.0.0.1", m_config->cllamaPort);
    cli.set_connection_timeout(2);
    cli.set_read_timeout(2);
    auto res = cli.Get("/v1/models");
    return res && res->status == 200;
}

int AiService::availableModels() const {
    httplib::Client cli("127.0.0.1", m_config->cllamaPort);
    cli.set_connection_timeout(2);
    cli.set_read_timeout(2);
    auto res = cli.Get("/v1/models");
    if (!res || res->status != 200) return 0;
    try {
        auto j = nlohmann::json::parse(res->body);
        if (j.contains("data")) return static_cast<int>(j["data"].size());
    } catch (...) {}
    return 0;
}

std::string AiService::listModels() const {
    httplib::Client cli("127.0.0.1", m_config->cllamaPort);
    cli.set_connection_timeout(2);
    cli.set_read_timeout(2);
    auto res = cli.Get("/v1/models");
    if (!res || res->status != 200) {
        nlohmann::json err;
        err["models"] = nlohmann::json::array();
        err["error"] = "AI server unreachable";
        return err.dump();
    }
    // Translate OpenAI format {object,data} → frontend {models}
    try {
        auto j = nlohmann::json::parse(res->body);
        nlohmann::json out;
        out["models"] = nlohmann::json::array();
        if (j.contains("data")) {
            for (const auto& m : j["data"]) {
                nlohmann::json item;
                item["id"] = m.value("id", "");
                item["name"] = m.value("id", "");
                item["object"] = m.value("object", "model");
                item["is_ready"] = true;
                item["is_local"] = true;
                auto created = m.value("created", 0);
                if (created > 0) {
                    std::time_t t = static_cast<std::time_t>(created);
                    std::ostringstream ss;
                    ss << std::put_time(std::gmtime(&t), "%Y-%m-%dT%H:%M:%SZ");
                    item["downloaded_at"] = ss.str();
                }
                out["models"].push_back(item);
            }
        }
        return out.dump();
    } catch (const std::exception& e) {
        nlohmann::json err;
        err["models"] = nlohmann::json::array();
        err["error"] = std::string("parse error: ") + e.what();
        return err.dump();
    }
}

std::string AiService::showModel(const std::string& name) const {
    httplib::Client cli("127.0.0.1", m_config->cllamaPort);
    cli.set_connection_timeout(2);
    cli.set_read_timeout(2);
    auto res = cli.Get("/v1/models");
    if (!res || res->status != 200) {
        nlohmann::json err;
        err["error"] = "AI server unreachable";
        return err.dump();
    }
    try {
        auto j = nlohmann::json::parse(res->body);
        if (j.contains("data")) {
            for (const auto& m : j["data"]) {
                if (m.value("id", "") == name) {
                    return m.dump();
                }
            }
        }
        nlohmann::json notFound;
        notFound["error"] = "model not found";
        notFound["id"] = name;
        return notFound.dump();
    } catch (const std::exception& e) {
        nlohmann::json err;
        err["error"] = std::string("parse error: ") + e.what();
        return err.dump();
    }
}

bool AiService::deleteModel(const std::string& name) const {
    httplib::Client cli("127.0.0.1", m_config->cllamaPort);
    cli.set_connection_timeout(2);
    cli.set_read_timeout(2);
    nlohmann::json body;
    body["model"] = name;
    auto res = cli.Post("/v1/delete", body.dump(), "application/json");
    return res && res->status == 200;
}

StartRunnerResult AiService::startRunner(const std::string& modelName,
                                        const std::string& runnerName,
                                        const std::string& runnerType) {
    httplib::Client cli("127.0.0.1", m_config->cllamaPort);
    cli.set_connection_timeout(5);
    cli.set_read_timeout(10);

    nlohmann::json body;
    body["name"]   = runnerName.empty() ? modelName : runnerName;
    body["binary"] = m_config->cllamaBinary.string();
    body["model"]  = modelName;
    if (!runnerType.empty())
        body["type"] = runnerType;

    auto res = cli.Post("/v1/run", body.dump(), "application/json");
    if (!res) {
        return {false, "", "Failed to connect to AI server"};
    }
    try {
        auto j = nlohmann::json::parse(res->body);
        if (j.value("status", "") == "error") {
            return {false, "", j.value("error", "unknown error")};
        }
        return {true, j.value("name", body["name"]), ""};
    } catch (const std::exception& e) {
        return {false, "", std::string("parse error: ") + e.what()};
    }
}

std::string AiService::listRunners() const {
    httplib::Client cli("127.0.0.1", m_config->cllamaPort);
    cli.set_connection_timeout(2);
    cli.set_read_timeout(2);
    auto res = cli.Get("/v1/runners");
    if (!res || res->status != 200) {
        nlohmann::json err;
        err["object"] = "list";
        err["data"] = nlohmann::json::array();
        err["error"] = "AI server unreachable";
        return err.dump();
    }
    return res->body;
}

bool AiService::stopRunner(const std::string& name) {
    httplib::Client cli("127.0.0.1", m_config->cllamaPort);
    cli.set_connection_timeout(2);
    cli.set_read_timeout(2);
    nlohmann::json body;
    body["name"] = name;
    auto res = cli.Post("/v1/stop", body.dump(), "application/json");
    return res && res->status == 200;
}

bool AiService::stopAllRunners() {
    httplib::Client cli("127.0.0.1", m_config->cllamaPort);
    cli.set_connection_timeout(2);
    cli.set_read_timeout(5);
    auto res = cli.Post("/v1/stop-all", "{}", "application/json");
    return res && res->status == 200;
}

std::string AiService::chatCompletions(const std::string& jsonBody) const {
    httplib::Client cli("127.0.0.1", m_config->cllamaPort);
    cli.set_connection_timeout(5);
    cli.set_read_timeout(120);
    auto res = cli.Post("/v1/chat/completions", jsonBody, "application/json");
    if (!res) {
        nlohmann::json err;
        err["error"] = "AI server unreachable";
        return err.dump();
    }
    return res->body;
}

std::string AiService::completions(const std::string& jsonBody) const {
    httplib::Client cli("127.0.0.1", m_config->cllamaPort);
    cli.set_connection_timeout(5);
    cli.set_read_timeout(120);
    auto res = cli.Post("/v1/completions", jsonBody, "application/json");
    if (!res) {
        nlohmann::json err;
        err["error"] = "AI server unreachable";
        return err.dump();
    }
    return res->body;
}

std::string AiService::getStatus() const {
    nlohmann::json j;
    j["pid"] = m_aiState->pid;
    j["port"] = m_aiState->port;
    j["binary"] = m_aiState->binary;
    j["models_folder"] = m_aiState->modelsFolder;
    j["models_available"] = 0;
    j["elapsed"] = m_aiState->startedAt > 0
        ? static_cast<double>(std::time(nullptr)) - m_aiState->startedAt
        : 0.0;

    if (!m_aiState->enabled.load()) {
        j["status"] = "disabled";
        j["error"] = "AI features are disabled";
    } else if (!isAlive()) {
        j["status"] = "error";
        j["error"] = "AI server is not responding";
    } else {
        j["status"] = m_aiState->ready ? "ready" : "initializing";
        j["models_available"] = availableModels();
    }

    // Build features list enriched with current state (mirrors Python AIStatus.sync_features_list)
    {
        std::lock_guard<std::mutex> lock(m_aiState->featureMutex);
        nlohmann::json features = nlohmann::json::array();
        for (const auto& fi : m_aiState->features) {
            nlohmann::json f;
            f["name"] = fi.name;
            f["functionality"] = fi.functionality;
            f["feature_title"] = fi.featureTitle;
            f["feature_description"] = fi.featureDescription;

            auto it = m_aiState->featureStates.find(fi.name);
            if (it != m_aiState->featureStates.end()) {
                f["model_name"] = it->second.modelName;
                f["status"] = it->second.status;
                if (!it->second.error.empty()) {
                    f["error"] = it->second.error;
                }
            } else {
                f["model_name"] = "";
                f["status"] = "unknown";
            }
            features.push_back(f);
        }
        j["features"] = features;

        nlohmann::json states = nlohmann::json::array();
        for (const auto& [_, fs] : m_aiState->featureStates) {
            nlohmann::json s;
            s["name"] = fs.name;
            s["model_name"] = fs.modelName;
            s["status"] = fs.status;
            if (!fs.error.empty()) s["error"] = fs.error;
            states.push_back(s);
        }
        j["feature_states"] = states;
    }

    return j.dump();
}

std::string AiService::listFeatures() const {
    nlohmann::json j;
    nlohmann::json features = nlohmann::json::array();
    {
        std::lock_guard<std::mutex> lock(m_aiState->featureMutex);
        for (const auto& fi : m_aiState->features) {
            nlohmann::json f;
            f["name"] = fi.name;
            f["functionality"] = fi.functionality;
            f["feature_title"] = fi.featureTitle;
            f["feature_description"] = fi.featureDescription;
            auto it = m_aiState->featureStates.find(fi.name);
            f["model_name"] = (it != m_aiState->featureStates.end()) ? it->second.modelName : "";
            features.push_back(f);
        }
    }
    j["features"] = features;
    return j.dump();
}

std::string AiService::getFeatureModel(const std::string& name) const {
    std::lock_guard<std::mutex> lock(m_aiState->featureMutex);
    auto it = m_aiState->featureStates.find(name);
    return (it != m_aiState->featureStates.end()) ? it->second.modelName : "";
}

void AiService::stop() {
    if (m_aiState->enabled.load()) {
        terminate();
    }
    m_aiState->enabled = false;
    m_aiState->ready = false;
    m_aiState->status = "disabled";
}

bool AiService::spawnCllama() {
    std::string portStr = std::to_string(m_config->cllamaPort);
    std::string modelsFolder = m_config->cllamaModelsFolder.string();
    std::string binary = m_config->cllamaBinary.string();

    std::vector<std::string> args = {
        "serve", "start",
        "--port", portStr,
        "--models-folder", modelsFolder
    };

    ainas::platform::Pid pid = 0;
    if (!ainas::platform::spawnProcess(binary, args, pid)) {
        LOG_ERROR("Failed to spawn cllama server");
        return false;
    }

    m_aiState->pid = static_cast<int>(pid);
    LOG_INFO("Spawned cllama server (PID {}) from binary: {}", pid, binary);
    return true;
}

bool AiService::waitForReady(int timeoutSeconds) {
    httplib::Client cli("127.0.0.1", m_config->cllamaPort);
    cli.set_connection_timeout(1);
    cli.set_read_timeout(2);

    auto start = std::chrono::steady_clock::now();
    while (true) {
        auto res = cli.Get("/v1/models");
        if (res && res->status == 200) return true;
        auto elapsed = std::chrono::steady_clock::now() - start;
        if (elapsed > std::chrono::seconds(timeoutSeconds)) return false;
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
    }
}

void AiService::terminate() {
    ainas::platform::Pid pid = static_cast<ainas::platform::Pid>(m_aiState->pid);
    if (pid == 0) return;
    LOG_INFO("Stopping cllama server (PID {})...", m_aiState->pid);

    if (!ainas::platform::killProcess(pid)) {
        LOG_WARN("Cllama server (PID {}) may already be stopped", m_aiState->pid);
    }
    m_aiState->pid = -1;
}

} // namespace ainas
