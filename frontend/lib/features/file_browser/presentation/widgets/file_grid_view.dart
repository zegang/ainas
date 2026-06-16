import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/themes/app_theme.dart';
import '../../../../shared/models/file_item.dart';
import 'file_action_menu.dart';

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

  @override
  Widget build(BuildContext context) {
    final themeExt = Theme.of(context).extension<AppThemeExtension>()!;

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
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onItemTap(item),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!item.isDir && _isImage(item.name))
                        SizedBox(
                          width: 64,
                          height: 64,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(
                              item.thumbnailUrl, // Use the new thumbnailUrl from FileItem
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
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
                Positioned(
                  top: 0,
                  left: 0,
                  child: Checkbox(
                    value: selectedItems.contains(item),
                    onChanged: (val) => onItemSelected(item, val),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: FileActionMenu(item: item, onActionSelected: onActionSelected),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
