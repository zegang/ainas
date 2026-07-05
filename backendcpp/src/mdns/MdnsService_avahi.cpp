#include "ainas/mdns/MdnsService.hpp"
#include "ainas/logging/Logger.hpp"
#include "ainas/platform/Platform.hpp"

#include <avahi-client/client.h>
#include <avahi-client/publish.h>
#include <avahi-common/error.h>
#include <avahi-common/malloc.h>
#include <avahi-common/strlst.h>
#include <avahi-common/simple-watch.h>

#include <cstdint>
#include <cstring>
#include <netinet/in.h>
#include <unistd.h>

namespace ainas {

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

//===----------------------------------------------------------------------===//
//  Avahi callbacks
//===----------------------------------------------------------------------===//

void entryGroupCallback(void* g, int state, void* userdata) {
    auto* self = static_cast<MdnsService*>(userdata);
    auto* group = static_cast<AvahiEntryGroup*>(g);

    switch (static_cast<AvahiEntryGroupState>(state)) {
        case AVAHI_ENTRY_GROUP_ESTABLISHED:
            LOG_DEBUG("mDNS: Entry group established");
            break;
        case AVAHI_ENTRY_GROUP_COLLISION:
            LOG_WARN("mDNS: Name collision detected — Avahi renamed the service");
            break;
        case AVAHI_ENTRY_GROUP_FAILURE:
            LOG_ERROR("mDNS: Entry group failure: {}",
                      avahi_strerror(avahi_client_errno(avahi_entry_group_get_client(group))));
            break;
        case AVAHI_ENTRY_GROUP_UNCOMMITED:
        case AVAHI_ENTRY_GROUP_REGISTERING:
            break;
    }
}

void clientCallback(void* c, int state, void* userdata) {
    auto* self = static_cast<MdnsService*>(userdata);
    auto* client = static_cast<AvahiClient*>(c);

    switch (static_cast<AvahiClientState>(state)) {
        case AVAHI_CLIENT_S_RUNNING: {
            auto* group = static_cast<AvahiEntryGroup*>(self->m_entryGroup);

            if (!group) {
                group = avahi_entry_group_new(client,
                    reinterpret_cast<AvahiEntryGroupCallback>(entryGroupCallback), self);
                self->m_entryGroup = group;
                if (!group) {
                    LOG_ERROR("mDNS: Failed to create entry group: {}",
                              avahi_strerror(avahi_client_errno(client)));
                    break;
                }
            }

            AvahiStringList* txt = nullptr;
            for (const auto& [key, value] : self->m_txtRecords) {
                txt = avahi_string_list_add_pair(txt, key.c_str(), value.c_str());
            }

            int ret = avahi_entry_group_add_service_strlst(
                group,
                AVAHI_IF_UNSPEC,
                AVAHI_PROTO_UNSPEC,
                static_cast<AvahiPublishFlags>(0),
                self->m_serviceName.c_str(),
                "_http._tcp",
                nullptr,
                nullptr,
                self->m_port,
                txt);
            avahi_string_list_free(txt);

            if (ret < 0) {
                LOG_ERROR("mDNS: Failed to add service: {}", avahi_strerror(ret));
                avahi_entry_group_free(group);
                self->m_entryGroup = nullptr;
                break;
            }

            ret = avahi_entry_group_commit(group);
            if (ret < 0) {
                LOG_ERROR("mDNS: Failed to commit entry group: {}", avahi_strerror(ret));
            } else {
                LOG_INFO("mDNS: Publishing via Avahi on port {}", self->m_port);
            }
            break;
        }

        case AVAHI_CLIENT_FAILURE: {
            auto reason = avahi_client_errno(client);
            LOG_WARN("mDNS: Avahi client failure: {}", avahi_strerror(reason));
            if (self->m_entryGroup) {
                avahi_entry_group_free(static_cast<AvahiEntryGroup*>(self->m_entryGroup));
                self->m_entryGroup = nullptr;
            }
            avahi_client_free(client);
            self->m_client = nullptr;
            break;
        }

        case AVAHI_CLIENT_CONNECTING:
            LOG_DEBUG("mDNS: Connecting to Avahi daemon...");
            break;

        case AVAHI_CLIENT_S_COLLISION:
        case AVAHI_CLIENT_S_REGISTERING:
            break;
    }
}

//===----------------------------------------------------------------------===//
//  Start / Stop
//===----------------------------------------------------------------------===//

bool MdnsService::start() {
    if (m_running) return true;

    auto* poll = avahi_simple_poll_new();
    if (!poll) {
        LOG_ERROR("mDNS: Failed to create AvahiSimplePoll");
        return false;
    }
    m_simplePoll = poll;

    int error = 0;
    auto* client = avahi_client_new(
        avahi_simple_poll_get(poll),
        static_cast<AvahiClientFlags>(AVAHI_CLIENT_NO_FAIL),
        reinterpret_cast<AvahiClientCallback>(clientCallback),
        this,
        &error);

    if (!client) {
        LOG_ERROR("mDNS: Failed to create Avahi client: {}", avahi_strerror(error));
        avahi_simple_poll_free(poll);
        m_simplePoll = nullptr;
        return false;
    }
    m_client = client;

    m_running = true;
    m_thread = std::thread([this]() {
        auto* poll = static_cast<AvahiSimplePoll*>(m_simplePoll);
        while (m_running) {
            int ret = avahi_simple_poll_iterate(poll, 50);
            if (ret != 0 && m_running) {
                LOG_WARN("mDNS: Poll loop exited with code {}", ret);
                break;
            }
        }
    });

    return true;
}

void MdnsService::stop() {
    if (!m_running) return;
    m_running = false;

    auto* poll = static_cast<AvahiSimplePoll*>(m_simplePoll);
    if (poll) {
        avahi_simple_poll_quit(poll);
    }

    if (m_thread.joinable()) {
        m_thread.join();
    }

    if (m_entryGroup) {
        avahi_entry_group_free(static_cast<AvahiEntryGroup*>(m_entryGroup));
        m_entryGroup = nullptr;
    }

    if (m_client) {
        avahi_client_free(static_cast<AvahiClient*>(m_client));
        m_client = nullptr;
    }

    if (poll) {
        avahi_simple_poll_free(poll);
        m_simplePoll = nullptr;
    }

    LOG_INFO("mDNS: Stopped");
}

} // namespace ainas
