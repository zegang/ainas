import 'package:flutter/material.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';

class FileFilterSheet extends StatefulWidget {
  final Map<String, dynamic> initial;
  final List<String> availableTags;
  const FileFilterSheet({super.key, this.initial = const {}, this.availableTags = const []});

  @override
  State<FileFilterSheet> createState() => _FileFilterSheetState();
}

class _FileFilterSheetState extends State<FileFilterSheet> {
  final Map<String, bool> _types = {
    'images': false,
    'pdf': false,
    'docx': false,
    'videos': false,
    'others': false,
  };
  final Set<String> _selectedTagChips = {};

  void _apply() {
    final selected = <String>{};
    _types.forEach((k, v) {
      if (v) selected.add(k);
    });
    Navigator.of(context).pop({'types': selected, 'tags': _selectedTagChips.join(', ')});
  }

  void _clear() {
    _types.keys.forEach((k) => _types[k] = false);
    _selectedTagChips.clear();
    Navigator.of(context).pop(<String, dynamic>{});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final style = TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant);

    Widget _sectionHeader(IconData icon, String label, {int? count}) {
      return Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (count != null && count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(10)),
              child: Text('$count', style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer)),
            ),
          ],
        ],
      );
    }

    return SafeArea(
      child: Material(
        color: cs.surface,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.filterTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      _sectionHeader(Icons.label_outline, l10n.filterTagsLabel, count: _selectedTagChips.length),
                      const SizedBox(height: 10),
                      if (widget.availableTags.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(l10n.filterTagsEmpty, style: style),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: widget.availableTags.map((tag) {
                            final sel = _selectedTagChips.contains(tag);
                            return FilterChip(
                              label: Text(tag, style: TextStyle(fontSize: 13, color: sel ? cs.onSecondaryContainer : cs.onSurface)),
                              selected: sel,
                              selectedColor: cs.secondaryContainer,
                              checkmarkColor: cs.onSecondaryContainer,
                              visualDensity: VisualDensity.compact,
                              onSelected: (val) => setState(() => val ? _selectedTagChips.add(tag) : _selectedTagChips.remove(tag)),
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 20),
                      _sectionHeader(Icons.category_outlined, l10n.filterTypeLabel),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: _types.keys.map((k) {
                          IconData icon;
                          String label;
                          switch (k) {
                            case 'images':
                              icon = Icons.image_outlined;
                              label = l10n.filterTypeImages;
                              break;
                            case 'pdf':
                              icon = Icons.picture_as_pdf_outlined;
                              label = l10n.filterTypePdf;
                              break;
                            case 'docx':
                              icon = Icons.description_outlined;
                              label = l10n.filterTypeDocx;
                              break;
                            case 'videos':
                              icon = Icons.videocam_outlined;
                              label = l10n.filterTypeVideos;
                              break;
                            default:
                              icon = Icons.insert_drive_file_outlined;
                              label = l10n.filterTypeOthers;
                          }
                          final sel = _types[k]!;
                          return FilterChip(
                            avatar: Icon(icon, size: 18, color: sel ? cs.onSecondaryContainer : cs.onSurfaceVariant),
                            label: Text(label, style: TextStyle(fontSize: 13, color: sel ? cs.onSecondaryContainer : cs.onSurface)),
                            selected: sel,
                            selectedColor: cs.secondaryContainer,
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            onSelected: (val) => setState(() => _types[k] = val),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _clear,
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                            side: BorderSide(color: cs.outline),
                            padding: const EdgeInsets.symmetric(vertical: 14.0),
                          ),
                          child: Text(l10n.clear),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _apply,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: cs.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                            padding: const EdgeInsets.symmetric(vertical: 14.0),
                          ),
                          child: Text(l10n.applyButton, style: TextStyle(color: cs.onPrimary)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
