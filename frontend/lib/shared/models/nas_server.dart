class NasServer {
  final String name;
  final String host;
  final int port;
  final int priority;
  final int weight;
  final List<String> addresses;
  final List<String> ipv6Addresses;
  final List<String> txtRecords;
  final String serviceType;

  NasServer({
    required this.name,
    required this.host,
    required this.port,
    this.priority = 0,
    this.weight = 0,
    required this.addresses,
    this.ipv6Addresses = const [],
    this.txtRecords = const [],
    this.serviceType = '_http._tcp.local.',
  });

  String get primaryAddress => addresses.isNotEmpty
      ? addresses.first
      : ipv6Addresses.isNotEmpty
          ? ipv6Addresses.first
          : host;

  String get url => 'http://$primaryAddress:$port';

  String get displayUrl => addresses.isNotEmpty
      ? '${addresses.first}:$port'
      : ipv6Addresses.isNotEmpty
          ? '${ipv6Addresses.first}:$port'
          : '$host:$port';

  Map<String, String> get properties {
    final map = <String, String>{};
    for (final record in txtRecords) {
      for (final line in record.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final idx = trimmed.indexOf('=');
        if (idx > 0) {
          map[trimmed.substring(0, idx)] = trimmed.substring(idx + 1);
        } else {
          map[trimmed] = '';
        }
      }
    }
    return map;
  }
}