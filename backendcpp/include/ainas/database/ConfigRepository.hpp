#pragma once

#include "ainas/database/Database.hpp"

#include <optional>
#include <string>
#include <vector>

namespace ainas {

class ConfigRepository {
public:
    struct Entry {
        std::string key;
        std::string value;
    };

    explicit ConfigRepository(Database& db);

    void migrate();

    std::optional<Entry> get(const std::string& key);
    std::vector<Entry> getAll();
    void set(const std::string& key, const std::string& value);
    bool remove(const std::string& key);

private:
    Database& m_db;
};

} // namespace ainas
