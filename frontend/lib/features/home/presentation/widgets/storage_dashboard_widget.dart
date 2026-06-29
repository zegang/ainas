import 'package:flutter/material.dart';
import 'package:ainas_frontend/l10n/app_localizations.dart';

class StorageDashboardWidget extends StatelessWidget {
  final Map<String, dynamic>? usageData;
  final VoidCallback? onRefresh;

  const StorageDashboardWidget({super.key, this.usageData, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (usageData == null) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(child: Text(l10n.loadingStorageUsage)),
        ),
      );
    }

    // Prefer using a pre-calculated percentage from the backend if available.
    // Backend services often return 'percent_used' or simply 'percent'.
    double percent = (usageData!['percent_used'] as num?)?.toDouble() ?? 
                     (usageData!['percent'] as num?)?.toDouble() ?? -1.0;

    final double total = (usageData!['total_gb'] as num?)?.toDouble() ?? 0.0;
    final double free = (usageData!['free_gb'] as num?)?.toDouble() ?? 0.0;

    // Fallback calculation if the specific percentage field is missing or invalid.
    if (percent < 0) {
      percent = (total > 0) ? (((total - free) / total) * 100.0) : 0.0;
    }
    
    final color = percent > 90 ? Colors.red : (percent > 70 ? Colors.orange : Colors.green);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.nasStorageStatus, style: Theme.of(context).textTheme.titleMedium),
                if (onRefresh != null)
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: onRefresh,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: percent / 100,
              backgroundColor: color.withOpacity(0.1),
              color: color,
              minHeight: 12,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.percentUsed(percent.toStringAsFixed(1)),
                  style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                Text(l10n.freeOfTotal(free.toStringAsFixed(1), total.toStringAsFixed(1)),
                  style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            if (percent > 90)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(l10n.storageAlmostFull, 
                  style: TextStyle(color: Colors.red[700], fontSize: 12, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }
}