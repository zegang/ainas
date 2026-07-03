import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logging/logging.dart';
import 'package:multicast_dns/multicast_dns.dart';
import '../shared/models/nas_server.dart';

class MdnsService {
  static final _log = Logger('MdnsService');

  /// Scans all mDNS services on the network and filters by [searchText].
  ///
  /// A server matches if:
  ///   - its service name (first label of the PTR domain) contains [searchText]
  ///     (case-insensitive), OR
  ///   - any TXT record with key "id" has a value containing [searchText]
  ///     (case-insensitive).
  ///
  /// When [searchText] is empty or null, all discovered servers are returned.
  static Stream<NasServer> scanForServers({
    String searchText = '',
    Duration timeout = const Duration(seconds: 5),
  }) async* {
    if (kIsWeb) {
      _log.warning('mDNS discovery is not supported on Web.');
      return;
    }

    final lowerSearch = searchText.toLowerCase();
    final client = MDnsClient();
    try {
      await client.start();
      _log.info('Starting mDNS scan for all services ($searchText)...');

      // Discover all service types
      final serviceTypes = <String>{};
      await for (final ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer('_services._dns-sd._udp.local'),
        timeout: Duration(seconds: 3),
      )) {
        serviceTypes.add(ptr.domainName);
      }
      serviceTypes.add('_http._tcp.local');

      for (final serviceType in serviceTypes) {
        _log.fine('Scanning service type: $serviceType');

        await for (final ptr in client.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(serviceType),
          timeout: timeout,
        )) {
          final serviceName = ptr.domainName.split('.').first;

          // Resolve SRV to get port and target hostname
          SrvResourceRecord? srv;
          await for (final record in client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
            timeout: const Duration(seconds: 2),
          )) {
            srv = record;
            break;
          }
          if (srv == null) continue;

          // Resolve TXT records
          final List<String> txtEntries = [];
          await for (final txt in client.lookup<TxtResourceRecord>(
            ResourceRecordQuery.text(ptr.domainName),
            timeout: const Duration(seconds: 2),
          )) {
            txtEntries.add(txt.text);
          }

          // Apply filter
          if (searchText.isNotEmpty &&
              !_matchesSearchText(lowerSearch, serviceName, txtEntries)) {
            _log.fine('Skipping $serviceName (no match)');
            continue;
          }

          // Resolve IP addresses
          final List<String> ipAddresses = [];
          await for (final ip in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
            timeout: const Duration(seconds: 2),
          )) {
            ipAddresses.add(ip.address.address);
          }
          final List<String> ipv6Addresses = [];
          await for (final ip in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv6(srv.target),
            timeout: const Duration(seconds: 2),
          )) {
            ipv6Addresses.add(ip.address.address);
          }

          if (ipAddresses.isEmpty && ipv6Addresses.isEmpty) {
            _log.warning('No IP addresses resolved for ${srv.target}, using hostname as fallback');
          }

          final host = srv.target.endsWith('.')
              ? srv.target.substring(0, srv.target.length - 1)
              : srv.target;

          _log.info('Discovered: $serviceName -> $host:${srv.port}');
          yield NasServer(
            name: serviceName,
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
      _log.info('mDNS scan for all services completed.');
    } catch (e) {
      _log.severe('Error during mDNS discovery: $e');
    } finally {
      client.stop();
    }
  }

  /// Returns true if [serviceName] or any TXT "id" value matches [lowerSearch].
  static bool _matchesSearchText(
    String lowerSearch,
    String serviceName,
    List<String> txtEntries,
  ) {
    if (serviceName.toLowerCase().contains(lowerSearch)) return true;
    for (final entry in txtEntries) {
      for (final line in entry.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final eq = trimmed.indexOf('=');
        if (eq < 0) continue;
        final key = trimmed.substring(0, eq).trim();
        final value = trimmed.substring(eq + 1).trim();
        if (key.toLowerCase() == 'id' && value.toLowerCase().contains(lowerSearch)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Scans the local network for all registered mDNS service types.
  static Stream<NasServer> scanForAllServices({
    Duration timeout = const Duration(seconds: 5),
  }) async* {
    yield* scanForServers(searchText: '', timeout: timeout);
  }
}
