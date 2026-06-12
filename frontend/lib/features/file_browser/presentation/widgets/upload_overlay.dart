import 'package:flutter/material.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/models/upload_models.dart';

class UploadOverlay extends StatelessWidget {
  final ApiService api;

  const UploadOverlay({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: api,
      builder: (context, _) {
        if (api.uploads.isEmpty) return const SizedBox.shrink();

        return Card(
          margin: const EdgeInsets.all(12),
          elevation: 8,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 250),
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  dense: true,
                  title: Text(
                    "Uploads (${api.uploads.where((t) => t.status == UploadStatus.uploading).length} active)",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: TextButton(
                    onPressed: api.clearCompletedUploads,
                    child: const Text("Clear"),
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: api.uploads.length,
                    itemBuilder: (context, index) {
                      final task = api.uploads[api.uploads.length - 1 - index];
                      return ListTile(
                        dense: true,
                        leading: _getUploadIcon(task.status),
                        title: Text(task.fileName, overflow: TextOverflow.ellipsis),
                        subtitle: task.status == UploadStatus.uploading
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (task.parentPath.isNotEmpty)
                                    Text("To: /${task.parentPath}", style: const TextStyle(fontSize: 10)),
                                  const SizedBox(height: 2),
                                  LinearProgressIndicator(value: task.progress > 0 ? task.progress : null),
                                ],
                              )
                            : Text("${task.status.name}${task.parentPath.isNotEmpty ? ' to /${task.parentPath}' : ''}", 
                                   style: TextStyle(fontSize: 10, color: _getStatusColor(task.status))),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (task.status == UploadStatus.failed)
                              IconButton(
                                icon: const Icon(Icons.refresh, size: 20),
                                onPressed: () => api.retryUpload(task.id),
                              ),
                            if (task.status == UploadStatus.uploading)
                              IconButton(
                                icon: const Icon(Icons.cancel, size: 20),
                                onPressed: () => api.cancelUpload(task.id),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Icon _getUploadIcon(UploadStatus status) {
    switch (status) {
      case UploadStatus.completed: return const Icon(Icons.check_circle, color: Colors.green);
      case UploadStatus.failed: return const Icon(Icons.error, color: Colors.red);
      case UploadStatus.canceled: return const Icon(Icons.block, color: Colors.grey);
      default: return const Icon(Icons.cloud_upload, color: Colors.blue);
    }
  }

  Color _getStatusColor(UploadStatus status) {
    switch (status) {
      case UploadStatus.completed: return Colors.green;
      case UploadStatus.failed: return Colors.red;
      case UploadStatus.canceled: return Colors.grey;
      default: return Colors.blue;
    }
  }
}