#include "ainas/database/FileRepository.hpp"

#include <sqlite3.h>
#include <format>

namespace ainas {

FileRepository::FileRepository(Database& db)
    : m_db(db)
{}

//===----------------------------------------------------------------------===//
//  Schema management
//===----------------------------------------------------------------------===//

void FileRepository::migrate() {
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

    if (version < 1) {
        db.execute(R"(
            CREATE TABLE IF NOT EXISTS file_metadata (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                name        TEXT    NOT NULL,
                path        TEXT    NOT NULL UNIQUE,
                size        INTEGER NOT NULL DEFAULT 0,
                is_directory INTEGER NOT NULL DEFAULT 0,
                created_at  INTEGER NOT NULL,
                updated_at  INTEGER NOT NULL,
                parent_id   INTEGER REFERENCES file_metadata(id)
            )
        )");

        db.execute(R"(
            CREATE INDEX IF NOT EXISTS idx_file_metadata_path
                ON file_metadata(path)
        )");

        db.execute(R"(
            CREATE INDEX IF NOT EXISTS idx_file_metadata_parent
                ON file_metadata(parent_id)
        )");

        db.execute(R"(
            CREATE TABLE IF NOT EXISTS tags (
                id   INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT    NOT NULL UNIQUE
            )
        )");

        db.execute(R"(
            CREATE TABLE IF NOT EXISTS file_tags (
                file_id INTEGER NOT NULL REFERENCES file_metadata(id)
                    ON DELETE CASCADE,
                tag_id  INTEGER NOT NULL REFERENCES tags(id)
                    ON DELETE CASCADE,
                PRIMARY KEY (file_id, tag_id)
            )
        )");

        {
            auto stmt = Database::Statement(db,
                "INSERT INTO schema_version (version) VALUES (1)");
            stmt.step();
        }
        version = 1;
    }
}

//===----------------------------------------------------------------------===//
//  Record mapping
//===----------------------------------------------------------------------===//

FileRepository::Record FileRepository::rowToRecord(
    Database::Statement& stmt) const
{
    Record r;
    r.id = static_cast<int64_t>(stmt.columnInt64(0));
    r.name = stmt.columnText(1);
    r.path = stmt.columnText(2);
    r.size = stmt.columnInt64(3);
    r.isDirectory = stmt.columnInt64(4) != 0;
    r.createdAt = stmt.columnInt64(5);
    r.updatedAt = stmt.columnInt64(6);
    if (!stmt.columnNull(7)) {
        r.parentId = stmt.columnInt64(7);
    }
    return r;
}

void FileRepository::loadTags(Record& record) const {
    auto stmt = Database::Statement(m_db,
        "SELECT t.name FROM tags t "
        "JOIN file_tags ft ON t.id = ft.tag_id "
        "WHERE ft.file_id = ? "
        "ORDER BY t.name");
    stmt.bind(1, record.id);
    while (stmt.step()) {
        record.tags.push_back(stmt.columnText(0));
    }
}

//===----------------------------------------------------------------------===//
//  CRUD
//===----------------------------------------------------------------------===//

std::optional<FileRepository::Record>
FileRepository::findById(int64_t id) {
    auto stmt = Database::Statement(m_db,
        "SELECT id, name, path, size, is_directory, "
        "       created_at, updated_at, parent_id "
        "FROM file_metadata WHERE id = ?");
    stmt.bind(1, id);

    if (stmt.step()) {
        auto record = rowToRecord(stmt);
        loadTags(record);
        return record;
    }
    return std::nullopt;
}

std::optional<FileRepository::Record>
FileRepository::findByPath(const std::string& path) {
    auto stmt = Database::Statement(m_db,
        "SELECT id, name, path, size, is_directory, "
        "       created_at, updated_at, parent_id "
        "FROM file_metadata WHERE path = ?");
    stmt.bind(1, path);

    if (stmt.step()) {
        auto record = rowToRecord(stmt);
        loadTags(record);
        return record;
    }
    return std::nullopt;
}

std::vector<FileRepository::Record>
FileRepository::findByParentId(std::optional<int64_t> parentId) {
    std::vector<Record> records;

    auto stmt = Database::Statement(m_db,
        "SELECT id, name, path, size, is_directory, "
        "       created_at, updated_at, parent_id "
        "FROM file_metadata WHERE parent_id IS ? "
        "ORDER BY name");

    if (parentId) {
        stmt.bind(1, *parentId);
    } else {
        stmt.bind(1, nullptr);
    }

    while (stmt.step()) {
        auto record = rowToRecord(stmt);
        loadTags(record);
        records.push_back(std::move(record));
    }
    return records;
}

std::vector<FileRepository::Record>
FileRepository::searchByName(const std::string& query) {
    std::vector<Record> records;
    auto pattern = std::format("%{}%", query);

    auto stmt = Database::Statement(m_db,
        "SELECT id, name, path, size, is_directory, "
        "       created_at, updated_at, parent_id "
        "FROM file_metadata WHERE name LIKE ? "
        "ORDER BY name LIMIT 100");
    stmt.bind(1, pattern);

    while (stmt.step()) {
        auto record = rowToRecord(stmt);
        records.push_back(std::move(record));
    }
    return records;
}

//===----------------------------------------------------------------------===//
//  Mutations
//===----------------------------------------------------------------------===//

int64_t FileRepository::insert(const Record& record) {
    auto stmt = Database::Statement(m_db,
        "INSERT INTO file_metadata "
        "(name, path, size, is_directory, created_at, updated_at, parent_id) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)");
    stmt.bind(1, record.name);
    stmt.bind(2, record.path);
    stmt.bind(3, record.size);
    stmt.bind(4, static_cast<int64_t>(record.isDirectory));
    stmt.bind(5, record.createdAt);
    stmt.bind(6, record.updatedAt);
    if (record.parentId) {
        stmt.bind(7, *record.parentId);
    } else {
        stmt.bind(7, nullptr);
    }
    stmt.step();

    auto id = m_db.lastInsertRowId();

    if (!record.tags.empty()) {
        setTags(id, record.tags);
    }

    return id;
}

void FileRepository::update(const Record& record) {
    auto stmt = Database::Statement(m_db,
        "UPDATE file_metadata SET "
        "name = ?, path = ?, size = ?, is_directory = ?, "
        "created_at = ?, updated_at = ?, parent_id = ? "
        "WHERE id = ?");
    stmt.bind(1, record.name);
    stmt.bind(2, record.path);
    stmt.bind(3, record.size);
    stmt.bind(4, static_cast<int64_t>(record.isDirectory));
    stmt.bind(5, record.createdAt);
    stmt.bind(6, record.updatedAt);
    if (record.parentId) {
        stmt.bind(7, *record.parentId);
    } else {
        stmt.bind(7, nullptr);
    }
    stmt.bind(8, record.id);
    stmt.step();
}

bool FileRepository::deleteById(int64_t id) {
    auto stmt = Database::Statement(m_db,
        "DELETE FROM file_metadata WHERE id = ?");
    stmt.bind(1, id);
    stmt.step();
    return sqlite3_changes(m_db.handle()) > 0;
}

bool FileRepository::deleteByPath(const std::string& path) {
    auto stmt = Database::Statement(m_db,
        "DELETE FROM file_metadata WHERE path = ?");
    stmt.bind(1, path);
    stmt.step();
    return sqlite3_changes(m_db.handle()) > 0;
}

int64_t FileRepository::deleteByParentId(int64_t parentId) {
    auto stmt = Database::Statement(m_db,
        "DELETE FROM file_metadata WHERE parent_id = ?");
    stmt.bind(1, parentId);
    stmt.step();
    return sqlite3_changes(m_db.handle());
}

//===----------------------------------------------------------------------===//
//  Tags
//===----------------------------------------------------------------------===//

void FileRepository::setTags(int64_t fileId,
                              const std::vector<std::string>& tags) {
    Database::Transaction tx(m_db);

    {
        auto stmt = Database::Statement(m_db,
            "DELETE FROM file_tags WHERE file_id = ?");
        stmt.bind(1, fileId);
        stmt.step();
    }

    for (const auto& tag : tags) {
        int64_t tagId = 0;

        auto findStmt = Database::Statement(m_db,
            "SELECT id FROM tags WHERE name = ?");
        findStmt.bind(1, tag);
        if (findStmt.step()) {
            tagId = findStmt.columnInt64(0);
        } else {
            auto insertStmt = Database::Statement(m_db,
                "INSERT INTO tags (name) VALUES (?)");
            insertStmt.bind(1, tag);
            insertStmt.step();
            tagId = m_db.lastInsertRowId();
        }

        auto linkStmt = Database::Statement(m_db,
            "INSERT OR IGNORE INTO file_tags (file_id, tag_id) VALUES (?, ?)");
        linkStmt.bind(1, fileId);
        linkStmt.bind(2, tagId);
        linkStmt.step();
    }

    tx.commit();
}

std::vector<std::string> FileRepository::getTags(int64_t fileId) {
    std::vector<std::string> tags;
    auto stmt = Database::Statement(m_db,
        "SELECT t.name FROM tags t "
        "JOIN file_tags ft ON t.id = ft.tag_id "
        "WHERE ft.file_id = ? "
        "ORDER BY t.name");
    stmt.bind(1, fileId);

    while (stmt.step()) {
        tags.push_back(stmt.columnText(0));
    }
    return tags;
}

int64_t FileRepository::countChildren(int64_t parentId) {
    auto stmt = Database::Statement(m_db,
        "SELECT COUNT(*) FROM file_metadata WHERE parent_id = ?");
    stmt.bind(1, parentId);
    if (stmt.step()) {
        return stmt.columnInt64(0);
    }
    return 0;
}

} // namespace ainas
