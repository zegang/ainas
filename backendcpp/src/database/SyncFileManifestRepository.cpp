#include "ainas/database/SyncFileManifestRepository.hpp"

namespace ainas {

SyncFileManifestRepository::SyncFileManifestRepository(Database& db)
    : m_db(db)
{}

void SyncFileManifestRepository::migrate() {
    auto& db = m_db;

    db.execute(R"(
        CREATE TABLE IF NOT EXISTS sync_file_manifest (
            id                INTEGER PRIMARY KEY AUTOINCREMENT,
            sync_config_id    INTEGER NOT NULL,
            relative_path     TEXT    NOT NULL,
            file_size         INTEGER NOT NULL DEFAULT 0,
            modified_at       TEXT    NOT NULL DEFAULT '',
            synced_at         TEXT    NOT NULL DEFAULT (datetime('now')),
            FOREIGN KEY (sync_config_id) REFERENCES sync_configs(id) ON DELETE CASCADE
        )
    )");

    db.execute(R"(
        CREATE INDEX IF NOT EXISTS idx_manifest_config_path
            ON sync_file_manifest(sync_config_id, relative_path)
    )");

    {
        auto stmt = Database::Statement(db,
            "INSERT OR IGNORE INTO schema_version (version) VALUES (10)");
        stmt.step();
    }
}

SyncFileManifestRepository::Entry SyncFileManifestRepository::rowToEntry(
    Database::Statement& stmt) const
{
    Entry e;
    e.id = stmt.columnInt64(0);
    e.syncConfigId = stmt.columnInt64(1);
    e.relativePath = stmt.columnText(2);
    e.fileSize = stmt.columnInt64(3);
    if (!stmt.columnNull(4)) {
        e.modifiedAt = stmt.columnText(4);
    }
    if (!stmt.columnNull(5)) {
        e.syncedAt = stmt.columnText(5);
    }
    return e;
}

std::vector<SyncFileManifestRepository::Entry>
SyncFileManifestRepository::findByConfigId(int64_t configId) {
    std::vector<Entry> entries;
    auto stmt = Database::Statement(m_db,
        "SELECT id, sync_config_id, relative_path, file_size, modified_at, synced_at "
        "FROM sync_file_manifest WHERE sync_config_id = ? ORDER BY relative_path");
    stmt.bind(1, configId);

    while (stmt.step()) {
        entries.push_back(rowToEntry(stmt));
    }
    return entries;
}

std::optional<SyncFileManifestRepository::Entry>
SyncFileManifestRepository::findByConfigIdAndPath(int64_t configId, const std::string& path) {
    auto stmt = Database::Statement(m_db,
        "SELECT id, sync_config_id, relative_path, file_size, modified_at, synced_at "
        "FROM sync_file_manifest WHERE sync_config_id = ? AND relative_path = ?");
    stmt.bind(1, configId);
    stmt.bind(2, path);

    if (stmt.step()) {
        return rowToEntry(stmt);
    }
    return std::nullopt;
}

int64_t SyncFileManifestRepository::upsert(const Entry& entry) {
    auto existing = findByConfigIdAndPath(entry.syncConfigId, entry.relativePath);
    if (existing) {
        auto stmt = Database::Statement(m_db,
            "UPDATE sync_file_manifest SET "
            "file_size = ?, modified_at = ?, synced_at = datetime('now') "
            "WHERE id = ?");
        stmt.bind(1, entry.fileSize);
        stmt.bind(2, entry.modifiedAt);
        stmt.bind(3, existing->id);
        stmt.step();
        return existing->id;
    }
    return insert(entry);
}

int64_t SyncFileManifestRepository::insert(const Entry& entry) {
    auto stmt = Database::Statement(m_db,
        "INSERT INTO sync_file_manifest "
        "(sync_config_id, relative_path, file_size, modified_at, synced_at) "
        "VALUES (?, ?, ?, ?, datetime('now'))");
    stmt.bind(1, entry.syncConfigId);
    stmt.bind(2, entry.relativePath);
    stmt.bind(3, entry.fileSize);
    stmt.bind(4, entry.modifiedAt);
    stmt.step();

    return m_db.lastInsertRowId();
}

void SyncFileManifestRepository::deleteByConfigId(int64_t configId) {
    auto stmt = Database::Statement(m_db,
        "DELETE FROM sync_file_manifest WHERE sync_config_id = ?");
    stmt.bind(1, configId);
    stmt.step();
}

void SyncFileManifestRepository::deleteByPath(int64_t configId, const std::string& path) {
    auto stmt = Database::Statement(m_db,
        "DELETE FROM sync_file_manifest WHERE sync_config_id = ? AND relative_path = ?");
    stmt.bind(1, configId);
    stmt.bind(2, path);
    stmt.step();
}

} // namespace ainas
