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
    'others': false,
  };
  final Set<String> _selectedTagChips = {};
  late TextEditingController _tagsController;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init['types'] != null) {
      for (final t in (init['types'] as Set).cast<String>()) {
        if (_types.containsKey(t)) _types[t] = true;
      }
    }
    _tagsController = TextEditingController(text: init['tags'] ?? '');
    // initialize selected chips from initial tags
    if (init['tags'] != null && (init['tags'] as String).trim().isNotEmpty) {
      for (final t in (init['tags'] as String).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
        _selectedTagChips.add(t);
      }
    }
  }

  @override
  void dispose() {
    _tagsController.dispose();
    super.dispose();
  }

  void _apply() {
    final selected = <String>{};
    _types.forEach((k, v) {
      if (v) selected.add(k);
    });
    // merge selected chips and freeform tags
    final fromText = _tagsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    final merged = {..._selectedTagChips, ...fromText};
    Navigator.of(context).pop({'types': selected, 'tags': merged.join(', ')});
  }

  void _clear() {
    _types.keys.forEach((k) => _types[k] = false);
    _tagsController.clear();
    _selectedTagChips.clear();
    Navigator.of(context).pop(<String, dynamic>{});
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
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
                      Text(AppLocalizations.of(context)!.filterTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Text(AppLocalizations.of(context)!.filterTagsLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: widget.availableTags.map((tag) {
                          final selected = _selectedTagChips.contains(tag);
                          return FilterChip(
                            label: Text(tag),
                            selected: selected,
                            onSelected: (val) => setState(() {
                              if (val) {
                                _selectedTagChips.add(tag);
                              } else {
                                _selectedTagChips.remove(tag);
                              }
                              // reflect into text field for visibility
                              _tagsController.text = (_selectedTagChips.toList() + _tagsController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()).join(', ');
                            }),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      Text(AppLocalizations.of(context)!.filterTypeLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Wrap(
                        spacing: 8,
                        children: _types.keys.map((k) {
                          String label;
                          switch (k) {
                            case 'images':
                              label = AppLocalizations.of(context)!.filterTypeImages;
                              break;
                            case 'pdf':
                              label = AppLocalizations.of(context)!.filterTypePdf;
                              break;
                            case 'docx':
                              label = AppLocalizations.of(context)!.filterTypeDocx;
                              break;
                            default:
                              label = AppLocalizations.of(context)!.filterTypeOthers;
                          }

                          return FilterChip(
                            label: Text(label),
                            selected: _types[k]!,
                            onSelected: (val) => setState(() => _types[k] = val),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      TextField(controller: _tagsController, decoration: InputDecoration(hintText: AppLocalizations.of(context)!.filterTagsHint)),
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
                            side: BorderSide(color: Theme.of(context).colorScheme.outline),
                            padding: const EdgeInsets.symmetric(vertical: 14.0),
                          ),
                          child: Text(AppLocalizations.of(context)!.clear),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _apply,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                            padding: const EdgeInsets.symmetric(vertical: 14.0),
                          ),
                          child: Text(AppLocalizations.of(context)!.applyButton, style: const TextStyle(color: Colors.white)),
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
