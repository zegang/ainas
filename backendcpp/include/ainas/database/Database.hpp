#pragma once

#include <filesystem>
#include <stdexcept>
#include <string>
#include <string_view>

struct sqlite3;
struct sqlite3_stmt;

namespace ainas {

class DatabaseError : public std::runtime_error {
public:
    int code;
    DatabaseError(int code, const std::string& msg)
        : std::runtime_error(msg), code(code) {}
};

class Database {
public:
    explicit Database(const std::filesystem::path& dbPath);
    ~Database();

    Database(const Database&) = delete;
    Database& operator=(const Database&) = delete;

    Database(Database&&) noexcept;
    Database& operator=(Database&&) noexcept;

    void execute(std::string_view sql);

    class Statement {
    public:
        Statement(Database& db, std::string_view sql);
        ~Statement();

        Statement(const Statement&) = delete;
        Statement& operator=(const Statement&) = delete;

        Statement(Statement&&) noexcept;
        Statement& operator=(Statement&&) noexcept;

        Statement& bind(int index, std::nullptr_t);
        Statement& bind(int index, int64_t value);
        Statement& bind(int index, double value);
        Statement& bind(int index, const std::string& value);
        Statement& bind(int index, std::string_view value);

        bool step();

        int columnCount() const;
        int64_t columnInt64(int index) const;
        double columnDouble(int index) const;
        std::string columnText(int index) const;
        bool columnNull(int index) const;

        void reset();

        explicit operator bool() const { return m_stmt != nullptr; }

    private:
        sqlite3_stmt* m_stmt{nullptr};
        Database* m_db{nullptr};
        void checkBind(int rc, int index);
    };

    class Transaction {
    public:
        explicit Transaction(Database& db);
        ~Transaction();

        Transaction(const Transaction&) = delete;
        Transaction& operator=(const Transaction&) = delete;

        void commit();
        void rollback() noexcept;

    private:
        Database* m_db{nullptr};
        bool m_committed{false};
    };

    sqlite3* handle() { return m_db; }
    const std::filesystem::path& path() const { return m_path; }
    int64_t lastInsertRowId() const;

private:
    sqlite3* m_db{nullptr};
    std::filesystem::path m_path;

    static void checkSqlite(int rc, sqlite3* db, const char* context);
};

} // namespace ainas
