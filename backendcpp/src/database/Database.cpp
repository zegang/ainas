#include "ainas/database/Database.hpp"

#include <sqlite3.h>

#include <system_error>
#include <utility>

namespace ainas {

//===----------------------------------------------------------------------===//
//  Database
//===----------------------------------------------------------------------===//

Database::Database(const std::filesystem::path& dbPath)
    : m_path(dbPath)
{
    std::error_code ec;
    auto parent = dbPath.parent_path();
    if (!parent.empty()) {
        std::filesystem::create_directories(parent, ec);
    }

    int rc = sqlite3_open(dbPath.c_str(), &m_db);
    if (rc != SQLITE_OK) {
        std::string msg = sqlite3_errmsg(m_db);
        sqlite3_close(m_db);
        m_db = nullptr;
        throw DatabaseError(rc, "Failed to open database: " + msg);
    }

    execute("PRAGMA journal_mode=WAL");
    execute("PRAGMA foreign_keys=ON");
}

Database::~Database() {
    if (m_db) {
        sqlite3_close(m_db);
    }
}

Database::Database(Database&& other) noexcept
    : m_db(std::exchange(other.m_db, nullptr))
    , m_path(std::move(other.m_path))
{}

Database& Database::operator=(Database&& other) noexcept {
    if (this != &other) {
        if (m_db) sqlite3_close(m_db);
        m_db = std::exchange(other.m_db, nullptr);
        m_path = std::move(other.m_path);
    }
    return *this;
}

void Database::execute(std::string_view sql) {
    char* errMsg = nullptr;
    int rc = sqlite3_exec(m_db, sql.data(), nullptr, nullptr, &errMsg);
    if (rc != SQLITE_OK) {
        std::string msg = errMsg ? errMsg : "unknown error";
        sqlite3_free(errMsg);
        throw DatabaseError(rc, "SQL execute failed: " + msg);
    }
}

int64_t Database::lastInsertRowId() const {
    return sqlite3_last_insert_rowid(m_db);
}

void Database::checkSqlite(int rc, sqlite3* db, const char* context) {
    if (rc != SQLITE_OK && rc != SQLITE_DONE) {
        throw DatabaseError(rc,
            std::string(context) + ": " + sqlite3_errmsg(db));
    }
}

//===----------------------------------------------------------------------===//
//  Statement
//===----------------------------------------------------------------------===//

Database::Statement::Statement(Database& db, std::string_view sql)
    : m_db(&db)
{
    int rc = sqlite3_prepare_v2(db.m_db, sql.data(),
                                 static_cast<int>(sql.size()),
                                 &m_stmt, nullptr);
    if (rc != SQLITE_OK) {
        throw DatabaseError(rc, "Failed to prepare statement: " +
                             std::string(sqlite3_errmsg(db.m_db)));
    }
}

Database::Statement::~Statement() {
    if (m_stmt) {
        sqlite3_finalize(m_stmt);
    }
}

Database::Statement::Statement(Statement&& other) noexcept
    : m_stmt(std::exchange(other.m_stmt, nullptr))
    , m_db(std::exchange(other.m_db, nullptr))
{}

Database::Statement& Database::Statement::operator=(Statement&& other) noexcept {
    if (this != &other) {
        if (m_stmt) sqlite3_finalize(m_stmt);
        m_stmt = std::exchange(other.m_stmt, nullptr);
        m_db = std::exchange(other.m_db, nullptr);
    }
    return *this;
}

void Database::Statement::checkBind(int rc, int index) {
    if (rc != SQLITE_OK) {
        throw DatabaseError(rc, "Bind error at index " + std::to_string(index));
    }
}

Database::Statement& Database::Statement::bind(int index, std::nullptr_t) {
    int rc = sqlite3_bind_null(m_stmt, index);
    checkBind(rc, index);
    return *this;
}

Database::Statement& Database::Statement::bind(int index, int64_t value) {
    int rc = sqlite3_bind_int64(m_stmt, index, value);
    checkBind(rc, index);
    return *this;
}

Database::Statement& Database::Statement::bind(int index, double value) {
    int rc = sqlite3_bind_double(m_stmt, index, value);
    checkBind(rc, index);
    return *this;
}

Database::Statement& Database::Statement::bind(int index, const std::string& value) {
    int rc = sqlite3_bind_text(m_stmt, index, value.data(),
                                static_cast<int>(value.size()),
                                SQLITE_TRANSIENT);
    checkBind(rc, index);
    return *this;
}

Database::Statement& Database::Statement::bind(int index, std::string_view value) {
    int rc = sqlite3_bind_text(m_stmt, index, value.data(),
                                static_cast<int>(value.size()),
                                SQLITE_TRANSIENT);
    checkBind(rc, index);
    return *this;
}

bool Database::Statement::step() {
    int rc = sqlite3_step(m_stmt);
    if (rc == SQLITE_ROW) return true;
    if (rc == SQLITE_DONE) return false;
    throw DatabaseError(rc, "Step failed: " +
                         std::string(sqlite3_errmsg(m_db->m_db)));
}

int Database::Statement::columnCount() const {
    return sqlite3_column_count(m_stmt);
}

int64_t Database::Statement::columnInt64(int index) const {
    return sqlite3_column_int64(m_stmt, index);
}

double Database::Statement::columnDouble(int index) const {
    return sqlite3_column_double(m_stmt, index);
}

std::string Database::Statement::columnText(int index) const {
    auto text = sqlite3_column_text(m_stmt, index);
    auto bytes = sqlite3_column_bytes(m_stmt, index);
    return {reinterpret_cast<const char*>(text), static_cast<size_t>(bytes)};
}

bool Database::Statement::columnNull(int index) const {
    return sqlite3_column_type(m_stmt, index) == SQLITE_NULL;
}

void Database::Statement::reset() {
    sqlite3_reset(m_stmt);
}

//===----------------------------------------------------------------------===//
//  Transaction
//===----------------------------------------------------------------------===//

Database::Transaction::Transaction(Database& db)
    : m_db(&db)
{
    m_db->execute("BEGIN IMMEDIATE");
}

Database::Transaction::~Transaction() {
    if (m_db && !m_committed) {
        try {
            m_db->execute("ROLLBACK");
        } catch (...) {
            // swallow during unwind
        }
    }
}

void Database::Transaction::commit() {
    m_db->execute("COMMIT");
    m_committed = true;
}

void Database::Transaction::rollback() noexcept {
    if (m_db && !m_committed) {
        try {
            m_db->execute("ROLLBACK");
            m_committed = true;
        } catch (...) {
        }
    }
}

} // namespace ainas
