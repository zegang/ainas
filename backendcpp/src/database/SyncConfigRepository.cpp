#include "ainas/database/SyncConfigRepository.hpp"

#include <sqlite3.h>

namespace ainas {

SyncConfigRepository::SyncConfigRepository(Database& db)
    : m_db(db)
{}

void SyncConfigRepository::migrate() {
    auto& db = m_db;

    db.execute(R"(
        CREATE TABLE IF NOT EXISTS schema_version (
            version INTEGER PRIMARY KEY
        )
    )");

    int version = 0;
    {
        auto stmt = Database::Statement(db,
            "SELECT COALESCE(MAX(version), 0) FROM schema_version");
        if (stmt.step()) {
            version = static_cast<int>(stmt.columnInt64(0));
        }
    }

    if (version < 2) {
        db.execute(R"(
            CREATE TABLE IF NOT EXISTS sync_configs (
                id                 INTEGER PRIMARY KEY AUTOINCREMENT,
                name               TEXT    NOT NULL,
                source_path        TEXT    NOT NULL,
                target_path        TEXT    NOT NULL,
                sync_interval_secs INTEGER NOT NULL DEFAULT 0,
                last_synced_at     TEXT,
                enabled            INTEGER NOT NULL DEFAULT 1,
                delete_after_sync  INTEGER NOT NULL DEFAULT 0,
                created_at         TEXT    NOT NULL DEFAULT (datetime('now')),
                updated_at         TEXT    NOT NULL DEFAULT (datetime('now'))
            )
        )");

        db.execute(R"(
            CREATE INDEX IF NOT EXISTS idx_sync_configs_name
                ON sync_configs(name)
        )");

        {
            auto stmt = Database::Statement(db,
                "INSERT INTO schema_version (version) VALUES (2)");
            stmt.step();
        }
        version = 2;
    }

    if (version < 3) {
        bool columnExists = false;
        {
            auto stmt = Database::Statement(db,
                "PRAGMA table_info(sync_configs)");
            while (stmt.step()) {
                if (stmt.columnText(1) == "delete_after_sync") {
                    columnExists = true;
                    break;
                }
            }
        }

        if (!columnExists) {
            db.execute(R"(
                ALTER TABLE sync_configs
                ADD COLUMN delete_after_sync INTEGER NOT NULL DEFAULT 0
            )");
        }

        {
            auto stmt = Database::Statement(db,
                "INSERT INTO schema_version (version) VALUES (3)");
            stmt.step();
        }
        version = 3;
    }

    if (version < 11) {
        bool hasSyncType = false;
        bool hasSyncTime = false;
        {
            auto stmt = Database::Statement(db,
                "PRAGMA table_info(sync_configs)");
            while (stmt.step()) {
                auto name = stmt.columnText(1);
                if (name == "sync_policy") hasSyncType = true;
                if (name == "sync_time") hasSyncTime = true;
            }
        }

        if (!hasSyncType) {
            db.execute(R"(
                ALTER TABLE sync_configs
                ADD COLUMN sync_policy TEXT NOT NULL DEFAULT 'interval'
            )");
        }
        if (!hasSyncTime) {
            db.execute(R"(
                ALTER TABLE sync_configs
                ADD COLUMN sync_time TEXT NOT NULL DEFAULT ''
            )");
        }

        {
            auto stmt = Database::Statement(db,
                "INSERT INTO schema_version (version) VALUES (11)");
            stmt.step();
        }
        version = 11;
    }

    if (version < 12) {
        {
            auto stmt = Database::Statement(db,
                "PRAGMA table_info(sync_configs)");
            bool hasSyncPolicy = false;
            bool hasSyncType = false;
            while (stmt.step()) {
                auto name = stmt.columnText(1);
                if (name == "sync_policy") hasSyncPolicy = true;
                if (name == "sync_type") hasSyncType = true;
            }

            if (hasSyncType && !hasSyncPolicy) {
                db.execute("ALTER TABLE sync_configs RENAME COLUMN sync_type TO sync_policy");
            } else if (!hasSyncPolicy) {
                db.execute("ALTER TABLE sync_configs ADD COLUMN sync_policy TEXT NOT NULL DEFAULT 'interval'");
            }
        }

        auto stmt2 = Database::Statement(db,
            "PRAGMA table_info(sync_configs)");
        bool hasSyncTime = false;
        while (stmt2.step()) {
            if (stmt2.columnText(1) == "sync_time") {
                hasSyncTime = true;
                break;
            }
        }
        if (!hasSyncTime) {
            db.execute("ALTER TABLE sync_configs ADD COLUMN sync_time TEXT NOT NULL DEFAULT ''");
        }

        {
            auto stmt = Database::Statement(db,
                "INSERT INTO schema_version (version) VALUES (12)");
            stmt.step();
        }
        version = 12;
    }
}

SyncConfigRepository::Entry SyncConfigRepository::rowToEntry(
    Database::Statement& stmt) const
{
    Entry e;
    e.id = stmt.columnInt64(0);
    e.name = stmt.columnText(1);
    e.sourcePath = stmt.columnText(2);
    e.targetPath = stmt.columnText(3);
    e.syncIntervalSecs = stmt.columnInt64(4);
    if (!stmt.columnNull(5)) {
        e.lastSyncedAt = stmt.columnText(5);
    }
    e.enabled = stmt.columnInt64(6) != 0;
    e.createdAt = stmt.columnText(7);
    e.updatedAt = stmt.columnText(8);
    e.deleteAfterSync = stmt.columnInt64(9) != 0;
    e.syncPolicy = stmt.columnText(10);
    e.syncTime = stmt.columnText(11);
    return e;
}

std::vector<SyncConfigRepository::Entry>
SyncConfigRepository::findAll() {
    std::vector<Entry> entries;
    auto stmt = Database::Statement(m_db,
        "SELECT id, name, source_path, target_path, "
        "       sync_interval_secs, last_synced_at, enabled, "
        "       created_at, updated_at, delete_after_sync, "
        "       sync_policy, sync_time "
        "FROM sync_configs ORDER BY name");

    while (stmt.step()) {
        entries.push_back(rowToEntry(stmt));
    }
    return entries;
}

std::optional<SyncConfigRepository::Entry>
SyncConfigRepository::findById(int64_t id) {
    auto stmt = Database::Statement(m_db,
        "SELECT id, name, source_path, target_path, "
        "       sync_interval_secs, last_synced_at, enabled, "
        "       created_at, updated_at, delete_after_sync, "
        "       sync_policy, sync_time "
        "FROM sync_configs WHERE id = ?");
    stmt.bind(1, id);

    if (stmt.step()) {
        return rowToEntry(stmt);
    }
    return std::nullopt;
}

std::vector<SyncConfigRepository::Entry>
SyncConfigRepository::findByTargetPath(const std::string& targetPath) {
    std::vector<Entry> entries;
    auto stmt = Database::Statement(m_db,
        "SELECT id, name, source_path, target_path, "
        "       sync_interval_secs, last_synced_at, enabled, "
        "       created_at, updated_at, delete_after_sync, "
        "       sync_policy, sync_time "
        "FROM sync_configs WHERE target_path = ? ORDER BY name");
    stmt.bind(1, targetPath);

    while (stmt.step()) {
        entries.push_back(rowToEntry(stmt));
    }
    return entries;
}

int64_t SyncConfigRepository::insert(const Entry& entry) {
    auto stmt = Database::Statement(m_db,
        "INSERT INTO sync_configs "
        "(name, source_path, target_path, sync_interval_secs, enabled, delete_after_sync, sync_policy, sync_time) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
    stmt.bind(1, entry.name);
    stmt.bind(2, entry.sourcePath);
    stmt.bind(3, entry.targetPath);
    stmt.bind(4, entry.syncIntervalSecs);
    stmt.bind(5, static_cast<int64_t>(entry.enabled));
    stmt.bind(6, static_cast<int64_t>(entry.deleteAfterSync));
    stmt.bind(7, entry.syncPolicy);
    stmt.bind(8, entry.syncTime);
    stmt.step();

    return m_db.lastInsertRowId();
}

void SyncConfigRepository::update(const Entry& entry) {
    auto stmt = Database::Statement(m_db,
        "UPDATE sync_configs SET "
        "name = ?, source_path = ?, target_path = ?, "
        "sync_interval_secs = ?, enabled = ?, "
        "delete_after_sync = ?, "
        "sync_policy = ?, sync_time = ?, "
        "updated_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now') "
        "WHERE id = ?");
    stmt.bind(1, entry.name);
    stmt.bind(2, entry.sourcePath);
    stmt.bind(3, entry.targetPath);
    stmt.bind(4, entry.syncIntervalSecs);
    stmt.bind(5, static_cast<int64_t>(entry.enabled));
    stmt.bind(6, static_cast<int64_t>(entry.deleteAfterSync));
    stmt.bind(7, entry.syncPolicy);
    stmt.bind(8, entry.syncTime);
    stmt.bind(9, entry.id);
    stmt.step();
}

bool SyncConfigRepository::deleteById(int64_t id) {
    auto stmt = Database::Statement(m_db,
        "DELETE FROM sync_configs WHERE id = ?");
    stmt.bind(1, id);
    stmt.step();
    return sqlite3_changes(m_db.handle()) > 0;
}

void SyncConfigRepository::updateLastSyncedAt(int64_t id) {
    auto stmt = Database::Statement(m_db,
        "UPDATE sync_configs SET "
        "last_synced_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now'), "
        "updated_at = datetime('now') "
        "WHERE id = ?");
    stmt.bind(1, id);
    stmt.step();
}

} // namespace ainas
