import 'package:flutter/material.dart';

class BreadcrumbBar extends StatelessWidget {
  final List<String> pathStack;
  final Function(int) onPathPressed;

  const BreadcrumbBar({
    super.key,
    required this.pathStack,
    required this.onPathPressed,
  });

  static const int _maxVisibleItems = 5;

  @override
  Widget build(BuildContext context) {
    final breadcrumbWidgets = _buildBreadcrumbWidgets();

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      color: Colors.grey[100],
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: breadcrumbWidgets),
      ),
    );
  }

  List<Widget> _buildBreadcrumbWidgets() {
    if (pathStack.length <= _maxVisibleItems) {
      return _buildFullBreadcrumbs();
    }

    final visibleTrailingCount = _maxVisibleItems - 2;
    final trailingStart = pathStack.length - visibleTrailingCount;
    final widgets = <Widget>[];

    widgets.add(_breadcrumbItem(0));
    widgets.add(_separator());
    widgets.add(_collapsedBreadcrumb(1, trailingStart));
    widgets.add(_separator());

    for (var index = trailingStart; index < pathStack.length; index++) {
      widgets.add(_breadcrumbItem(index));
      if (index != pathStack.length - 1) {
        widgets.add(_separator());
      }
    }

    return widgets;
  }

  List<Widget> _buildFullBreadcrumbs() {
    return List<Widget>.generate(pathStack.length * 2 - 1, (widgetIndex) {
      final index = widgetIndex ~/ 2;
      if (widgetIndex.isOdd) return _separator();
      return _breadcrumbItem(index);
    });
  }

  Widget _breadcrumbItem(int index) {
    final isLast = index == pathStack.length - 1;
    final label = index == 0 ? '/' : pathStack[index].split('/').last;

    return TextButton(
      onPressed: isLast ? null : () => onPathPressed(index),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
          color: isLast ? Colors.black87 : Colors.blue,
        ),
      ),
    );
  }

  Widget _collapsedBreadcrumb(int startHiddenIndex, int endHiddenIndex) {
    final hiddenItems = pathStack.sublist(startHiddenIndex, endHiddenIndex);

    return PopupMenuButton<int>(
      tooltip: 'Show hidden folders',
      padding: EdgeInsets.zero,
      itemBuilder: (context) {
        return List<PopupMenuEntry<int>>.generate(hiddenItems.length, (menuIndex) {
          final actualIndex = startHiddenIndex + menuIndex;
          final label = pathStack[actualIndex].split('/').last;
          return PopupMenuItem<int>(
            value: actualIndex,
            child: Text(label.isEmpty ? '/' : label),
          );
        });
      },
      onSelected: (index) => onPathPressed(index),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4.0),
        child: Icon(Icons.more_horiz, size: 20, color: Colors.blue),
      ),
    );
  }

  Widget _separator() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.0),
      child: Icon(Icons.chevron_right, size: 16),
    );
  }
}
