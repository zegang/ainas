import 'package:flutter/material.dart';
import '../../services/api_service.dart'; // Import ApiService to get baseUrl

class FileItem {
  final String name;
  final String path; // Relative path from NAS_DATA_PATH
  final bool isDir;
  final List<String> tags;
  final int size;
  final DateTime updatedAt;
  final DateTime createdAt;

  FileItem({
    required this.name,
    required this.path,
    required this.isDir,
    this.tags = const [],
    this.size = 0,
    required this.updatedAt,
    required this.createdAt,
  });

  factory FileItem.fromJson(Map<String, dynamic> json) {
    return FileItem(
      name: json['name'],
      path: json['path'] ?? json['name'],
      isDir: json['is_dir'],
      tags: List<String>.from(json['tags'] ?? []),
      size: json['size'] ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(((json['updated_at'] ?? 0) * 1000).toInt()),
      createdAt: DateTime.fromMillisecondsSinceEpoch(((json['created_at'] ?? 0) * 1000).toInt()),
    );
  }

  // Helper getter for thumbnail URL
  String get thumbnailUrl {
    final api = ApiService();
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '${api.baseUrl}/api/files/download?path=${Uri.encodeComponent(cleanPath)}&thumbnail=true';
  }

  // Helper getter for download URL
  String get downloadUrl {
    final api = ApiService();
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '${api.baseUrl}/api/files/download?path=${Uri.encodeComponent(cleanPath)}';
  }

  @override
  bool operator ==(Object other) => identical(this, other) || other is FileItem && runtimeType == other.runtimeType && path == other.path && isDir == other.isDir;

  @override
  int get hashCode => path.hashCode ^ isDir.hashCode;
}