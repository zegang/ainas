#pragma once

#include "ainas/database/Database.hpp"

#include <array>
#include <cstdint>
#include <optional>
#include <string>

namespace ainas {

class UserRepository {
public:
    struct User {
        int64_t id;
        std::string username;
        std::string passwordHash;
        std::string role;
        int64_t createdAt;
    };

    explicit UserRepository(Database& db);

    void migrate();

    bool registerUser(const std::string& username, const std::string& password,
                      const std::string& role = "user");
    std::optional<User> findByUsername(const std::string& username);
    bool deleteUser(const std::string& username);

    static std::string hashPassword(const std::string& password);

private:
    Database& m_db;
};

} // namespace ainas
