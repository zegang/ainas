#ifndef AINAS_WINDOWS_COMPAT_HPP
#define AINAS_WINDOWS_COMPAT_HPP

#ifdef _WIN32

#ifndef WINVER
#define WINVER 0x0601
#endif

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601
#endif

#ifndef _WIN32_IE
#define _WIN32_IE 0x0800
#endif

#ifndef NTDDI_VERSION
#define NTDDI_VERSION 0x06010000
#endif

#include <windows.h>
#include <string>

namespace ainas::compat {

inline bool isApiAvailable(const wchar_t* dll, const char* api) {
    auto mod = GetModuleHandleW(dll);
    if (!mod) return false;
    return GetProcAddress(mod, api) != nullptr;
}

inline bool copyFile(const wchar_t* existing, const wchar_t* target,
                      BOOL failIfExists) {
    static auto pCopyFile2 = reinterpret_cast<HRESULT(WINAPI*)(LPVOID)>(
        GetProcAddress(GetModuleHandleW(L"KERNEL32"), "CopyFile2"));
    if (pCopyFile2) {
        COPYFILE2_EXTENDED_PARAMETERS params = {sizeof(COPYFILE2_EXTENDED_PARAMETERS)};
        params.dwCopyFlags = failIfExists ? COPY_FILE_FAIL_IF_EXISTS : 0;
        params.pwszSource = existing;
        params.pwszTarget = target;
        return SUCCEEDED(pCopyFile2(&params));
    }
    return CopyFileExW(existing, target, nullptr, nullptr, nullptr,
                       failIfExists ? COPY_FILE_FAIL_IF_EXISTS : 0) != 0;
}

} // namespace ainas::compat

#endif // _WIN32
#endif // AINAS_WINDOWS_COMPAT_HPP
