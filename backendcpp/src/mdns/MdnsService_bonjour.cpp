#include "ainas/mdns/MdnsService.hpp"
#include "ainas/logging/Logger.hpp"

#include <cstdint>
#include <cstring>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winsock2.h>
#else
#include <dns_sd.h>
#include <netinet/in.h>
#include <poll.h>
#include <unistd.h>
#endif

namespace ainas {

//===----------------------------------------------------------------------===//
//  Platform-specific Bonjour binding
//===----------------------------------------------------------------------===//

#ifdef _WIN32

// Minimal dns_sd types for the API we use
struct BonjourTXTRecord {
    char _private[16];
};

typedef uint32_t (*DNSServiceRegister_t)(
    void** sdRef, uint32_t flags, uint32_t interfaceIndex,
    const char* name, const char* regtype, const char* domain,
    const char* host, uint16_t port, uint16_t txtLen,
    const void* txtRecord, void* callBack, void* context);

typedef uint32_t (*DNSServiceProcessResult_t)(void* ref);
typedef void (*DNSServiceRefDeallocate_t)(void* ref);
typedef void (*TXTRecordCreate_t)(BonjourTXTRecord*, uint16_t, void*);
typedef void (*TXTRecordSetValue_t)(BonjourTXTRecord*, const char*, uint8_t, const void*);
typedef uint16_t (*TXTRecordGetLength_t)(const BonjourTXTRecord*);
typedef const void* (*TXTRecordGetBytesPtr_t)(const BonjourTXTRecord*);
typedef void (*TXTRecordDeallocate_t)(BonjourTXTRecord*);

struct BonjourApi {
    HMODULE dll;
    DNSServiceRegister_t DNSServiceRegister;
    DNSServiceProcessResult_t DNSServiceProcessResult;
    DNSServiceRefDeallocate_t DNSServiceRefDeallocate;
    TXTRecordCreate_t TXTRecordCreate;
    TXTRecordSetValue_t TXTRecordSetValue;
    TXTRecordGetLength_t TXTRecordGetLength;
    TXTRecordGetBytesPtr_t TXTRecordGetBytesPtr;
    TXTRecordDeallocate_t TXTRecordDeallocate;

    bool load() {
        dll = LoadLibraryA("dnssd.dll");
        if (!dll) return false;

        DNSServiceRegister = reinterpret_cast<DNSServiceRegister_t>(
            GetProcAddress(dll, "DNSServiceRegister"));
        DNSServiceProcessResult = reinterpret_cast<DNSServiceProcessResult_t>(
            GetProcAddress(dll, "DNSServiceProcessResult"));
        DNSServiceRefDeallocate = reinterpret_cast<DNSServiceRefDeallocate_t>(
            GetProcAddress(dll, "DNSServiceRefDeallocate"));
        TXTRecordCreate = reinterpret_cast<TXTRecordCreate_t>(
            GetProcAddress(dll, "TXTRecordCreate"));
        TXTRecordSetValue = reinterpret_cast<TXTRecordSetValue_t>(
            GetProcAddress(dll, "TXTRecordSetValue"));
        TXTRecordGetLength = reinterpret_cast<TXTRecordGetLength_t>(
            GetProcAddress(dll, "TXTRecordGetLength"));
        TXTRecordGetBytesPtr = reinterpret_cast<TXTRecordGetBytesPtr_t>(
            GetProcAddress(dll, "TXTRecordGetBytesPtr"));
        TXTRecordDeallocate = reinterpret_cast<TXTRecordDeallocate_t>(
            GetProcAddress(dll, "TXTRecordDeallocate"));

        if (!DNSServiceRegister || !DNSServiceProcessResult || !DNSServiceRefDeallocate) {
            FreeLibrary(dll);
            dll = nullptr;
            return false;
        }
        return true;
    }

    void unload() {
        if (dll) {
            FreeLibrary(dll);
            dll = nullptr;
        }
    }
};

static BonjourApi s_bonjour;
#define kDNSServiceErr_NoError 0

#endif

//===----------------------------------------------------------------------===//
//  Hostname helper
//===----------------------------------------------------------------------===//

std::string MdnsService::getHostname() {
    char buf[256];
#ifdef _WIN32
    DWORD size = sizeof(buf);
    if (GetComputerNameA(buf, &size)) {
        buf[sizeof(buf) - 1] = '\0';
        return buf;
    }
#else
    if (gethostname(buf, sizeof(buf)) == 0) {
        buf[sizeof(buf) - 1] = '\0';
        return buf;
    }
#endif
    return "unknown";
}

//===----------------------------------------------------------------------===//
//  Constructor / Destructor
//===----------------------------------------------------------------------===//

MdnsService::MdnsService(const std::string& host, uint16_t port)
    : m_host(host)
    , m_port(port)
    , m_serviceName("AINAS-" + getHostname())
    , m_client(nullptr)
    , m_running(false)
{}

MdnsService::~MdnsService() { stop(); }

//===----------------------------------------------------------------------===//
//  Start / Stop
//===----------------------------------------------------------------------===//

bool MdnsService::start() {
    if (m_running) return true;

#ifdef _WIN32
    if (!s_bonjour.load()) {
        LOG_WARN("mDNS: Bonjour not available (dnssd.dll not found)");
        return false;
    }

    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);

    void* ref = nullptr;
    BonjourTXTRecord txt;
    char buf[256];
    s_bonjour.TXTRecordCreate(&txt, sizeof(buf), buf);
    s_bonjour.TXTRecordSetValue(&txt, "version", 5, "1.0.0");
    s_bonjour.TXTRecordSetValue(&txt, "id", 8, "ai-nas-v1");

    auto err = s_bonjour.DNSServiceRegister(
        &ref, 0, 0,
        m_serviceName.c_str(), "_http._tcp", "local.",
        nullptr, htons(m_port),
        s_bonjour.TXTRecordGetLength(&txt),
        s_bonjour.TXTRecordGetBytesPtr(&txt),
        nullptr, nullptr);
    s_bonjour.TXTRecordDeallocate(&txt);

    if (err != kDNSServiceErr_NoError) {
        LOG_ERROR("mDNS: Bonjour registration failed: {}", static_cast<int>(err));
        WSACleanup();
        s_bonjour.unload();
        return false;
    }
    m_client = ref;
    m_running = true;

    m_thread = std::thread([this]() {
        while (m_running) {
            auto ret = s_bonjour.DNSServiceProcessResult(m_client);
            if (ret != kDNSServiceErr_NoError) break;
        }
    });

    LOG_INFO("mDNS: Publishing via Bonjour (Windows) on port {}", m_port);
    return true;

#else
    DNSServiceRef ref{};
    char buf[256];
    TXTRecordRef txt;
    TXTRecordCreate(&txt, sizeof(buf), buf);
    TXTRecordSetValue(&txt, "version", 5, "1.0.0");
    TXTRecordSetValue(&txt, "id", 8, "ai-nas-v1");

    auto err = DNSServiceRegister(
        &ref, 0, 0,
        m_serviceName.c_str(), "_http._tcp", "local.",
        nullptr, htons(m_port),
        TXTRecordGetLength(&txt), TXTRecordGetBytesPtr(&txt),
        nullptr, nullptr);
    TXTRecordDeallocate(&txt);

    if (err != kDNSServiceErr_NoError) {
        LOG_ERROR("mDNS: Bonjour registration failed: {}", static_cast<int>(err));
        return false;
    }
    m_client = ref;
    m_running = true;

    m_thread = std::thread([this]() {
        auto sdRef = static_cast<DNSServiceRef>(m_client);
        int sockFd = DNSServiceRefSockFD(sdRef);
        struct pollfd pfd = {sockFd, POLLIN, 0};
        while (m_running) {
            int ret = poll(&pfd, 1, 500);
            if (ret > 0 && m_running) {
                DNSServiceProcessResult(sdRef);
            }
        }
    });

    LOG_INFO("mDNS: Publishing via Bonjour on port {}", m_port);
    return true;
#endif
}

void MdnsService::stop() {
    if (!m_running) return;
    m_running = false;
    if (m_thread.joinable()) {
        m_thread.join();
    }
    if (m_client) {
#ifdef _WIN32
        s_bonjour.DNSServiceRefDeallocate(m_client);
        WSACleanup();
        s_bonjour.unload();
#else
        DNSServiceRefDeallocate(static_cast<DNSServiceRef>(m_client));
#endif
        m_client = nullptr;
    }
    LOG_INFO("mDNS: Stopped");
}

} // namespace ainas
