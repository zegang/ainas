import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/shared/themes/app_theme.dart';
import 'package:ainas_frontend/services/api_service.dart';
import 'package:ainas_frontend/shared/models/file_item.dart';
import 'package:ainas_frontend/features/file_browser/presentation/widgets/file_action_menu.dart';

class FileListView extends StatelessWidget {
  final List<FileItem> items;
  final int sortColumnIndex;
  final bool sortAscending;
  final Function(int, bool) onSort;
  final Function(FileItem) onItemTap;
  final Function(String, FileItem) onActionSelected;
  final Set<FileItem> selectedItems;
  final Function(bool?) onSelectAll;
  final Function(FileItem, bool?) onItemSelected;
  final ApiService api = ApiService(); // Instantiate singleton for baseUrl and row builder

  FileListView({
    super.key,
    required this.items,
    required this.sortColumnIndex,
    required this.sortAscending,
    required this.onSort,
    required this.onItemTap,
    required this.onActionSelected,
    required this.selectedItems,
    required this.onSelectAll,
    required this.onItemSelected,
  });

  String _formatSize(int bytes) {
    if (bytes <= 0) return "---";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (math.log(bytes) / math.log(1024)).floor();
    return ((bytes / math.pow(1024, i)).toStringAsFixed(1)) + ' ' + suffixes[i];
  }

  bool _isImage(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Column(
      children: [
        if (!isSmallScreen) _buildListHeader(context),
        if (!isSmallScreen) const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) => isSmallScreen
                ? _buildMobileListRow(context, items[index], api)
                : _buildListRow(context, items[index], api),
          ),
        ),
      ],
    );
  }

  Widget _buildListHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          Checkbox(
            visualDensity: VisualDensity.compact,
            value: items.isEmpty ? false : (selectedItems.length == items.length ? true : (selectedItems.isEmpty ? false : null)),
            tristate: true,
            onChanged: onSelectAll,
          ),
          _buildHeaderCell(context, "Name", 0, flex: 4),
          _buildHeaderCell(context, "Size", 1, flex: 1),
          _buildHeaderCell(context, "Type", 2, flex: 1),
          _buildHeaderCell(context, "Modified", 3, flex: 2),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(BuildContext context, String label, int index, {required int flex}) {
    final isSorted = sortColumnIndex == index;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () => onSort(index, isSorted ? !sortAscending : true),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontWeight: isSorted ? FontWeight.bold : FontWeight.normal)),
            if (isSorted) Icon(sortAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildListRow(BuildContext context, FileItem item, ApiService api) {
    final themeExt = Theme.of(context).extension<AppThemeExtension>()!;
    final dateStr = DateFormat.yMMMd().add_jm().format(item.updatedAt);
    final typeStr = item.isDir ? 'Folder' : (item.name.contains('.') ? item.name.split('.').last.toUpperCase() : 'File');
    final extension = item.name.contains('.') ? item.name.split('.').last : null;

    return InkWell(
      onTap: () => onItemTap(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Checkbox(
              visualDensity: VisualDensity.compact,
              value: selectedItems.contains(item),
              onChanged: (val) => onItemSelected(item, val),
            ),
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  if (!item.isDir && _isImage(item.name))
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2), // Use the new thumbnailUrl from FileItem
                        child: Image.network(
                          '${api.baseUrl}/api/files/download?path=${Uri.encodeComponent(item.path)}&thumbnail=true',
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  value: loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                      : null,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.insert_drive_file,
                            size: 20,
                            color: themeExt.getFileColor(extension),
                          ),
                        ),
                      ),
                    )
                  else
                    Icon(
                      item.isDir ? Icons.folder : Icons.insert_drive_file,
                      size: 20,
                      color: item.isDir ? themeExt.folderIconColor : themeExt.getFileColor(extension),
                    ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(item.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500))),
                ],
              ),
            ),
            Expanded(flex: 1, child: Text(item.isDir ? "---" : _formatSize(item.size), style: const TextStyle(fontSize: 13))),
            Expanded(flex: 1, child: Text(typeStr, style: const TextStyle(fontSize: 13, color: Colors.grey))),
            Expanded(flex: 2, child: Text(dateStr, style: const TextStyle(fontSize: 13, color: Colors.grey))),
            FileActionMenu(item: item, onActionSelected: onActionSelected),
          ],
        ),
      ),
    );
  }

  void _showMobileActionSheet(BuildContext context, FileItem item) {
    final l10n = AppLocalizations.of(context)!;
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(item.isDir ? 'Folder' : _formatSize(item.size), style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                ],
              ),
            ),
            const Divider(height: 1),
            if (item.tags.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.aiTags, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.outline)),
                    Text(item.tags.join(', '), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
              const Divider(height: 1),
            ],
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(l10n.renameAction),
              onTap: () {
                Navigator.pop(context);
                onActionSelected('rename', item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: Text(l10n.moveAction),
              onTap: () {
                Navigator.pop(context);
                onActionSelected('move', item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(l10n.attachToAiAction),
              onTap: () {
                Navigator.pop(context);
                onActionSelected('attach', item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(l10n.downloadAction),
              onTap: () {
                Navigator.pop(context);
                onActionSelected('download', item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(l10n.deleteAction, style: const TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                onActionSelected('delete', item);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileListRow(BuildContext context, FileItem item, ApiService api) {
    final themeExt = Theme.of(context).extension<AppThemeExtension>()!;
    final dateStr = DateFormat.yMMMd().add_jm().format(item.updatedAt);
    final extension = item.name.contains('.') ? item.name.split('.').last : null;
    final sizeStr = item.isDir ? "" : " • ${_formatSize(item.size)}";
    final isSelected = selectedItems.contains(item);

    return InkWell(
      onTap: () => onItemTap(item),
      onLongPress: () => _showMobileActionSheet(context, item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // First column: image/file icon
            if (!item.isDir && _isImage(item.name))
              SizedBox(
                width: 48,
                height: 48,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    '${api.baseUrl}/api/files/download?path=${Uri.encodeComponent(item.path)}&thumbnail=true',
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: themeExt.getFileColor(extension).withOpacity(0.1),
                      child: Icon(
                        Icons.image,
                        size: 28,
                        color: themeExt.getFileColor(extension),
                      ),
                    ),
                  ),
                ),
              )
            else
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: item.isDir ? themeExt.folderIconColor.withOpacity(0.1) : themeExt.getFileColor(extension).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  item.isDir ? Icons.folder : Icons.insert_drive_file,
                  size: 28,
                  color: item.isDir ? themeExt.folderIconColor : themeExt.getFileColor(extension),
                ),
              ),
            const SizedBox(width: 16),
            // Second column: 2 rows
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "$dateStr$sizeStr",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Last column: small circle selection button
            InkWell(
              onTap: () => onItemSelected(item, !isSelected),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
                    width: 2,
                  ),
                  color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}