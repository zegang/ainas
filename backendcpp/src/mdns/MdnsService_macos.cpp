#include "ainas/mdns/MdnsService.hpp"
#include "ainas/logging/Logger.hpp"

#include <dns_sd.h>
#include <netinet/in.h>
#include <unistd.h>

#include <cstring>

namespace ainas {

//===----------------------------------------------------------------------===//
//  Helpers
//===----------------------------------------------------------------------===//

std::string MdnsService::getHostname() {
    char buf[256];
    if (gethostname(buf, sizeof(buf)) == 0) {
        buf[sizeof(buf) - 1] = '\0';
        return buf;
    }
    return "unknown";
}

MdnsService::MdnsService(const std::string& host, uint16_t port)
    : m_host(host)
    , m_port(port)
    , m_serviceName("AINAS-" + getHostname())
    , m_poll(nullptr)
    , m_client(nullptr)
    , m_group(nullptr)
    , m_running(false)
{}

MdnsService::~MdnsService() { stop(); }

//===----------------------------------------------------------------------===//
//  Unused Avahi-compatible callbacks (required by shared header)
//===----------------------------------------------------------------------===//

void MdnsService::mdnsClientCallback(void*, int, void*) {}
void MdnsService::mdnsGroupCallback(void*, int, void*) {}

//===----------------------------------------------------------------------===//
//  Bonjour start / stop
//===----------------------------------------------------------------------===//

bool MdnsService::start() {
    if (m_running) return true;

    DNSServiceRef ref{};
    char buf[256];
    TXTRecordRef txt;
    TXTRecordCreate(&txt, sizeof(buf), buf);
    TXTRecordSetValue(&txt, "version", 5, "1.0.0");
    TXTRecordSetValue(&txt, "id", 8, "ai-nas-v1");

    auto err = DNSServiceRegister(
        &ref, 0, 0, m_serviceName.c_str(), "_http._tcp", "local.",
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
    LOG_INFO("mDNS: Publishing via Bonjour on port {}", m_port);
    return true;
}

void MdnsService::stop() {
    if (!m_running) return;
    m_running = false;
    if (m_client) {
        DNSServiceRefDeallocate(static_cast<DNSServiceRef>(m_client));
        m_client = nullptr;
    }
    LOG_INFO("mDNS: Stopped");
}

} // namespace ainas

