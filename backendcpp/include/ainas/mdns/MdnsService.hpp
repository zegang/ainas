#pragma once

#include <atomic>
#include <map>
#include <string>
#include <thread>
#include <vector>

namespace ainas {

class MdnsService {
public:
    MdnsService(const std::string& host, uint16_t port);
    ~MdnsService();

    MdnsService(const MdnsService&) = delete;
    MdnsService& operator=(const MdnsService&) = delete;

    bool start();
    void stop();

    void setTxtRecord(const std::string& key, const std::string& value);
    void removeTxtRecord(const std::string& key);
    void clearTxtRecords();
    const std::map<std::string, std::string>& getTxtRecords() const;

private:
    static std::string getHostname();

    template <typename TXTRecordT, typename SetFn>
    void buildTxtRecord(TXTRecordT& txt, char* buf, size_t bufSize, SetFn setValue) const;

    friend void clientCallback(void*, int, void*);
    friend void entryGroupCallback(void*, int, void*);

    std::string m_host;
    uint16_t m_port;
    std::string m_serviceName;

    std::map<std::string, std::string> m_txtRecords;

    void* m_client;       // DNSServiceRef (Bonjour) or AvahiClient*
    void* m_entryGroup;   // AvahiEntryGroup* (Avahi native only)
    void* m_simplePoll;   // AvahiSimplePoll* (Avahi native only)
    std::atomic<bool> m_running;
    std::thread m_thread;
};

} // namespace ainas
