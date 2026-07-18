import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'db_service.dart';
import '../shared/models/file_item.dart';
import '../shared/models/upload_models.dart';
import 'connection_helper.dart';
import 'progress_multipart_request.dart';

class FileService with ChangeNotifier {
  FileService._internal();

  static final FileService _instance = FileService._internal();

  factory FileService() => _instance;

  final _log = Logger('FileService');

  String baseUrl = '';

  DbService _db = SharedPrefDbService();

  set dbService(DbService service) {
    _db = service;
  }

  String currentPath = '';
  final List<UploadTask> uploads = [];
  static const String _pendingUploadsKey = 'nas_pending_uploads';
  static const Duration _fileListCacheTtl = Duration(seconds: 30);
  final Map<String, _CacheEntry<List<FileItem>>> _fileListCache = {};

  final List<UploadTask> _uploadQueue = [];
  bool _isProcessingQueue = false;

  Directory get _stagingDir => Directory('${Directory.systemTemp.path}/ainas_uploads');

  Future<void> _ensureStagingDir() async {
    if (!await _stagingDir.exists()) {
      await _stagingDir.create(recursive: true);
    }
  }

  void invalidateFileListCache() {
    _fileListCache.clear();
  }

  Future<List<FileItem>> listFiles(String path, {bool forceRefresh = false}) async {
    currentPath = path;

    if (!forceRefresh) {
      final cached = _fileListCache[path];
      if (cached != null && !cached.isExpired) {
        _log.fine('Cache hit for $path');
        return cached.data;
      }
    }

    final url = '$baseUrl/api/files?path=$path&_t=${DateTime.now().millisecondsSinceEpoch}';
    _log.info('--> GET $url');

    final response = await http.get(Uri.parse(url));
    _log.info('<-- ${response.statusCode} $url');
    _log.fine('Response Headers: ${response.headers}');

    if (response.statusCode == 200) {
      List data = json.decode(response.body)['items'];
      final items = data.map((item) => FileItem.fromJson(item)).toList();
      _fileListCache[path] = _CacheEntry(items);
      return items;
    } else {
      _log.severe('API Error Detail - Status: ${response.statusCode}, Body: ${response.body}');
      throw Exception('Failed to load files');
    }
  }

  Future<void> createFolder(String path) async {
    final url = '$baseUrl/api/files/folder';
    _log.info('--> POST $url');
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'path': path}),
    );
    if (response.statusCode != 200) throw Exception('Failed to create folder');
  }

  Future<void> deleteItem(String path) async {
    final url = '$baseUrl/api/files';
    _log.info('--> DELETE $url');
    final response = await http.delete(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'path': path}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete item');
    }
  }

  Future<void> renameItem(String path, String newName) async {
    final url = '$baseUrl/api/files/rename';
    _log.info('--> PATCH $url');
    final response = await http.patch(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'path': path, 'new_name': newName}),
    );
    if (response.statusCode != 200) throw Exception('Failed to rename');
  }

  Future<void> moveItem(String path, String newPath) async {
    final url = '$baseUrl/api/files/move';
    _log.info('--> PATCH $url');
    final response = await http.patch(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'path': path, 'new_path': newPath}),
    );
    if (response.statusCode != 200) throw Exception('Failed to move');
  }

  Future<void> copyItem(String path, String targetDir) async {
    final url = '$baseUrl/api/files/copy';
    _log.info('--> POST $url');
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'paths': [path], 'target_dir': targetDir}),
    );
    if (response.statusCode != 200) throw Exception('Failed to copy');
  }

  Future<void> copyItems(List<String> paths, String targetDir) async {
    final url = '$baseUrl/api/files/copy';
    _log.info('--> POST $url');
    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'paths': paths, 'target_dir': targetDir}),
    );
    if (response.statusCode != 200) throw Exception('Failed to copy');
  }

  void cancelUpload(String taskId) {
    final index = uploads.indexWhere((t) => t.id == taskId);
    if (index == -1) return;
    final task = uploads[index];
    task.client?.close();
    task.status = UploadStatus.canceled;
    if (_isProcessingQueue && _uploadQueue.isNotEmpty && _uploadQueue.first.id == taskId) {
      // Currently being uploaded — let _processQueue remove it after _performUpload returns
    } else {
      _uploadQueue.removeWhere((t) => t.id == taskId);
    }
    _cleanupStagedFile(task);
    _persistQueue();
    notifyListeners();
  }

  void clearCompletedUploads() {
    uploads.removeWhere((t) => t.status == UploadStatus.completed || t.status == UploadStatus.canceled);
    _uploadQueue.removeWhere((t) => t.status == UploadStatus.completed || t.status == UploadStatus.canceled);
    notifyListeners();
  }

  Future<void> retryUpload(String taskId) async {
    final index = uploads.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = uploads[index];
    task.status = UploadStatus.uploading;
    task.progress = 0.0;
    task.errorMessage = null;
    notifyListeners();

    _uploadQueue.add(task);
    await _persistQueue();
    _processQueue();
  }

  Future<Map<String, dynamic>> pdfToImages(String path, String outputDir) async {
    final url = Uri.parse('$baseUrl/api/files/pdf-to-images');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'path': path, 'output_dir': outputDir}),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('PDF-to-images failed: ${response.body}');
  }

  Future<Map<String, dynamic>> compressImage(String path, int quality, {int? maxWidth, int? maxHeight, String? outputPath}) async {
    final url = Uri.parse('$baseUrl/api/files/compress-image');
    final body = <String, dynamic>{'path': path, 'quality': quality};
    if (maxWidth != null && maxWidth > 0) {
      body['max_width'] = maxWidth;
    }
    if (maxHeight != null && maxHeight > 0) {
      body['max_height'] = maxHeight;
    }
    if (outputPath != null && outputPath.isNotEmpty) {
      body['output_path'] = outputPath;
    }
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(body),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Compress image failed: ${response.body}');
  }

  Future<Map<String, dynamic>> mergeToPdf(
      List<String> filePaths, String outputPath) async {
    final url = Uri.parse('$baseUrl/api/files/merge-to-pdf');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'file_paths': filePaths,
        'output_path': outputPath,
      }),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Merge-to-PDF failed: ${response.body}');
  }

  Future<void> uploadFile(String fileName, Uint8List bytes, {String? parentPath}) async {
    final taskId = DateTime.now().millisecondsSinceEpoch.toString() + fileName;
    final targetPath = parentPath ?? currentPath;
    final task = UploadTask(
      id: taskId,
      fileName: fileName,
      parentPath: targetPath,
      bytes: bytes,
      status: UploadStatus.uploading,
    );
    uploads.add(task);
    notifyListeners();
    await _performUpload(task);
  }

  Future<void> uploadFileFromPath(String fileName, String filePath, {String? parentPath}) async {
    final taskId = DateTime.now().millisecondsSinceEpoch.toString() + fileName;
    final targetPath = parentPath ?? currentPath;
    final task = UploadTask(
      id: taskId,
      fileName: fileName,
      parentPath: targetPath,
      filePath: filePath,
      status: UploadStatus.uploading,
    );
    uploads.add(task);
    notifyListeners();
    await _performUpload(task);
  }

  Future<void> enqueueUploads(List<MapEntry<String, String>> files, {String? parentPath}) async {
    await _ensureStagingDir();
    final targetPath = parentPath ?? currentPath;

    for (final entry in files) {
      final fileName = entry.key;
      final sourcePath = entry.value;
      final taskId = DateTime.now().millisecondsSinceEpoch.toString() + fileName;
      final ext = p.extension(fileName);
      final stagedPath = '${_stagingDir.path}/$taskId$ext';

      try {
        await File(sourcePath).copy(stagedPath);
      } catch (e) {
        _log.warning('Failed to stage file $fileName for persistent upload: $e');
        final task = UploadTask(
          id: taskId,
          fileName: fileName,
          parentPath: targetPath,
          filePath: sourcePath,
          status: UploadStatus.pending,
        );
        _uploadQueue.add(task);
        uploads.add(task);
        continue;
      }

      final task = UploadTask(
        id: taskId,
        fileName: fileName,
        parentPath: targetPath,
        stagingFilePath: stagedPath,
        status: UploadStatus.pending,
      );
      _uploadQueue.add(task);
      uploads.add(task);
    }

    await _persistQueue();
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;

    while (_uploadQueue.isNotEmpty) {
      final task = _uploadQueue.first;

      if (task.status == UploadStatus.canceled) {
        _uploadQueue.removeAt(0);
        await _persistQueue();
        notifyListeners();
        continue;
      }

      task.status = UploadStatus.uploading;
      notifyListeners();
      try {
        await _performUpload(task);
      } catch (e) {
        _log.severe('Unexpected error in upload queue for "${task.fileName}": $e');
        if (task.status != UploadStatus.canceled) {
          task.status = UploadStatus.failed;
          task.errorMessage = e.toString();
        }
      }

      _uploadQueue.removeAt(0);
      try {
        await _persistQueue();
      } catch (e) {
        _log.severe('Failed to persist upload queue: $e');
      }
      if (task.status == UploadStatus.completed || task.status == UploadStatus.canceled) {
        _cleanupStagedFile(task);
      }
      notifyListeners();
    }

    _isProcessingQueue = false;
  }

  void _cleanupStagedFile(UploadTask task) {
    if (task.stagingFilePath != null) {
      try {
        File(task.stagingFilePath!).deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _persistQueue() async {
    final jsonList = _uploadQueue
        .where((t) => t.status == UploadStatus.pending || t.status == UploadStatus.uploading)
        .map((t) => t.toJson())
        .toList();
    await _db.setString(_pendingUploadsKey, json.encode(jsonList));
  }

  Future<void> loadPendingUploads() async {
    final raw = await _db.getString(_pendingUploadsKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final List<dynamic> jsonList = json.decode(raw);
      for (final j in jsonList) {
        final task = UploadTask.fromJson(j as Map<String, dynamic>);
        if (task.status == UploadStatus.pending || task.status == UploadStatus.uploading) {
          final resetTask = task.copyWith(status: UploadStatus.pending, progress: 0.0);
          _uploadQueue.add(resetTask);
          uploads.add(resetTask);
        }
      }
      if (_uploadQueue.isNotEmpty) {
        _log.info('Loaded ${_uploadQueue.length} pending uploads from persistence');
        _processQueue();
      }
    } catch (e) {
      _log.severe('Failed to load pending uploads: $e');
      await _db.remove(_pendingUploadsKey);
    }
  }

  Future<void> _performUpload(UploadTask task) async {
    final client = http.Client();
    task.client = client;

    try {
      final uploadUrl = '$baseUrl/api/files/upload';
      _log.info('Uploading file "${task.fileName}" to $uploadUrl, parentPath="${task.parentPath}"');

      final request = ProgressMultipartRequest(
        'POST',
        Uri.parse(uploadUrl),
        onProgress: (bytes, total) {
          try {
            task.progress = total > 0 ? bytes / total : 0.0;
            notifyListeners();
          } catch (_) {
          }
        },
      );

      request.fields['path'] = task.parentPath;
      final uploadPath = task.stagingFilePath ?? task.filePath;
      if (uploadPath != null) {
        request.files.add(await http.MultipartFile.fromPath('file', uploadPath, filename: task.fileName));
      } else if (task.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes('file', task.bytes!, filename: task.fileName));
      }

      final response = await client.send(request);

      final respBody = await response.stream.bytesToString();
      if (response.statusCode == 200) {
        task.status = UploadStatus.completed;
        task.progress = 1.0;
        _log.info('Successfully uploaded "${task.fileName}"');
      } else {
        task.status = UploadStatus.failed;
        task.errorMessage = "Status ${response.statusCode}";
        _log.severe('Upload failed for "${task.fileName}": $respBody');
      }
    } catch (e) {
      if (task.status != UploadStatus.canceled) {
        task.status = UploadStatus.failed;
        task.errorMessage = e.toString();
      }
      _log.severe('Upload error for "${task.fileName}": $e');
    } finally {
      client.close();
      notifyListeners();
    }
  }
}

class _CacheEntry<T> {
  final T data;
  final DateTime timestamp;
  _CacheEntry(this.data) : timestamp = DateTime.now();
  bool get isExpired => DateTime.now().difference(timestamp) > FileService._fileListCacheTtl;
}
