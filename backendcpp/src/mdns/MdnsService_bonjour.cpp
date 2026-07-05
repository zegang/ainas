#include "ainas/mdns/MdnsService.hpp"
#include "ainas/logging/Logger.hpp"
#include "ainas/platform/Platform.hpp"

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
    return ainas::platform::hostname();
}

//===----------------------------------------------------------------------===//
//  Constructor / Destructor
//===----------------------------------------------------------------------===//

MdnsService::MdnsService(const std::string& host, uint16_t port)
    : m_host(host)
    , m_port(port)
    , m_serviceName("AiNAS on " + getHostname())
    , m_client(nullptr)
    , m_entryGroup(nullptr)
    , m_simplePoll(nullptr)
    , m_running(false)
{
    m_txtRecords["version"] = "0.0.1";
    m_txtRecords["id"] = "ainas";
}

MdnsService::~MdnsService() { stop(); }

//===----------------------------------------------------------------------===//
//  TXT record management
//===----------------------------------------------------------------------===//

void MdnsService::setTxtRecord(const std::string& key, const std::string& value) {
    m_txtRecords[key] = value;
}

void MdnsService::removeTxtRecord(const std::string& key) {
    m_txtRecords.erase(key);
}

void MdnsService::clearTxtRecords() {
    m_txtRecords.clear();
}

const std::map<std::string, std::string>& MdnsService::getTxtRecords() const {
    return m_txtRecords;
}

#ifdef _WIN32
// Free-function wrappers around the dynamically-loaded Bonjour API,
// so the buildTxtRecord template compiles on Windows where dns_sd.h
// is not available.
inline void TXTRecordCreate(BonjourTXTRecord* t, uint16_t s, void* b) {
    s_bonjour.TXTRecordCreate(t, s, b);
}
inline uint16_t TXTRecordGetLength(const BonjourTXTRecord* t) {
    return s_bonjour.TXTRecordGetLength(t);
}
inline const void* TXTRecordGetBytesPtr(const BonjourTXTRecord* t) {
    return s_bonjour.TXTRecordGetBytesPtr(t);
}
inline void TXTRecordDeallocate(BonjourTXTRecord* t) {
    s_bonjour.TXTRecordDeallocate(t);
}
#endif

template <typename TXTRecordT, typename SetFn>
void MdnsService::buildTxtRecord(TXTRecordT& txt, char* buf, size_t bufSize, SetFn setValue) const {
    TXTRecordCreate(&txt, static_cast<uint16_t>(bufSize), buf);
    for (const auto& [key, value] : m_txtRecords) {
        setValue(&txt, key.c_str(), static_cast<uint8_t>(value.size()), value.c_str());
    }
}

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
    buildTxtRecord(txt, buf, sizeof(buf), [this](auto* r, const char* k, uint8_t v, const void* d) {
        s_bonjour.TXTRecordSetValue(r, k, v, d);
    });

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
    buildTxtRecord(txt, buf, sizeof(buf), [](auto* r, const char* k, uint8_t v, const void* d) {
        TXTRecordSetValue(r, k, v, d);
    });

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
