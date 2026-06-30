import 'package:flutter/material.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/services/api_service.dart';
import 'package:ainas_frontend/shared/models/upload_models.dart';

class UploadOverlay extends StatelessWidget {
  final ApiService api;

  const UploadOverlay({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: api,
      builder: (context, _) {
        final activeCount = api.uploads.where((t) => t.status == UploadStatus.uploading).length;
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
                    l10n.uploadTitle(activeCount),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: TextButton(
                    onPressed: api.clearCompletedUploads,
                    child: Text(l10n.transferClear),
                  ),
                ),
                const Divider(height: 1),
                if (api.uploads.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        l10n.uploadEmpty,
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: api.uploads.length,
                      itemBuilder: (context, index) {
                        final task = api.uploads[api.uploads.length - 1 - index];
                        final statusText = _statusLabel(task.status, l10n);
                        return ListTile(
                          dense: true,
                          leading: _getUploadIcon(task.status),
                          title: Text(task.fileName, overflow: TextOverflow.ellipsis),
                          subtitle: task.status == UploadStatus.uploading
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (task.parentPath.isNotEmpty)
                                      Text(l10n.uploadToPath(task.parentPath), style: const TextStyle(fontSize: 10)),
                                    const SizedBox(height: 2),
                                    LinearProgressIndicator(value: task.progress > 0 ? task.progress : null),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      task.parentPath.isNotEmpty
                                          ? '${statusText} — ${l10n.uploadToPath(task.parentPath)}'
                                          : statusText,
                                      style: TextStyle(fontSize: 10, color: _getStatusColor(task.status)),
                                    ),
                                    if (task.errorMessage != null)
                                      Text(
                                        task.errorMessage!,
                                        style: const TextStyle(fontSize: 9, color: Colors.red),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
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

  String _statusLabel(UploadStatus status, AppLocalizations l10n) {
    switch (status) {
      case UploadStatus.completed: return l10n.transferCompleted;
      case UploadStatus.failed: return l10n.transferFailed;
      case UploadStatus.canceled: return l10n.transferCancelled;
      case UploadStatus.uploading: return l10n.uploadStatusUploading;
      case UploadStatus.pending: return l10n.transferPending;
    }
  }
}
