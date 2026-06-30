#include "ainas/logging/Logger.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <ctime>
#include <iostream>
#include <sstream>
#include <thread>

namespace ainas {

//===----------------------------------------------------------------------===//
//  Singleton
//===----------------------------------------------------------------------===//

void Logger::init(Config config) {
    auto& inst = instance();
    inst.m_config = std::move(config);

    if (!inst.m_config.filePath.empty()) {
        inst.m_fileStream.open(inst.m_config.filePath, std::ios::app);
        if (!inst.m_fileStream.is_open()) {
            std::cerr << "Logger: failed to open log file: "
                      << inst.m_config.filePath << std::endl;
        }
    }
}

Logger& Logger::instance() {
    static Logger inst;
    return inst;
}

//===----------------------------------------------------------------------===//
//  Level helpers
//===----------------------------------------------------------------------===//

std::string_view Logger::levelName(LogLevel level) noexcept {
    using namespace std::string_view_literals;
    static constexpr std::array names{
        "TRACE"sv, "DEBUG"sv, "INFO"sv, "WARN"sv, "ERROR"sv, "FATAL"sv
    };
    auto idx = static_cast<uint8_t>(level);
    return idx < names.size() ? names[idx] : "?????"sv;
}

//===----------------------------------------------------------------------===//
//  Colours
//===----------------------------------------------------------------------===//

std::string Logger::colorEscape(LogLevel level) {
    switch (level) {
        case LogLevel::Trace: return "\033[90m"; // gray
        case LogLevel::Debug: return "\033[36m"; // cyan
        case LogLevel::Info:  return "\033[32m"; // green
        case LogLevel::Warn:  return "\033[33m"; // yellow
        case LogLevel::Error: return "\033[31m"; // red
        case LogLevel::Fatal: return "\033[41m"; // red bg
    }
    return "\033[0m";
}

//===----------------------------------------------------------------------===//
//  Timestamp
//===----------------------------------------------------------------------===//

std::string Logger::formatTimestamp(std::chrono::system_clock::time_point now) {
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                  now.time_since_epoch()) %
              1000;
    std::time_t t = std::chrono::system_clock::to_time_t(now);
    std::tm bt{};
#if defined(_WIN32)
    localtime_s(&bt, &t);
#else
    localtime_r(&t, &bt);
#endif
    char buf[64];
    std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%S", &bt);
    return std::format("{}.{:03d}", buf, static_cast<int>(ms.count()));
}

//===----------------------------------------------------------------------===//
//  Thread-ID helper (no std::formatter in GCC 13)
//===----------------------------------------------------------------------===//

namespace {

std::string tid() {
    std::ostringstream ss;
    ss << std::this_thread::get_id();
    auto s = ss.str();
    if (s.size() > 8) s = s.substr(s.size() - 8);
    return s;
}

} // anonymous namespace

//===----------------------------------------------------------------------===//
//  Core write
//===----------------------------------------------------------------------===//

void Logger::write(LogLevel level, std::source_location loc, std::string&& message) {
    std::lock_guard<std::mutex> lock(m_mutex);

    auto now = std::chrono::system_clock::now();
    auto timestamp = formatTimestamp(now);
    auto lvl = levelName(level);

    // Shorten file path to just filename
    std::string_view fullPath(loc.file_name());
    auto lastSlash = fullPath.find_last_of("/\\");
    auto filename = (lastSlash != std::string_view::npos)
                        ? fullPath.substr(lastSlash + 1)
                        : fullPath;

    auto source = std::format("{}:{}", filename, loc.line());

    // --- Console (ANSI-coloured) ---
    if (m_config.console) {
        auto line = std::format(
            "{}[{}] [{}] [{}] [{}] {}{}",
            colorEscape(level),
            timestamp,
            lvl,
            tid(),
            source,
            message,
            colorReset());

        if (level >= LogLevel::Error)
            std::cerr << line << std::endl;
        else
            std::cout << line << std::endl;
    }

    // --- File (plain text) ---
    if (m_fileStream.is_open()) {
        m_fileStream << std::format(
            "[{}] [{}] [{}] {}\n", timestamp, lvl, source, message);
        m_fileStream.flush();
    }
}

void Logger::setLogFile(std::string_view path) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_fileStream.is_open()) {
        m_fileStream.close();
    }
    m_config.filePath = path;
    m_fileStream.open(m_config.filePath, std::ios::app);
    if (!m_fileStream.is_open()) {
        std::cerr << "Logger: failed to reopen log file: "
                  << m_config.filePath << std::endl;
    }
}

void Logger::logRaw(LogLevel level, std::string_view message,
                    std::source_location loc) {
    if (static_cast<uint8_t>(level) < static_cast<uint8_t>(m_config.level))
        return;
    write(level, loc, std::string{message});
}

} // namespace ainas
