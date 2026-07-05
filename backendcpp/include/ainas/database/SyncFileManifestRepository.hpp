#pragma once

#include "ainas/database/Database.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace ainas {

class SyncFileManifestRepository {
public:
    struct Entry {
        int64_t id{0};
        int64_t syncConfigId{0};
        std::string relativePath;
        int64_t fileSize{0};
        std::string modifiedAt;
        std::string syncedAt;
    };

    explicit SyncFileManifestRepository(Database& db);

    void migrate();

    std::vector<Entry> findByConfigId(int64_t configId);
    std::optional<Entry> findByConfigIdAndPath(int64_t configId, const std::string& path);
    int64_t upsert(const Entry& entry);
    int64_t insert(const Entry& entry);
    void deleteByConfigId(int64_t configId);
    void deleteByPath(int64_t configId, const std::string& path);

private:
    Database& m_db;
    Entry rowToEntry(Database::Statement& stmt) const;
};

} // namespace ainas
