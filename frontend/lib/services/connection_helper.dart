import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

/// A utility class for checking connectivity to the AI-NAS backend.
abstract final class ConnectionHelper {
  static final _log = Logger('ConnectionHelper');

  /// Verifies connectivity to the backend by calling the status endpoint.
  /// 
  /// [baseUrl] should be the root URL (e.g., http://localhost:9026).
  /// The method automatically appends /api/status if not present.
  static Future<bool> checkStatus(String baseUrl, {Duration timeout = const Duration(seconds: 3)}) async {
    final targetUrl = baseUrl.endsWith('/api/status') ? baseUrl : "$baseUrl/api/status";
    try {
      final response = await http.get(Uri.parse(targetUrl)).timeout(timeout);
      return response.statusCode == 200;
    } catch (e) {
      _log.warning('Connection check failed for $targetUrl: $e');
      return false;
    }
  }
}