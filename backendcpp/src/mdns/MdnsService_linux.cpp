#include "ainas/mdns/MdnsService.hpp"
#include "ainas/logging/Logger.hpp"

#include <avahi-client/client.h>
#include <avahi-client/publish.h>
#include <avahi-common/alternative.h>
#include <avahi-common/error.h>
#include <avahi-common/malloc.h>
#include <avahi-common/simple-watch.h>
#include <avahi-common/strlst.h>

#include <unistd.h>

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
//  Avahi callbacks (static private methods → can access private members)
//===----------------------------------------------------------------------===//

void MdnsService::mdnsGroupCallback(void* g_, int state_, void* userdata) {
    auto* g = static_cast<AvahiEntryGroup*>(g_);
    auto state = static_cast<AvahiEntryGroupState>(state_);
    auto* self = static_cast<MdnsService*>(userdata);
    if (!self) return;

    switch (state) {
        case AVAHI_ENTRY_GROUP_ESTABLISHED:
            LOG_INFO("mDNS: Service '{}' registered", self->m_serviceName);
            break;
        case AVAHI_ENTRY_GROUP_COLLISION:
            if (auto* alt = avahi_alternative_service_name(self->m_serviceName.c_str())) {
                LOG_WARN("mDNS: Collision, switching to '{}'", alt);
                self->m_serviceName = alt;
                avahi_free(alt);
            }
            avahi_entry_group_reset(g);
            break;
        case AVAHI_ENTRY_GROUP_FAILURE:
            LOG_ERROR("mDNS: Group failure: {}",
                      avahi_strerror(avahi_client_errno(avahi_entry_group_get_client(g))));
            avahi_simple_poll_quit(static_cast<AvahiSimplePoll*>(self->m_poll));
            break;
        default:
            break;
    }
}

void MdnsService::mdnsClientCallback(void* c_, int state_, void* userdata) {
    auto* c = static_cast<AvahiClient*>(c_);
    auto state = static_cast<AvahiClientState>(state_);
    auto* self = static_cast<MdnsService*>(userdata);
    if (!self) return;

    switch (state) {
        case AVAHI_CLIENT_S_RUNNING: {
            auto* group = static_cast<AvahiEntryGroup*>(self->m_group);
            if (!group) {
                group = avahi_entry_group_new(c, [](AvahiEntryGroup* g, AvahiEntryGroupState st, void* ud) {
                    MdnsService::mdnsGroupCallback(g, static_cast<int>(st), ud);
                }, self);
                if (!group) {
                    LOG_ERROR("mDNS: Failed to create entry group: {}",
                              avahi_strerror(avahi_client_errno(c)));
                    break;
                }
                self->m_group = group;
            }
            if (!avahi_entry_group_is_empty(group)) break;

            LOG_INFO("mDNS: Registering '{}' port {}", self->m_serviceName, self->m_port);
            auto* txt = avahi_string_list_add_pair(
                avahi_string_list_add_pair(nullptr, "version", "1.0.0"),
                "id", "ai-nas-v1");
            auto ret = avahi_entry_group_add_service_strlst(
                group, AVAHI_IF_UNSPEC, AVAHI_PROTO_UNSPEC, AvahiPublishFlags{},
                self->m_serviceName.c_str(), "_http._tcp",
                nullptr, nullptr, self->m_port, txt);
            avahi_string_list_free(txt);
            if (ret < 0) {
                LOG_ERROR("mDNS: add_service: {}", avahi_strerror(avahi_client_errno(c)));
                avahi_entry_group_free(group);
                self->m_group = nullptr;
            } else if (avahi_entry_group_commit(group) < 0) {
                LOG_ERROR("mDNS: commit: {}", avahi_strerror(avahi_client_errno(c)));
            }
            break;
        }
        case AVAHI_CLIENT_FAILURE:
            LOG_ERROR("mDNS: Avahi failure: {}", avahi_strerror(avahi_client_errno(c)));
            avahi_simple_poll_quit(static_cast<AvahiSimplePoll*>(self->m_poll));
            break;
        case AVAHI_CLIENT_S_COLLISION:
            if (self->m_group) {
                avahi_entry_group_free(static_cast<AvahiEntryGroup*>(self->m_group));
                self->m_group = nullptr;
            }
            [[fallthrough]];
        case AVAHI_CLIENT_S_REGISTERING:
            if (self->m_group)
                avahi_entry_group_reset(static_cast<AvahiEntryGroup*>(self->m_group));
            break;
        default:
            break;
    }
}

//===----------------------------------------------------------------------===//
//  start / stop
//===----------------------------------------------------------------------===//

bool MdnsService::start() {
    if (m_running) return true;

    m_poll = avahi_simple_poll_new();
    if (!m_poll) {
        LOG_ERROR("mDNS: Failed to create poll");
        return false;
    }

    m_client = avahi_client_new(
        avahi_simple_poll_get(static_cast<AvahiSimplePoll*>(m_poll)),
        AVAHI_CLIENT_NO_FAIL, [](AvahiClient* c, AvahiClientState st, void* ud) {
            MdnsService::mdnsClientCallback(c, static_cast<int>(st), ud);
        }, this, nullptr);
    if (!m_client) {
        LOG_ERROR("mDNS: Failed to create Avahi client");
        avahi_simple_poll_free(static_cast<AvahiSimplePoll*>(m_poll));
        m_poll = nullptr;
        return false;
    }

    m_running = true;
    m_thread = std::thread([this]() {
        avahi_simple_poll_loop(static_cast<AvahiSimplePoll*>(m_poll));
    });
    return true;
}

void MdnsService::stop() {
    if (!m_running) return;
    m_running = false;

    if (m_poll) avahi_simple_poll_quit(static_cast<AvahiSimplePoll*>(m_poll));
    if (m_thread.joinable()) m_thread.join();

    if (m_group) {
        avahi_entry_group_free(static_cast<AvahiEntryGroup*>(m_group));
        m_group = nullptr;
    }
    if (m_client) {
        avahi_client_free(static_cast<AvahiClient*>(m_client));
        m_client = nullptr;
    }
    if (m_poll) {
        avahi_simple_poll_free(static_cast<AvahiSimplePoll*>(m_poll));
        m_poll = nullptr;
    }
    LOG_INFO("mDNS: Stopped");
}

} // namespace ainas
