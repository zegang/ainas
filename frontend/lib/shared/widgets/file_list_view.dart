import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/shared/themes/app_theme.dart';
import 'package:ainas_frontend/services/api_service.dart';
import 'package:ainas_frontend/shared/models/file_item.dart';
import 'package:ainas_frontend/shared/widgets/file_action_menu.dart';

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
  final bool showSizeColumn;
  final bool showTypeColumn;
  final bool showDateColumn;
  final bool showActionMenu;
  final bool showOnlyDirs;
  final ApiService api = ApiService();

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
    this.showSizeColumn = true,
    this.showTypeColumn = true,
    this.showDateColumn = true,
    this.showActionMenu = true,
    this.showOnlyDirs = false,
  });

  List<FileItem> get _filteredItems =>
      showOnlyDirs ? items.where((i) => i.isDir).toList() : items;

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
    final filtered = _filteredItems;

    return Column(
      children: [
        if (!isSmallScreen) _buildListHeader(context, filtered),
        if (!isSmallScreen) const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: filtered.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) => isSmallScreen
                ? _buildMobileListRow(context, filtered[index], api)
                : _buildListRow(context, filtered[index], api),
          ),
        ),
      ],
    );
  }

  Widget _buildListHeader(BuildContext context, List<FileItem> filtered) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          Checkbox(
            visualDensity: VisualDensity.compact,
            value: filtered.isEmpty ? false : (selectedItems.length == filtered.length ? true : (selectedItems.isEmpty ? false : null)),
            tristate: true,
            onChanged: onSelectAll,
          ),
          _buildHeaderCell(context, "Name", 0, flex: 4),
          if (showSizeColumn) _buildHeaderCell(context, "Size", 1, flex: 1),
          if (showTypeColumn) _buildHeaderCell(context, "Type", 2, flex: 1),
          if (showDateColumn) _buildHeaderCell(context, "Modified", 3, flex: 2),
          if (showActionMenu) const SizedBox(width: 48),
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
    final l10n = AppLocalizations.of(context)!;
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
                        borderRadius: BorderRadius.circular(2),
                        child: CachedNetworkImage(
                          imageUrl: '${api.baseUrl}/api/files/download?path=${Uri.encodeComponent(item.path)}&thumbnail=true',
                          fit: BoxFit.cover,
                          width: 24,
                          height: 24,
                          placeholder: (context, url) => Center(
                            child: SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (context, url, error) => Icon(
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
            if (showSizeColumn)
              Expanded(
                flex: 1,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(item.isDir ? "---" : _formatSize(item.size), style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                    ),
                    if (item.tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            l10n.taggedLabel,
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onPrimaryContainer),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (showTypeColumn) Expanded(flex: 1, child: Text(typeStr, style: const TextStyle(fontSize: 13, color: Colors.grey))),
            if (showDateColumn) Expanded(flex: 2, child: Text(dateStr, style: const TextStyle(fontSize: 13, color: Colors.grey))),
            if (showActionMenu) FileActionMenu(item: item, onActionSelected: onActionSelected),
          ],
        ),
      ),
    );
  }

  void _showMobileActionSheet(BuildContext context, FileItem item) {
    FileActionMenu(item: item, onActionSelected: onActionSelected).showSheet(context);
  }

  Widget _buildMobileListRow(BuildContext context, FileItem item, ApiService api) {
    final l10n = AppLocalizations.of(context)!;
    final themeExt = Theme.of(context).extension<AppThemeExtension>()!;
    final dateStr = DateFormat.yMMMd().add_jm().format(item.updatedAt);
    final extension = item.name.contains('.') ? item.name.split('.').last : null;
    final sizeStr = item.isDir ? "" : " • ${_formatSize(item.size)}";
    final tagStr = item.tags.isNotEmpty ? " • ${l10n.taggedLabel}" : "";
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
                  child: CachedNetworkImage(
                    imageUrl: '${api.baseUrl}/api/files/download?path=${Uri.encodeComponent(item.path)}&thumbnail=true',
                    fit: BoxFit.cover,
                    width: 48,
                    height: 48,
                    placeholder: (context, url) => const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
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
                      "$dateStr$sizeStr$tagStr",
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