class NasServer {
  final String name;
  final String host;
  final int port;
  final int priority;
  final int weight;
  final List<String> addresses;
  final List<String> ipv6Addresses;
  final List<String> txtRecords;

  NasServer({
    required this.name,
    required this.host,
    required this.port,
    this.priority = 0,
    this.weight = 0,
    required this.addresses,
    this.ipv6Addresses = const [],
    this.txtRecords = const [],
  });

  String get primaryAddress => addresses.isNotEmpty ? addresses.first : host;

  String get url => 'http://$primaryAddress:$port';

  String get displayUrl => addresses.isNotEmpty
      ? '${addresses.first}:$port'
      : '$host:$port';
}