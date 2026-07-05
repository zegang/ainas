#include "ainas/platform/Platform.hpp"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <errhandlingapi.h>
#include <handleapi.h>
#include <processthreadsapi.h>
#include <synchapi.h>
#include <fcntl.h>
#include <io.h>
#include <process.h>

#include <cstdlib>
#include <cstring>
#include <filesystem>

namespace ainas::platform {

std::string hostname() {
    char buf[256];
    DWORD size = sizeof(buf);
    if (GetComputerNameA(buf, &size)) {
        buf[sizeof(buf) - 1] = '\0';
        return buf;
    }
    return "unknown";
}

std::string executablePath() {
    char exePath[MAX_PATH];
    DWORD len = GetModuleFileNameA(nullptr, exePath, MAX_PATH);
    if (len > 0) return std::filesystem::path(exePath).string();
    return {};
}

bool setEnv(const char* name, const char* value) {
    return _putenv_s(name, value) == 0;
}

std::string getEnv(const char* name) {
    DWORD len = GetEnvironmentVariableA(name, nullptr, 0);
    if (len == 0) return {};
    std::string buf(len, '\0');
    len = GetEnvironmentVariableA(name, buf.data(), static_cast<DWORD>(buf.size()));
    if (len > 0) {
        buf.resize(len);
        return buf;
    }
    return {};
}

void safeWrite(int fd, const char* s) {
    _write(fd, s, static_cast<unsigned>(std::strlen(s)));
}

int safeOpen(const char* path, int flags, int mode) {
    return _open(path, flags, mode);
}

void safeClose(int fd) {
    _close(fd);
}

bool localtime(const time_t* clock, struct tm* result) {
    return localtime_s(result, clock) == 0;
}

bool setThreadName(const char* name) {
    // Windows: use SetThreadDescription (Windows 10 1607+)
    wchar_t wbuf[128];
    int len = MultiByteToWideChar(CP_UTF8, 0, name, -1, wbuf,
                                  static_cast<int>(std::size(wbuf)));
    if (len <= 0) return false;
    HRESULT hr = SetThreadDescription(GetCurrentThread(), wbuf);
    return SUCCEEDED(hr);
}

bool daemonize() {
    // Daemonization not supported on Windows — run as a service instead
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
    m_handle = LoadLibraryA(path);
    return m_handle != nullptr;
}

void* DynamicLib::sym(const char* name) const {
    return reinterpret_cast<void*>(GetProcAddress(
        static_cast<HMODULE>(m_handle), name));
}

void DynamicLib::close() {
    if (m_handle) {
        FreeLibrary(static_cast<HMODULE>(m_handle));
        m_handle = nullptr;
    }
}

// ── Process ────────────────────────────────────────────────────────────

bool spawnProcess(const std::string& path,
                  const std::vector<std::string>& args,
                  Pid& outPid) {
    std::string cmdline = "\"" + path + "\"";
    for (const auto& a : args) {
        cmdline += " \"" + a + "\"";
    }

    STARTUPINFOA si{};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi{};

    if (!CreateProcessA(nullptr, cmdline.data(), nullptr, nullptr, FALSE,
                        CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi)) {
        return false;
    }

    CloseHandle(pi.hThread);
    outPid = static_cast<Pid>(pi.dwProcessId);
    // Store handle for wait/kill operations via a static map
    // For now we use pid-based lookup with OpenProcess
    CloseHandle(pi.hProcess);
    return true;
}

bool isProcessRunning(Pid pid) {
    HANDLE h = OpenProcess(PROCESS_QUERY_INFORMATION, FALSE,
                           static_cast<DWORD>(pid));
    if (!h) return false;
    DWORD exitCode;
    bool running = (GetExitCodeProcess(h, &exitCode) && exitCode == STILL_ACTIVE);
    CloseHandle(h);
    return running;
}

bool waitProcess(Pid pid, int timeoutMs) {
    HANDLE h = OpenProcess(SYNCHRONIZE, FALSE, static_cast<DWORD>(pid));
    if (!h) return false;
    DWORD ms = (timeoutMs < 0) ? INFINITE : static_cast<DWORD>(timeoutMs);
    DWORD ret = WaitForSingleObject(h, ms);
    CloseHandle(h);
    return ret == WAIT_OBJECT_0;
}

bool killProcess(Pid pid) {
    HANDLE h = OpenProcess(PROCESS_TERMINATE, FALSE, static_cast<DWORD>(pid));
    if (!h) return false;
    bool ok = TerminateProcess(h, 0) != 0;
    CloseHandle(h);
    return ok;
}

int processExitCode(Pid pid) {
    HANDLE h = OpenProcess(PROCESS_QUERY_INFORMATION, FALSE,
                           static_cast<DWORD>(pid));
    if (!h) return -1;
    DWORD exitCode;
    if (!GetExitCodeProcess(h, &exitCode)) {
        CloseHandle(h);
        return -1;
    }
    CloseHandle(h);
    return static_cast<int>(exitCode);
}

} // namespace ainas::platform
