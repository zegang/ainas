#pragma once

#include <cstddef>
#include <cstdint>
#include <ctime>
#include <string>
#include <vector>

namespace ainas::platform {

// ── Hostname ───────────────────────────────────────────────────────────
std::string hostname();

// ── Executable path ────────────────────────────────────────────────────
std::string executablePath();

// ── Environment ────────────────────────────────────────────────────────
bool setEnv(const char* name, const char* value);
std::string getEnv(const char* name);

// ── Crash-safe I/O (async-signal-safe, no allocations) ─────────────────
void safeWrite(int fd, const char* s);
int  safeOpen(const char* path, int flags, int mode);
void safeClose(int fd);

// ── Thread-safe localtime ──────────────────────────────────────────────
bool localtime(const time_t* clock, struct tm* result);

// ── Thread name ────────────────────────────────────────────────────────
bool setThreadName(const char* name);

// ── Daemonize ──────────────────────────────────────────────────────────
bool daemonize();

// ── Dynamic library loader ─────────────────────────────────────────────
class DynamicLib {
public:
    DynamicLib() = default;
    ~DynamicLib();

    DynamicLib(const DynamicLib&) = delete;
    DynamicLib& operator=(const DynamicLib&) = delete;

    DynamicLib(DynamicLib&& other) noexcept
        : m_handle(other.m_handle) { other.m_handle = nullptr; }
    DynamicLib& operator=(DynamicLib&& other) noexcept;

    bool open(const char* path);
    void* sym(const char* name) const;
    void close();
    explicit operator bool() const { return m_handle != nullptr; }

private:
    void* m_handle = nullptr;
};

// ── Process management ─────────────────────────────────────────────────
using Pid = uint64_t;

bool spawnProcess(const std::string& path,
                  const std::vector<std::string>& args,
                  Pid& outPid);
bool isProcessRunning(Pid pid);
bool waitProcess(Pid pid, int timeoutMs = -1);
bool killProcess(Pid pid);
int  processExitCode(Pid pid);

} // namespace ainas::platform
