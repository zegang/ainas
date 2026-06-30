#pragma once

#include <atomic>
#include <string>

namespace ainas {

class MdnsService {
public:
    MdnsService(const std::string& host, uint16_t port);
    ~MdnsService();

    MdnsService(const MdnsService&) = delete;
    MdnsService& operator=(const MdnsService&) = delete;

    bool start();
    void stop();

private:
    static std::string getHostname();

    std::string m_host;
    uint16_t m_port;
    std::string m_serviceName;

    void* m_client;
    std::atomic<bool> m_running;
};

} // namespace ainas
