import 'package:flutter/material.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/shared/models/file_item.dart';

class FileActionMenu extends StatelessWidget {
  final FileItem item;
  final Function(String, FileItem) onActionSelected;

  const FileActionMenu({
    super.key,
    required this.item,
    required this.onActionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return PopupMenuButton<String>(
      onSelected: (value) => onActionSelected(value, item),
      itemBuilder: (context) {
        return [
          if (item.tags.isNotEmpty)
            PopupMenuItem(
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.aiTags,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.outline),
                  ),
                  Text(
                    item.tags.join(', '),
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          if (item.tags.isNotEmpty) const PopupMenuDivider(),
          PopupMenuItem(value: 'rename', child: Text(l10n.renameAction)),
          PopupMenuItem(value: 'move', child: Text(l10n.moveAction)),
          PopupMenuItem(value: 'attach', child: Text(l10n.attachToAiAction)),
          PopupMenuItem(value: 'download', child: Text(l10n.downloadAction)),
          PopupMenuItem(value: 'delete', child: Text(l10n.deleteAction)),
        ];
      },
    );
  }
}