import socket
import logging
from zeroconf import IPVersion, ServiceInfo, Zeroconf

logger = logging.getLogger(__name__)

class NASDiscovery:
    def __init__(self, host="0.0.0.0", port=8000):
        self.zeroconf = Zeroconf(ip_version=IPVersion.V4Only)
        self.host = host
        self.port = port
        self.service_type = "_http._tcp.local."
        self.service_name = f"AINAS-{socket.gethostname()}.{self.service_type}"
        
    def register(self):
        desc = {'version': '1.0.0', 'id': 'ai-nas-v1'}
        info = ServiceInfo(
            self.service_type,
            self.service_name,
            addresses=[socket.inet_aton(self.host)],
            port=self.port,
            properties=desc,
            server=f"{socket.gethostname()}.local.",
        )
        logger.info("Registering NAS service as %s...", self.service_name)
        self.zeroconf.register_service(info)

    def unregister(self):
        self.zeroconf.unregister_all_services()
        self.zeroconf.close()