#include "ainas/platform/Platform.hpp"

#include <cerrno>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <system_error>

#include <fcntl.h>
#include <unistd.h>
#include <dlfcn.h>
#include <sys/prctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>

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
    std::error_code ec;
    auto p = std::filesystem::canonical("/proc/self/exe", ec);
    if (!ec) return p.string();
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
    return prctl(PR_SET_NAME, name, 0, 0, 0) == 0;
}

bool daemonize() {
    pid_t pid = fork();
    if (pid < 0) return false;
    if (pid > 0) _exit(EXIT_SUCCESS);

    if (setsid() < 0) return false;

    signal(SIGHUP, SIG_IGN);

    pid = fork();
    if (pid < 0) return false;
    if (pid > 0) _exit(EXIT_SUCCESS);

    int fd = open("/dev/null", O_RDWR);
    if (fd >= 0) {
        dup2(fd, STDIN_FILENO);
        dup2(fd, STDOUT_FILENO);
        dup2(fd, STDERR_FILENO);
        if (fd > 2) close(fd);
    }
    return true;
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

bool spawnProcess(const std::string& path,
                  const std::vector<std::string>& args,
                  Pid& outPid) {
    pid_t pid = fork();
    if (pid == -1) return false;

    if (pid == 0) {
        setpgid(0, 0);
        std::vector<const char*> argv;
        argv.reserve(args.size() + 1);
        argv.push_back(path.c_str());
        for (const auto& a : args) argv.push_back(a.c_str());
        argv.push_back(nullptr);

        execvp(path.c_str(), const_cast<char* const*>(argv.data()));
        _exit(1);
    }

    outPid = static_cast<Pid>(pid);
    return true;
}

bool isProcessRunning(Pid pid) {
    return kill(static_cast<pid_t>(pid), 0) == 0;
}

bool waitProcess(Pid pid, int timeoutMs) {
    if (timeoutMs < 0) {
        int status;
        return waitpid(static_cast<pid_t>(pid), &status, 0) == static_cast<pid_t>(pid);
    }

    auto deadline = std::chrono::steady_clock::now()
                    + std::chrono::milliseconds(timeoutMs);
    while (std::chrono::steady_clock::now() < deadline) {
        int status;
        pid_t ret = waitpid(static_cast<pid_t>(pid), &status, WNOHANG);
        if (ret == static_cast<pid_t>(pid)) return true;
        if (ret == -1) return false;
        usleep(10'000);
    }
    return false;
}

bool killProcess(Pid pid) {
    if (kill(static_cast<pid_t>(pid), SIGTERM) != 0) return false;

    for (int i = 0; i < 50; ++i) {
        if (kill(static_cast<pid_t>(pid), 0) != 0) return true;
        usleep(100'000);
    }
    kill(static_cast<pid_t>(pid), SIGKILL);
    return true;
}

int processExitCode(Pid pid) {
    int status;
    if (waitpid(static_cast<pid_t>(pid), &status, WNOHANG) == static_cast<pid_t>(pid)) {
        if (WIFEXITED(status)) return WEXITSTATUS(status);
    }
    return -1;
}

} // namespace ainas::platform
