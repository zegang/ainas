import 'dart:typed_data';
import 'package:http/http.dart' as http; // Only for http.Client type hint

enum UploadStatus { pending, uploading, completed, failed, canceled }

class UploadTask {
  final String id;
  final String fileName;
  final String parentPath;
  final Uint8List bytes;
  double progress; // 0.0 to 1.0
  UploadStatus status;
  String? errorMessage;
  http.Client? client; // Public client for cancellation across libraries

  UploadTask({
    required this.id,
    required this.fileName,
    required this.parentPath,
    required this.bytes,
    this.progress = 0.0,
    this.status = UploadStatus.pending,
  });
}