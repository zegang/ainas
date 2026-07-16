#include "ainas/lic/lic.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <comdef.h>
#include <Wbemidl.h>
#include <oleauto.h>

#include <string>
#include <sstream>
#include <vector>

#pragma comment(lib, "wbemuuid.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "oleaut32.lib")

namespace ainas::lic {
namespace {

// RAII COM initializer
class ComInit {
public:
    ComInit() : ok_(CoInitializeEx(nullptr, COINIT_MULTITHREADED) == S_OK) {}
    ~ComInit() { if (ok_) CoUninitialize(); }
    explicit operator bool() const { return ok_; }
private:
    bool ok_;
};

// RAII for IWbemLocator
class WbemLocator {
public:
    WbemLocator() : ptr_(nullptr) {
        CoCreateInstance(CLSID_WbemLocator, nullptr, CLSCTX_INPROC_SERVER,
                         IID_IWbemLocator, reinterpret_cast<void**>(&ptr_));
    }
    ~WbemLocator() { if (ptr_) ptr_->Release(); }
    IWbemLocator* get() const { return ptr_; }
    explicit operator bool() const { return ptr_ != nullptr; }
private:
    IWbemLocator* ptr_;
};

// RAII for IWbemServices
class WbemServices {
public:
    WbemServices() : ptr_(nullptr) {}
    ~WbemServices() { if (ptr_) ptr_->Release(); }
    IWbemServices** operator&() { return &ptr_; }
    IWbemServices* get() const { return ptr_; }
    explicit operator bool() const { return ptr_ != nullptr; }
private:
    IWbemServices* ptr_;
};

// RAII for IEnumWbemClassObject
class WbemEnumerator {
public:
    WbemEnumerator() : ptr_(nullptr) {}
    ~WbemEnumerator() { if (ptr_) ptr_->Release(); }
    IEnumWbemClassObject** operator&() { return &ptr_; }
    IEnumWbemClassObject* get() const { return ptr_; }
    explicit operator bool() const { return ptr_ != nullptr; }
private:
    IEnumWbemClassObject* ptr_;
};

// RAII for BSTR
class Bstr {
public:
    explicit Bstr(const wchar_t* s) : s_(SysAllocString(s)) {}
    ~Bstr() { if (s_) SysFreeString(s_); }
    BSTR get() const { return s_; }
    explicit operator bool() const { return s_ != nullptr; }
private:
    BSTR s_;
};

// RAII for VARIANT
class Var {
public:
    Var() { VariantInit(&v_); }
    ~Var() { VariantClear(&v_); }
    VARIANT* operator&() { return &v_; }
    const VARIANT& get() const { return v_; }
    std::string toString() const {
        if (v_.vt == VT_BSTR && v_.bstrVal) {
            char buf[256];
            WideCharToMultiByte(CP_UTF8, 0, v_.bstrVal, -1, buf, sizeof(buf), nullptr, nullptr);
            return buf;
        }
        return {};
    }
private:
    VARIANT v_;
};

std::string wmiQuerySingle(const wchar_t* query, const wchar_t* prop) {
    ComInit com;
    if (!com) return {};

    WbemLocator locator;
    if (!locator) return {};

    WbemServices services;
    Bstr wmiNamespace(L"ROOT\\CIMV2");
    if (!wmiNamespace) return {};

    HRESULT hr = locator.get()->ConnectServer(
        wmiNamespace.get(), nullptr, nullptr, nullptr, 0, nullptr,
        nullptr, &services);
    if (FAILED(hr) || !services) return {};

    hr = CoSetProxyBlanket(services.get(), RPC_C_AUTHN_WINNT,
                           RPC_C_AUTHZ_NONE, nullptr, RPC_C_AUTHN_LEVEL_CALL,
                           RPC_C_IMP_LEVEL_IMPERSONATE, nullptr,
                           EOAC_NONE);
    if (FAILED(hr)) return {};

    WbemEnumerator enumerator;
    Bstr wmiQuery(query);
    if (!wmiQuery) return {};

    hr = services.get()->ExecQuery(
        Bstr(L"WQL").get(), wmiQuery.get(),
        WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY,
        nullptr, &enumerator);
    if (FAILED(hr) || !enumerator) return {};

    IWbemClassObject* obj = nullptr;
    ULONG returned = 0;
    hr = enumerator.get()->Next(WBEM_INFINITE, 1, &obj, &returned);
    if (FAILED(hr) || returned == 0 || !obj) return {};

    Var val;
    Bstr propName(prop);
    hr = obj->Get(propName.get(), 0, &val, nullptr, nullptr);
    obj->Release();

    if (FAILED(hr)) return {};

    auto result = val.toString();
    // Filter out placeholder values
    if (result.find("O.E.M") != std::string::npos ||
        result.find("Default") != std::string::npos ||
        result.find("To be filled") != std::string::npos)
        return {};

    return result;
}

} // anonymous namespace

std::string getCpuSerial() {
    auto serial = wmiQuerySingle(
        L"SELECT ProcessorId FROM Win32_Processor",
        L"ProcessorId");
    if (!serial.empty()) return serial;

    // Fallback: build a composite from other CPU properties
    auto name = wmiQuerySingle(
        L"SELECT Name FROM Win32_Processor",
        L"Name");
    auto id = wmiQuerySingle(
        L"SELECT ProcessorId FROM Win32_Processor WHERE ProcessorType=3",
        L"ProcessorId");
    if (!id.empty()) return name + "::" + id;
    return name;
}

std::string getMotherboardSerial() {
    return wmiQuerySingle(
        L"SELECT SerialNumber FROM Win32_BaseBoard",
        L"SerialNumber");
}

std::string getDiskSerial() {
    return wmiQuerySingle(
        L"SELECT SerialNumber FROM Win32_DiskDrive WHERE Index=0",
        L"SerialNumber");
}

} // namespace ainas::lic
