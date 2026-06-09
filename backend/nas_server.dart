class NasServer {
  final String name;
  final String host;
  final int port;

  NasServer({required this.name, required this.host, required this.port});

  /// Returns the formatted base URL for API communication.
  String get url => 'http://$host:$port';
}