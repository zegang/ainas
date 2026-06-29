#pragma once

#include "ainas/database/Database.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace ainas {

class FileRepository {
public:
    struct Record {
        int64_t id{0};
        std::string name;
        std::string path;        // relative, e.g. "/" or "/dir/file.txt"
        int64_t size{0};
        bool isDirectory{false};
        int64_t createdAt{0};
        int64_t updatedAt{0};
        std::optional<int64_t> parentId;
        std::vector<std::string> tags;
    };

    explicit FileRepository(Database& db);

    void migrate();

    std::optional<Record> findById(int64_t id);
    std::optional<Record> findByPath(const std::string& path);
    std::vector<Record> findByParentId(std::optional<int64_t> parentId);
    std::vector<Record> searchByName(const std::string& query);

    int64_t insert(const Record& record);
    void update(const Record& record);
    bool deleteById(int64_t id);
    bool deleteByPath(const std::string& path);
    int64_t deleteByParentId(int64_t parentId);

    void setTags(int64_t fileId, const std::vector<std::string>& tags);
    std::vector<std::string> getTags(int64_t fileId);

    int64_t countChildren(int64_t parentId);

private:
    Database& m_db;

    Record rowToRecord(Database::Statement& stmt) const;
    void loadTags(Record& record) const;
};

} // namespace ainas
