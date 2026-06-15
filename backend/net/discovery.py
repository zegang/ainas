import socket
import logging
from zeroconf import IPVersion, ServiceInfo
from zeroconf.asyncio import AsyncZeroconf

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
        info = ServiceInfo(
            self.service_type,
            self.service_name,
            addresses=[socket.inet_aton(self.host)],
            port=self.port,
            properties=desc,
            server=f"{socket.gethostname()}.ainas.local.",
        )
        self.logger.info("mDNS: Attempting to register service: %s", self.service_name)
        self.logger.info("mDNS: Registration details -> Type: %s, Host: %s, Port: %s, Server: %s", 
                         self.service_type, self.host, self.port, info.server)
        
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
