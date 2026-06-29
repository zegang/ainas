#include "ainas/util/cflag.hpp"

#include <iostream>

namespace ainas::util {

FlagParser::FlagParser(int argc, const char* argv[]) {
    for (int i = 1; i < argc; ++i) {
        std::string_view arg(argv[i]);

        if (arg.size() < 2 || arg[0] != '-' || arg[1] != '-') {
            continue;
        }
        arg.remove_prefix(2);

        auto eq = arg.find('=');
        if (eq != std::string_view::npos) {
            auto key = arg.substr(0, eq);
            auto val = arg.substr(eq + 1);
            m_flags.emplace(key, val);
        } else {
            std::string key(arg);
            if (i + 1 < argc) {
                std::string_view next(argv[i + 1]);
                if (next.size() >= 2 && next[0] == '-' && next[1] == '-') {
                    m_flags.emplace(std::move(key), "");
                } else {
                    m_flags.emplace(std::move(key), next);
                    ++i;
                }
            } else {
                m_flags.emplace(std::move(key), "");
            }
        }
    }
}

bool FlagParser::has(std::string_view name) const {
    return m_flags.find(name) != m_flags.end();
}

std::string FlagParser::get(std::string_view name, std::string_view defaultVal) const {
    auto it = m_flags.find(name);
    if (it != m_flags.end()) {
        return it->second;
    }
    return std::string(defaultVal);
}

void FlagParser::usage(const char* prog, const char* extra) const {
    std::cerr << "Usage: " << prog << " [options]\n"
              << "Options:\n"
              << "  --addr <ip>            Listening IP address (default: 0.0.0.0)\n"
              << "  --port <port>          Listening port (default: 9026)\n"
              << "  --storage <path>       Storage root directory (alias: --storage-root-path)\n"
              << "  --daemon               Run as daemon (Unix only)\n"
              << "  --log-level <level>    Log level (trace, debug, info, warn, error)\n"
              << "  --log-file <path>      Log file path\n";
    if (extra) {
        std::cerr << extra;
    }
}

} // namespace ainas::util
