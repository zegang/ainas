#include "ainas/database/ConfigRepository.hpp"

namespace ainas {

ConfigRepository::ConfigRepository(Database& db)
    : m_db(db)
{}

void ConfigRepository::migrate() {
    m_db.execute(R"(
        CREATE TABLE IF NOT EXISTS app_config (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )
    )");
}

std::optional<ConfigRepository::Entry>
ConfigRepository::get(const std::string& key) {
    auto stmt = Database::Statement(m_db,
        "SELECT key, value FROM app_config WHERE key = ?");
    stmt.bind(1, key);

    if (stmt.step()) {
        return Entry{stmt.columnText(0), stmt.columnText(1)};
    }
    return std::nullopt;
}

std::vector<ConfigRepository::Entry>
ConfigRepository::getAll() {
    std::vector<Entry> entries;
    auto stmt = Database::Statement(m_db,
        "SELECT key, value FROM app_config ORDER BY key");

    while (stmt.step()) {
        entries.push_back({stmt.columnText(0), stmt.columnText(1)});
    }
    return entries;
}

void ConfigRepository::set(const std::string& key,
                            const std::string& value) {
    auto stmt = Database::Statement(m_db,
        "INSERT OR REPLACE INTO app_config (key, value) VALUES (?, ?)");
    stmt.bind(1, key);
    stmt.bind(2, value);
    stmt.step();
}

bool ConfigRepository::remove(const std::string& key) {
    auto stmt = Database::Statement(m_db,
        "DELETE FROM app_config WHERE key = ?");
    stmt.bind(1, key);
    stmt.step();
    return m_db.lastInsertRowId() > 0;
}

} // namespace ainas
