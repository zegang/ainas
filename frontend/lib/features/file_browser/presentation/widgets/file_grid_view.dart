import 'package:flutter/material.dart';
import '../../../../common/themes/app_theme.dart';
import '../../../../services/api_service.dart';

class FileGridView extends StatelessWidget {
  final List<FileItem> items;
  final Function(FileItem) onItemTap;
  final Function(String, FileItem) onActionSelected;
  final Set<FileItem> selectedItems;
  final Function(FileItem, bool?) onItemSelected;

  const FileGridView({
    super.key,
    required this.items,
    required this.onItemTap,
    required this.onActionSelected,
    required this.selectedItems,
    required this.onItemSelected,
  });

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
                  child: _buildPopupMenu(item),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPopupMenu(FileItem item) {
    return PopupMenuButton<String>(
      onSelected: (value) => onActionSelected(value, item),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'rename', child: Text("Rename")),
        const PopupMenuItem(value: 'move', child: Text("Move")),
        const PopupMenuItem(value: 'attach', child: Text("Attach to AI")),
        const PopupMenuItem(value: 'delete', child: Text("Delete")),
      ],
    );
  }
}
