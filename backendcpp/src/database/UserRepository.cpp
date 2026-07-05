#include "ainas/database/UserRepository.hpp"

#include <array>
#include <cstdint>
#include <cstring>
#include <sqlite3.h>
#include <ctime>
#include <iomanip>
#include <sstream>

namespace ainas {
namespace {

// ── Minimal SHA-256 (public domain, adapted from Olivier Gay) ─────

constexpr std::array<uint32_t, 64> K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

inline uint32_t rotr(uint32_t x, uint32_t n) {
    return (x >> n) | (x << (32 - n));
}

inline uint32_t ch(uint32_t x, uint32_t y, uint32_t z) {
    return (x & y) ^ (~x & z);
}

inline uint32_t maj(uint32_t x, uint32_t y, uint32_t z) {
    return (x & y) ^ (x & z) ^ (y & z);
}

inline uint32_t sigma0(uint32_t x) {
    return rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22);
}

inline uint32_t sigma1(uint32_t x) {
    return rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25);
}

inline uint32_t gamma0(uint32_t x) {
    return rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3);
}

inline uint32_t gamma1(uint32_t x) {
    return rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10);
}

void sha256(const uint8_t* data, size_t len, uint8_t out[32]) {
    std::array<uint32_t, 8> H = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    };

    size_t blockLen = 0;
    std::array<uint8_t, 64> block{};
    uint64_t bits = 0;

    auto transform = [&](const uint8_t* blk) {
        std::array<uint32_t, 64> W{};
        for (int t = 0; t < 16; ++t) {
            W[t] = (static_cast<uint32_t>(blk[4 * t]) << 24)
                 | (static_cast<uint32_t>(blk[4 * t + 1]) << 16)
                 | (static_cast<uint32_t>(blk[4 * t + 2]) << 8)
                 | (static_cast<uint32_t>(blk[4 * t + 3]));
        }
        for (int t = 16; t < 64; ++t) {
            W[t] = gamma1(W[t - 2]) + W[t - 7] + gamma0(W[t - 15]) + W[t - 16];
        }

        auto a = H[0], b = H[1], c = H[2], d = H[3];
        auto e = H[4], f = H[5], g = H[6], h = H[7];

        for (int t = 0; t < 64; ++t) {
            auto T1 = h + sigma1(e) + ch(e, f, g) + K[t] + W[t];
            auto T2 = sigma0(a) + maj(a, b, c);
            h = g;
            g = f;
            f = e;
            e = d + T1;
            d = c;
            c = b;
            b = a;
            a = T1 + T2;
        }

        H[0] += a; H[1] += b; H[2] += c; H[3] += d;
        H[4] += e; H[5] += f; H[6] += g; H[7] += h;
    };

    // Process complete 64-byte blocks
    for (size_t i = 0; i < len; ++i) {
        block[blockLen++] = data[i];
        bits += 8;
        if (blockLen == 64) {
            transform(block.data());
            blockLen = 0;
        }
    }

    // Padding
    block[blockLen++] = 0x80;
    if (blockLen > 56) {
        while (blockLen < 64) block[blockLen++] = 0;
        transform(block.data());
        blockLen = 0;
    }
    while (blockLen < 56) block[blockLen++] = 0;

    // Append bit length (big-endian)
    bits += len * 8;
    block[56] = static_cast<uint8_t>(bits >> 56);
    block[57] = static_cast<uint8_t>(bits >> 48);
    block[58] = static_cast<uint8_t>(bits >> 40);
    block[59] = static_cast<uint8_t>(bits >> 32);
    block[60] = static_cast<uint8_t>(bits >> 24);
    block[61] = static_cast<uint8_t>(bits >> 16);
    block[62] = static_cast<uint8_t>(bits >> 8);
    block[63] = static_cast<uint8_t>(bits);
    transform(block.data());

    // Output bytes (big-endian)
    for (int i = 0; i < 8; ++i) {
        out[4 * i]     = static_cast<uint8_t>(H[i] >> 24);
        out[4 * i + 1] = static_cast<uint8_t>(H[i] >> 16);
        out[4 * i + 2] = static_cast<uint8_t>(H[i] >> 8);
        out[4 * i + 3] = static_cast<uint8_t>(H[i]);
    }
}

} // anonymous namespace

// ── UserRepository ────────────────────────────────────────────────────

UserRepository::UserRepository(Database& db)
    : m_db(db)
{}

void UserRepository::migrate() {
    m_db.execute(R"(
        CREATE TABLE IF NOT EXISTS users (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            username      TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            role          TEXT NOT NULL DEFAULT 'user',
            created_at    INTEGER NOT NULL
        )
    )");
    // Add role column for databases created before role was introduced
    {
        bool hasRole = false;
        auto stmt = Database::Statement(m_db, "PRAGMA table_info(users)");
        while (stmt.step()) {
            if (stmt.columnText(1) == "role") {
                hasRole = true;
                break;
            }
        }
        if (!hasRole) {
            m_db.execute(R"(
                ALTER TABLE users ADD COLUMN role TEXT NOT NULL DEFAULT 'user'
            )");
        }
    }
}

bool UserRepository::registerUser(const std::string& username,
                                   const std::string& password,
                                   const std::string& role) {
    auto stmt = Database::Statement(m_db,
        "INSERT INTO users (username, password_hash, role, created_at) VALUES (?, ?, ?, ?)");
    stmt.bind(1, username);
    stmt.bind(2, hashPassword(password));
    stmt.bind(3, role);
    stmt.bind(4, static_cast<int64_t>(::time(nullptr)));
    try {
        stmt.step();
        return true;
    } catch (const DatabaseError&) {
        return false;
    }
}

std::optional<UserRepository::User>
UserRepository::findByUsername(const std::string& username) {
    auto stmt = Database::Statement(m_db,
        "SELECT id, username, password_hash, role, created_at FROM users WHERE username = ?");
    stmt.bind(1, username);

    if (stmt.step()) {
        return User{
            stmt.columnInt64(0),
            stmt.columnText(1),
            stmt.columnText(2),
            stmt.columnText(3),
            stmt.columnInt64(4),
        };
    }
    return std::nullopt;
}

bool UserRepository::deleteUser(const std::string& username) {
    auto stmt = Database::Statement(m_db,
        "DELETE FROM users WHERE username = ?");
    stmt.bind(1, username);
    stmt.step();
    return sqlite3_changes(m_db.handle()) > 0;
}

std::string UserRepository::hashPassword(const std::string& password) {
    // SHA-256 with a fixed salt
    auto salted = password + "ainas::user::salt";
    std::array<uint8_t, 32> digest{};
    sha256(reinterpret_cast<const uint8_t*>(salted.data()), salted.size(), digest.data());

    std::ostringstream oss;
    for (auto b : digest) {
        oss << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(b);
    }
    return oss.str();
}

} // namespace ainas
