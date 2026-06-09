import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logging/logging.dart';
import 'package:multicast_dns/multicast_dns.dart';
import '../features/home/domain/models/nas_server.dart';

class MdnsService {
  static final _log = Logger('MdnsService');

  /// Scans the local network for services of a specific type.
  /// Returns a [Stream] of [NasServer] as they are discovered.
  static Stream<NasServer> scanForServers({
    String serviceType = '_http._tcp.local',
    Duration timeout = const Duration(seconds: 5),
  }) async* {
    if (kIsWeb) {
      _log.warning('mDNS discovery is not supported on Web.');
      return;
    }

    final MDnsClient client = MDnsClient();
    try {
      await client.start();
      _log.info('Starting mDNS scan for $serviceType...');

      // 1. Look for Service Pointers (PTR)
      await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(serviceType),
        timeout: timeout,
      )) {
        _log.fine('Found PTR record: ${ptr.domainName}');

        // 2. For each PTR, look for the Service Record (SRV) to get Port and Target Host
        await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
          timeout: const Duration(seconds: 2),
        )) {
          _log.info('Found SRV record: ${ptr.domainName} -> ${srv.target}:${srv.port}');

          // Resolve IP addresses (A records) for the SRV target
          final List<String> ipAddresses = [];
          await for (final IPAddressResourceRecord ip in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
            timeout: const Duration(seconds: 2),
          )) {
            ipAddresses.add(ip.address.address);
          }

          if (ipAddresses.isEmpty) continue;

          // Strip trailing dots from the target hostname for compatibility with http clients
          final host = srv.target.endsWith('.')
              ? srv.target.substring(0, srv.target.length - 1)
              : srv.target;

          yield NasServer(
            name: ptr.domainName.split('.').first,
            host: host,
            addresses: ipAddresses,
            port: srv.port,
          );
        }
      }
    } catch (e, stack) {
      _log.severe('Error during mDNS discovery', e, stack);
    } finally {
      client.stop();
      _log.info('mDNS scan completed.');
    }
  }
}