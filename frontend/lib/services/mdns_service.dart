import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logging/logging.dart';
import 'package:multicast_dns/multicast_dns.dart';
import '../shared/models/nas_server.dart';

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

          // 3. Resolve IPv4 addresses (A records) for the SRV target
          final List<String> ipAddresses = [];
          await for (final IPAddressResourceRecord ip in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
            timeout: const Duration(seconds: 2),
          )) {
            ipAddresses.add(ip.address.address);
          }

          // 4. Resolve IPv6 addresses (AAAA records)
          final List<String> ipv6Addresses = [];
          await for (final IPAddressResourceRecord ip in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv6(srv.target),
            timeout: const Duration(seconds: 2),
          )) {
            ipv6Addresses.add(ip.address.address);
          }

          // 5. Resolve TXT records for additional metadata
          final List<String> txtEntries = [];
          await for (final TxtResourceRecord txt in client.lookup<TxtResourceRecord>(
            ResourceRecordQuery.text(ptr.domainName),
            timeout: const Duration(seconds: 2),
          )) {
            txtEntries.add(txt.text);
          }

          if (ipAddresses.isEmpty && ipv6Addresses.isEmpty) {
            _log.warning('No IP addresses resolved for ${srv.target}, using hostname as fallback');
          }

          // Strip trailing dots from the target hostname for compatibility with http clients
          final host = srv.target.endsWith('.')
              ? srv.target.substring(0, srv.target.length - 1)
              : srv.target;

          yield NasServer(
            name: ptr.domainName.split('.').first,
            host: host,
            addresses: ipAddresses,
            ipv6Addresses: ipv6Addresses,
            port: srv.port,
            priority: srv.priority,
            weight: srv.weight,
            txtRecords: txtEntries,
            serviceType: ptr.domainName.split('.').sublist(1).join('.'),
          );
        }
      }
    } catch (e, stack) {
      _log.severe('Error during mDNS discovery', e, stack);
    } finally {
      client.stop();
      _log.info('mDNS scan for $serviceType completed.');
    }
  }

  /// Scans the local network for all registered mDNS service types.
  /// First discovers available service types via DNS-SD meta-query,
  /// then resolves instances for each type.
  static Stream<NasServer> scanForAllServices({
    Duration timeout = const Duration(seconds: 5),
  }) async* {
    if (kIsWeb) {
      _log.warning('mDNS discovery is not supported on Web.');
      return;
    }

    _log.info('Starting mDNS scan for all services...');

    // Step 1: Discover service types via DNS-SD meta-query
    final serviceTypes = await _discoverServiceTypes(timeout: timeout);

    // Step 2: Always include _http._tcp as a fallback
    serviceTypes.add('_http._tcp.local');

    // Step 3: Scan each discovered service type
    for (final type in serviceTypes) {
      _log.info('Scanning service type: $type');
      yield* scanForServers(serviceType: type, timeout: timeout);
    }
  }

  /// Queries the DNS-SD meta-query name to discover all registered service types.
  static Future<Set<String>> _discoverServiceTypes({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final types = <String>{};
    final client = MDnsClient();
    try {
      await client.start();
      await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer('_services._dns-sd._udp.local'),
        timeout: timeout,
      )) {
        types.add(ptr.domainName);
        _log.fine('Discovered service type: ${ptr.domainName}');
      }
    } catch (e) {
      _log.warning('Failed to discover service types: $e');
    } finally {
      client.stop();
    }
    return types;
  }
}