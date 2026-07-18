#pragma once

#include <string>

namespace ainas {

/// Replaces invalid UTF-8 byte sequences with '?' so that nlohmann::json::parse
/// does not throw type_error.316 on malformed model output.
inline std::string sanitizeUtf8(const std::string& s) {
    std::string out;
    out.reserve(s.size());
    size_t i = 0;
    while (i < s.size()) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        if (c <= 0x7F) {
            out += c; ++i;
            continue;
        }
        int n;
        if (c >= 0xC2 && c <= 0xDF) n = 2;
        else if (c >= 0xE0 && c <= 0xEF) n = 3;
        else if (c >= 0xF0 && c <= 0xF4) n = 4;
        else { out += '?'; ++i; continue; }
        bool ok = true;
        for (int j = 1; j < n; ++j) {
            if (i + j >= s.size() || (static_cast<unsigned char>(s[i + j]) & 0xC0) != 0x80) {
                ok = false; break;
            }
        }
        if (ok) {
            for (int j = 0; j < n; ++j) out += s[i + j];
            i += n;
        } else {
            out += '?';
            ++i;
        }
    }
    return out;
}

} // namespace ainas
