import socket
import logging
from zeroconf import IPVersion, ServiceInfo
from zeroconf.asyncio import AsyncZeroconf


def _get_nic_ips():
    """Return all non-loopback IPv4 addresses of this host."""
    seen = set()

    # 1) gethostbyname_ex — cheap and usually works
    try:
        _, _, addrs = socket.gethostbyname_ex(socket.gethostname())
        for a in addrs:
            if not a.startswith("127."):
                seen.add(a)
    except Exception:
        pass

    # 2) UDP trick — discovers the primary NIC IP
    if not seen:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.settimeout(0.1)
            s.connect(("8.8.8.8", 80))
            seen.add(s.getsockname()[0])
            s.close()
        except Exception:
            pass

    # 3) Last resort
    if not seen:
        seen.add("127.0.0.1")

    return sorted(seen)


class NASDiscovery:
    def __init__(self, host="0.0.0.0", port=8000):
        self.logger = logging.getLogger(__name__)
        self.aiozc = AsyncZeroconf(ip_version=IPVersion.V4Only)
        self.host = host
        self.port = port
        self.service_type = "_http._tcp.local."
        self.service_name = f"AINAS-{socket.gethostname()}.{self.service_type}"

    async def register(self):
        desc = {'version': '1.0.0', 'id': 'ai-nas-v1'}

        # Determine the IP addresses to advertise:
        #   * If the user explicitly set a non-zero address, use it.
        #   * Otherwise auto-detect all NIC IPs so clients receive a reachable IP.
        if self.host == "0.0.0.0":
            ips = _get_nic_ips()
        else:
            ips = [self.host]

        addresses = [socket.inet_aton(ip) for ip in ips]

        info = ServiceInfo(
            self.service_type,
            self.service_name,
            addresses=addresses,
            port=self.port,
            properties=desc,
            server=f"{socket.gethostname()}.",
        )
        self.logger.info("mDNS: Attempting to register service: %s", self.service_name)
        self.logger.info("mDNS: Registration details -> Type: %s, IPs: %s, Port: %s, Server: %s",
                         self.service_type, ips, self.port, info.server)

        try:
            await self.aiozc.async_register_service(info)
            self.logger.info("mDNS: Service registration successfully completed")
        except Exception as e:
            self.logger.error("mDNS: Failed to register service: %s", e, exc_info=True)

    async def unregister(self):
        self.logger.info("mDNS: Shutting down Zeroconf and unregistering all services...")
        await self.aiozc.async_unregister_all_services()
        await self.aiozc.async_close()
        self.logger.info("mDNS: Unregistration complete")
