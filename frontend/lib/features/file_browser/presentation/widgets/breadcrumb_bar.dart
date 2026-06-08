import 'package:flutter/material.dart';

class BreadcrumbBar extends StatelessWidget {
  final List<String> pathStack;
  final Function(int) onPathPressed;

  const BreadcrumbBar({
    super.key,
    required this.pathStack,
    required this.onPathPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      color: Colors.grey[100],
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: pathStack.length,
        separatorBuilder: (context, index) => const Icon(Icons.chevron_right, size: 16),
        itemBuilder: (context, index) {
          final isLast = index == pathStack.length - 1;
          final label = index == 0 ? "/" : pathStack[index].split('/').last;
          
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
        },
      ),
    );
  }
}