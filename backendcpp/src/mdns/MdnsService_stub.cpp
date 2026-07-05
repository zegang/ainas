#include "ainas/mdns/MdnsService.hpp"
#include "ainas/logging/Logger.hpp"
#include "ainas/platform/Platform.hpp"

#ifdef _WIN32
#include <winsock2.h>
#pragma comment(lib, "ws2_32.lib")
#endif

namespace ainas {

//===----------------------------------------------------------------------===//
//  Helpers
//===----------------------------------------------------------------------===//

std::string MdnsService::getHostname() {
    return ainas::platform::hostname();
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
