#pragma once

#include "ainas/database/Database.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace ainas {

class SyncConfigRepository {
public:
    struct Entry {
        int64_t id{0};
        std::string name;
        std::string sourcePath;
        std::string targetPath;
        int64_t syncIntervalSecs{0};
        std::string syncPolicy{"interval"};
        std::string syncTime;
        std::string lastSyncedAt;
        bool enabled{true};
        bool deleteAfterSync{false};
        std::string createdAt;
        std::string updatedAt;
    };

    explicit SyncConfigRepository(Database& db);

    void migrate();

    std::vector<Entry> findAll();
    std::optional<Entry> findById(int64_t id);
    std::vector<Entry> findByTargetPath(const std::string& targetPath);
    int64_t insert(const Entry& entry);
    void update(const Entry& entry);
    bool deleteById(int64_t id);
    void updateLastSyncedAt(int64_t id);

private:
    Database& m_db;
    Entry rowToEntry(Database::Statement& stmt) const;
};

} // namespace ainas
