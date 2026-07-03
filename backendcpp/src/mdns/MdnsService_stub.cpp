#include "ainas/mdns/MdnsService.hpp"
#include "ainas/logging/Logger.hpp"

#ifdef _WIN32
#include <winsock2.h>
#pragma comment(lib, "ws2_32.lib")
#else
#include <unistd.h>
#endif

namespace ainas {

//===----------------------------------------------------------------------===//
//  Helpers
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

MdnsService::MdnsService(const std::string& host, uint16_t port)
    : m_host(host)
    , m_port(port)
    , m_serviceName("AiNAS on " + getHostname())
    , m_poll(nullptr)
    , m_client(nullptr)
    , m_group(nullptr)
    , m_running(false)
{}

MdnsService::~MdnsService() { stop(); }

void MdnsService::mdnsClientCallback(void*, int, void*) {}
void MdnsService::mdnsGroupCallback(void*, int, void*) {}

//===----------------------------------------------------------------------===//
//  Stub start / stop
//===----------------------------------------------------------------------===//

bool MdnsService::start() {
    LOG_WARN("mDNS: Not available on this platform");
    return false;
}

void MdnsService::stop() {}

} // namespace ainas
