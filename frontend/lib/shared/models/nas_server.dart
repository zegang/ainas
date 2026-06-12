class NasServer {
  final String name;
  final String host;
  final int port;
  final List<String> addresses;

  NasServer({
    required this.name,
    required this.host,
    required this.port,
    required this.addresses,
  });

  String get url => 'http://$host:$port';
}