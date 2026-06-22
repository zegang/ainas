import 'package:flutter/material.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';
import 'package:ainas_frontend/shared/models/file_item.dart';

class ActionItem {
  final String value;
  final IconData icon;
  final String label;
  final bool isDestructive;
  const ActionItem(this.value, this.icon, this.label, {this.isDestructive = false});
}

List<ActionItem> _buildActions(AppLocalizations l10n) => [
  ActionItem('rename', Icons.edit_outlined, l10n.renameAction),
  ActionItem('move', Icons.drive_file_move_outlined, l10n.moveAction),
  ActionItem('attach', Icons.auto_awesome_outlined, l10n.attachToAiAction),
  ActionItem('download', Icons.download_outlined, l10n.downloadAction),
  ActionItem('delete', Icons.delete_outlined, l10n.deleteAction, isDestructive: true),
];

class FileActionMenu extends StatelessWidget {
  final FileItem item;
  final Function(String, FileItem) onActionSelected;

  const FileActionMenu({
    super.key,
    required this.item,
    required this.onActionSelected,
  });

  void _showSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final actions = _buildActions(l10n);
    final rows = [actions.sublist(0, 3), actions.sublist(3)];

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 14, color: cs.primary),
                      const SizedBox(width: 4),
                      Text(l10n.aiTags, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.tags.join(', '),
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              if (item.tags.isNotEmpty)
                const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: rows.map((row) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: row.map((a) => ActionTile(
                        icon: a.icon,
                        label: a.label,
                        color: a.isDestructive ? cs.error : cs.onSurface,
                        onTap: () {
                          Navigator.pop(ctx);
                          onActionSelected(a.value, item);
                        },
                      )).toList(),
                    ),
                  )).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    if (!isMobile) {
      final l10n = AppLocalizations.of(context)!;
      return PopupMenuButton<String>(
        onSelected: (value) => onActionSelected(value, item),
        itemBuilder: (context) => [
          if (item.tags.isNotEmpty)
            PopupMenuItem(
              enabled: false,
              padding: EdgeInsets.zero,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, size: 12, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(l10n.aiTags, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4, runSpacing: 4,
                      children: item.tags.take(6).map((tag) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(tag, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onPrimaryContainer)),
                      )).toList()
                        ..addAll(item.tags.length > 6
                          ? [Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              child: Text('+${item.tags.length - 6}', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
                            )]
                          : []),
                    ),
                  ],
                ),
              ),
            ),
          if (item.tags.isNotEmpty) const PopupMenuDivider(),
          PopupMenuItem(value: 'rename', child: Text(l10n.renameAction)),
          PopupMenuItem(value: 'move', child: Text(l10n.moveAction)),
          PopupMenuItem(value: 'attach', child: Text(l10n.attachToAiAction)),
          PopupMenuItem(value: 'download', child: Text(l10n.downloadAction)),
          PopupMenuItem(value: 'delete', child: Text(l10n.deleteAction)),
        ],
      );
    }
    return IconButton(
      icon: const Icon(Icons.more_vert),
      onPressed: () => _showSheet(context),
    );
  }
}

class FileActionBar extends StatelessWidget {
  final FileItem item;
  final Function(String, FileItem) onActionSelected;
  final Color iconColor;
  final double iconSize;
  final MainAxisAlignment mainAxisAlignment;

  const FileActionBar({
    super.key,
    required this.item,
    required this.onActionSelected,
    this.iconColor = Colors.white,
    this.iconSize = 36,
    this.mainAxisAlignment = MainAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final actions = _buildActions(l10n);
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = Row(
          mainAxisAlignment: mainAxisAlignment,
          children: actions.map((a) => ActionTile(
            icon: a.icon,
            label: a.label,
            color: a.isDestructive ? cs.error : iconColor,
            iconSize: iconSize,
            onTap: () => onActionSelected(a.value, item),
          )).toList(),
        );
        final tileHeight = iconSize + 24;
        if (tileHeight > constraints.maxHeight) {
          return SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: content,
            ),
          );
        } else {
          return Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: content,
            ),
          );
        }
      },
    );
  }
}

class ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final double iconSize;
  final VoidCallback onTap;

  const ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    this.iconSize = 36,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final size = iconSize;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: size + 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: size, height: size,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: size * 0.5),
              ),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 11, color: color), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}