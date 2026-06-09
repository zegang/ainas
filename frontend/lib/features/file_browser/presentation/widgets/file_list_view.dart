import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../common/themes/app_theme.dart';
import '../../../../services/api_service.dart';

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

  const FileListView({
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildListHeader(context),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) => _buildListRow(context, items[index]),
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

  Widget _buildListRow(BuildContext context, FileItem item) {
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
            _buildPopupMenu(item),
          ],
        ),
      ),
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