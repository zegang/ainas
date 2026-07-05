#pragma once

#include "ainas/config/Config.hpp"

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace ainas {

struct FeatureInfo {
    std::string name;
    std::string functionality;
    std::string featureTitle;
    std::string featureDescription;
};

struct FeatureState {
    std::string name;
    std::string modelName;
    std::string status; // "loading" | "ready" | "error" | "unknown"
    std::string error;
};

struct AiState {
    std::atomic<bool> enabled{false};
    std::atomic<bool> ready{false};
    std::string status{"disabled"};
    int pid{-1};
    int port{0};
    std::string binary;
    std::string modelsFolder;
    double startedAt{0};
    std::vector<FeatureInfo> features;
    std::unordered_map<std::string, FeatureState> featureStates;
    std::mutex featureMutex;
};

struct StartRunnerResult {
    bool success{false};
    std::string name;
    std::string error;
};

class AiService {
public:
    explicit AiService(std::shared_ptr<Config> config);

    ~AiService();

    bool start();
    void stop();
    bool isAlive() const;
    int availableModels() const;
    std::string listModels() const;
    std::string showModel(const std::string& name) const;
    bool deleteModel(const std::string& name) const;
    StartRunnerResult startRunner(const std::string& modelName,
                                  const std::string& runnerName = "",
                                  const std::string& runnerType = "");
    std::string listRunners() const;
    bool stopRunner(const std::string& name);
    bool stopAllRunners();
    std::string chatCompletions(const std::string& jsonBody) const;
    std::string completions(const std::string& jsonBody) const;
    std::string getStatus() const;
    std::string listFeatures() const;
    std::shared_ptr<AiState> state() const { return m_aiState; }

    std::string getFeatureModel(const std::string& name) const;

    void updateFeatureState(const std::string& name, const std::string& modelName,
                            const std::string& status, const std::string& error = "");
    void initFeatures();

private:
    std::shared_ptr<Config> m_config;
    std::shared_ptr<AiState> m_aiState;

    bool spawnCllama();
    bool waitForReady(int timeoutSeconds);
    void terminate();
};

} // namespace ainas
