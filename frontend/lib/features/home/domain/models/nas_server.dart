class NasServer {
  final String name;
  final String host;
  final List<String> addresses;
  final int port;

  NasServer({required this.name, required this.host, required this.addresses, required this.port});

  /// Returns the formatted base URL for API communication.
  String get url => 'http://${addresses[0]}:$port';
}
