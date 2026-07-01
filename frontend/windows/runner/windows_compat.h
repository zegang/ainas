#ifndef WINDOWS_COMPAT_H
#define WINDOWS_COMPAT_H

#include <windows.h>
#include <string>

/// Dynamically loads CopyFile2 from KERNEL32 (Windows 8+) with a fallback
/// to CopyFileEx for older systems (Windows 7).
inline BOOL CompatCopyFile(const wchar_t* existing, const wchar_t* target,
                            BOOL failIfExists) {
  static auto pCopyFile2 = reinterpret_cast<HRESULT(WINAPI*)(LPVOID)>(
      GetProcAddress(GetModuleHandleW(L"KERNEL32"), "CopyFile2"));
  if (pCopyFile2) {
    COPYFILE2_EXTENDED_PARAMETERS params = {
        sizeof(COPYFILE2_EXTENDED_PARAMETERS)};
    params.dwCopyFlags = failIfExists ? COPY_FILE_FAIL_IF_EXISTS : 0;
    params.pwszSource = existing;
    params.pwszTarget = target;
    return SUCCEEDED(pCopyFile2(&params));
  }
  return CopyFileExW(existing, target, nullptr, nullptr, nullptr,
                     failIfExists ? COPY_FILE_FAIL_IF_EXISTS : 0);
}

#endif  // WINDOWS_COMPAT_H
