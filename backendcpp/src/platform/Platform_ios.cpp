#include "ainas/platform/Platform.hpp"

#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <system_error>

#include <fcntl.h>
#include <unistd.h>
#include <dlfcn.h>
#include <signal.h>
#include <mach-o/dyld.h>
#include <pthread.h>

namespace ainas::platform {

std::string hostname() {
    char buf[256];
    if (gethostname(buf, sizeof(buf)) == 0) {
        buf[sizeof(buf) - 1] = '\0';
        return buf;
    }
    return "unknown";
}

std::string executablePath() {
    uint32_t size = 0;
    _NSGetExecutablePath(nullptr, &size);
    if (size > 0) {
        std::string buf(size, '\0');
        if (_NSGetExecutablePath(buf.data(), &size) == 0) {
            std::error_code ec;
            auto p = std::filesystem::canonical(buf, ec);
            if (!ec) return p.string();
        }
    }
    return {};
}

bool setEnv(const char* name, const char* value) {
    return setenv(name, value, 1) == 0;
}

std::string getEnv(const char* name) {
    auto* v = std::getenv(name);
    return v ? std::string(v) : std::string{};
}

void safeWrite(int fd, const char* s) {
    write(fd, s, std::strlen(s));
}

int safeOpen(const char* path, int flags, int mode) {
    return open(path, flags, mode);
}

void safeClose(int fd) {
    close(fd);
}

bool localtime(const time_t* clock, struct tm* result) {
    return localtime_r(clock, result) != nullptr;
}

bool setThreadName(const char* name) {
    return pthread_setname_np(name) == 0;
}

bool daemonize() {
    return false;
}

// ── Dynamic library ────────────────────────────────────────────────────

DynamicLib::~DynamicLib() { close(); }

DynamicLib& DynamicLib::operator=(DynamicLib&& other) noexcept {
    if (this != &other) {
        close();
        m_handle = other.m_handle;
        other.m_handle = nullptr;
    }
    return *this;
}

bool DynamicLib::open(const char* path) {
    close();
    m_handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    return m_handle != nullptr;
}

void* DynamicLib::sym(const char* name) const {
    return dlsym(m_handle, name);
}

void DynamicLib::close() {
    if (m_handle) {
        dlclose(m_handle);
        m_handle = nullptr;
    }
}

// ── Process ────────────────────────────────────────────────────────────
// iOS sandbox does not allow fork/exec. These are stubs.

bool spawnProcess(const std::string&, const std::vector<std::string>&, Pid&) {
    return false;
}

bool isProcessRunning(Pid) {
    return false;
}

bool waitProcess(Pid, int) {
    return false;
}

bool killProcess(Pid) {
    return false;
}

int processExitCode(Pid) {
    return -1;
}

} // namespace ainas::platform
