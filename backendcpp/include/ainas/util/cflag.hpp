#pragma once

#include <map>
#include <string>
#include <string_view>

namespace ainas::util {

class FlagParser {
public:
    FlagParser(int argc, const char* argv[]);

    bool has(std::string_view name) const;
    std::string get(std::string_view name, std::string_view defaultVal = "") const;

    void usage(const char* prog, const char* extra = nullptr) const;

private:
    std::map<std::string, std::string, std::less<>> m_flags;
};

} // namespace ainas::util
