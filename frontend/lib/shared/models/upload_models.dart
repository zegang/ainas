import 'dart:typed_data';
import 'package:http/http.dart' as http;

enum UploadStatus { pending, uploading, completed, failed, canceled }

class UploadTask {
  final String id;
  final String fileName;
  final String parentPath;
  final Uint8List? bytes;
  final String? filePath;
  final String? stagingFilePath;
  double progress;
  UploadStatus status;
  String? errorMessage;
  http.Client? client;

  UploadTask({
    required this.id,
    required this.fileName,
    required this.parentPath,
    this.bytes,
    this.filePath,
    this.stagingFilePath,
    this.progress = 0.0,
    this.status = UploadStatus.pending,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'parentPath': parentPath,
    'filePath': filePath,
    'stagingFilePath': stagingFilePath,
    'status': status.name,
  };

  factory UploadTask.fromJson(Map<String, dynamic> json) => UploadTask(
    id: json['id'] as String,
    fileName: json['fileName'] as String,
    parentPath: json['parentPath'] as String? ?? '',
    filePath: json['filePath'] as String?,
    stagingFilePath: json['stagingFilePath'] as String?,
    status: UploadStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => UploadStatus.pending,
    ),
  );

  UploadTask copyWith({
    UploadStatus? status,
    double? progress,
    String? errorMessage,
  }) => UploadTask(
    id: id,
    fileName: fileName,
    parentPath: parentPath,
    bytes: bytes,
    filePath: filePath,
    stagingFilePath: stagingFilePath,
    progress: progress ?? this.progress,
    status: status ?? this.status,
  );
}
