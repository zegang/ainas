#pragma once

#include <atomic>
#include <chrono>
#include <format>
#include <fstream>
#include <mutex>
#include <source_location>
#include <string>
#include <string_view>

namespace ainas {

enum class LogLevel : uint8_t {
    Trace,
    Debug,
    Info,
    Warn,
    Error,
    Fatal
};

class Logger {
public:
    struct Config {
        LogLevel level{LogLevel::Info};
        bool console{true};
        std::string filePath{};
        uint64_t maxFileSize{10 * 1024 * 1024}; // 10 MB – 0 to disable
    };

    static void init(Config config);
    static Logger& instance();

    void setLevel(LogLevel level) noexcept { m_config.level = level; }
    void setLogFile(std::string_view path);
    LogLevel level() const noexcept { return m_config.level; }
    std::string getLogFilePath() const noexcept { return m_config.filePath; }

    // Core log - source_location passed first (by macro), then format-string + args
    template<typename... Args>
    void log(LogLevel level,
             std::source_location loc,
             std::format_string<Args...> fmt,
             Args&&... args)
    {
        if (static_cast<uint8_t>(level) < static_cast<uint8_t>(m_config.level))
            return;
        write(level, loc, std::format(fmt, std::forward<Args>(args)...));
    }

    // Runtime message (no compile-time format check)
    void logRaw(LogLevel level,
                std::string_view message,
                std::source_location loc = std::source_location::current());

private:
    Logger() = default;

    void write(LogLevel level, std::source_location loc, std::string&& message);

    static std::string_view levelName(LogLevel level) noexcept;
    static std::string formatTimestamp(
        std::chrono::system_clock::time_point now = std::chrono::system_clock::now());
    static std::string colorEscape(LogLevel level);
    static const char* colorReset() noexcept { return "\033[0m"; }

    Config m_config;
    std::mutex m_mutex;
    std::ofstream m_fileStream;
};

//===----------------------------------------------------------------------===//
//  Macros - convenience wrappers that capture source_location at call site
//  and forward everything to the matching Logger::log() overload
//===----------------------------------------------------------------------===//

#define LOG_TRACE(...)    ::ainas::Logger::instance().log(   \
    ::ainas::LogLevel::Trace,                                  \
    std::source_location::current(),                           \
    __VA_ARGS__)

#define LOG_DEBUG(...)    ::ainas::Logger::instance().log(   \
    ::ainas::LogLevel::Debug,                                  \
    std::source_location::current(),                           \
    __VA_ARGS__)

#define LOG_INFO(...)     ::ainas::Logger::instance().log(   \
    ::ainas::LogLevel::Info,                                   \
    std::source_location::current(),                           \
    __VA_ARGS__)

#define LOG_WARN(...)     ::ainas::Logger::instance().log(   \
    ::ainas::LogLevel::Warn,                                   \
    std::source_location::current(),                           \
    __VA_ARGS__)

#define LOG_ERROR(...)    ::ainas::Logger::instance().log(   \
    ::ainas::LogLevel::Error,                                  \
    std::source_location::current(),                           \
    __VA_ARGS__)

#define LOG_FATAL(...)    ::ainas::Logger::instance().log(   \
    ::ainas::LogLevel::Fatal,                                  \
    std::source_location::current(),                           \
    __VA_ARGS__)

// For runtime strings (no compile-time format check)
#define LOG_RAW(level, msg) \
    ::ainas::Logger::instance().logRaw(level, msg,             \
        std::source_location::current())

} // namespace ainas
