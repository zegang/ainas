import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/shared/themes/app_theme.dart';
import 'package:ainas_frontend/shared/models/file_item.dart';
import 'package:ainas_frontend/shared/widgets/file_action_menu.dart';

class FileGridView extends StatelessWidget {
  final List<FileItem> items;
  final Function(FileItem) onItemTap;
  final Function(String, FileItem) onActionSelected;
  final Set<FileItem> selectedItems;
  final Function(FileItem, bool?) onItemSelected;
  // ApiService api = ApiService(); // No longer needed here as FileItem is passed directly

  FileGridView({
    super.key,
    required this.items,
    required this.onItemTap,
    required this.onActionSelected,
    required this.selectedItems,
    required this.onItemSelected,
  });

  bool _isImage(String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }

  bool _isPdf(String fileName) => fileName.toLowerCase().endsWith('.pdf');

  String _formatSize(int bytes) {
    if (bytes <= 0) return "---";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (math.log(bytes) / math.log(1024)).floor();
    return ((bytes / math.pow(1024, i)).toStringAsFixed(1)) + ' ' + suffixes[i];
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

  @override
  Widget build(BuildContext context) {
    final themeExt = Theme.of(context).extension<AppThemeExtension>()!;
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final extension = item.name.contains('.') ? item.name.split('.').last : null;
        final isSelected = selectedItems.contains(item);
        
        return Card(
          clipBehavior: Clip.antiAlias,
          shape: isSmallScreen && isSelected
              ? RoundedRectangleBorder(
                  side: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
                  borderRadius: BorderRadius.circular(12),
                )
              : null,
          child: InkWell(
            onTap: () => onItemTap(item),
            onLongPress: isSmallScreen ? () => _showMobileActionSheet(context, item) : null,
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!item.isDir && (_isImage(item.name) || _isPdf(item.name)))
                        SizedBox(
                          width: 64,
                          height: 64,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: CachedNetworkImage(
                              imageUrl: item.thumbnailUrl,
                              fit: BoxFit.cover,
                              width: 64,
                              height: 64,
                              placeholder: (context, url) => Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                              errorWidget: (context, url, error) => _isPdf(item.name)
                                  ? Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        Container(
                                          width: 64,
                                          height: 64,
                                          decoration: BoxDecoration(
                                            color: Colors.red.shade50,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                        ),
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.picture_as_pdf, size: 36, color: Colors.red.shade400),
                                            const SizedBox(height: 2),
                                            Text('PDF', style: TextStyle(fontSize: 9, color: Colors.red.shade400, fontWeight: FontWeight.bold)),
                                          ],
                                        ),
                                      ],
                                    )
                                  : Icon(
                                      Icons.insert_drive_file,
                                      size: 48,
                                      color: themeExt.getFileColor(extension),
                                    ),
                            ),
                          ),
                        )
                      else
                        Icon(
                          item.isDir ? Icons.folder : Icons.insert_drive_file,
                          size: 48,
                          color: item.isDir ? themeExt.folderIconColor : themeExt.getFileColor(extension),
                        ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Text(
                          item.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isSmallScreen) ...[
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (val) => onItemSelected(item, val),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: FileActionMenu(item: item, onActionSelected: onActionSelected),
                  ),
                ],
                if (isSmallScreen)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: InkWell(
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
                          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.white.withOpacity(0.5),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, size: 16, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
