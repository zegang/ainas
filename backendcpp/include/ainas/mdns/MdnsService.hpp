#pragma once

#include <atomic>
#include <string>
#include <thread>

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
    static void mdnsClientCallback(void* c, int state, void* userdata);
    static void mdnsGroupCallback(void* g, int state, void* userdata);

    std::string m_host;
    uint16_t m_port;
    std::string m_serviceName;

    void* m_poll;
    void* m_client;
    void* m_group;

    std::thread m_thread;
    std::atomic<bool> m_running;
};

} // namespace ainas
