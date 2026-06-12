import 'package:http/http.dart' as http;

/// A [http.MultipartRequest] that tracks upload progress by wrapping the stream.
class ProgressMultipartRequest extends http.MultipartRequest {
  ProgressMultipartRequest(String method, Uri url, {required this.onProgress}) : super(method, url);

  final void Function(int bytes, int total) onProgress;

  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();
    final total = contentLength;
    int bytesWritten = 0;

    return http.ByteStream(byteStream.map((List<int> data) {
      bytesWritten += data.length;
      onProgress(bytesWritten, total);
      return data;
    }));
  }
}