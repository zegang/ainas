class SyncPair {
  final int id;
  final String name;
  final String sourcePath;
  final String targetPath;
  final int syncIntervalSecs;
  final String syncPolicy;
  final String syncTime;
  final String? lastSyncedAt;
  final bool enabled;
  final bool deleteAfterSync;
  final String? createdAt;
  final String? updatedAt;

  SyncPair({
    required this.id,
    required this.name,
    required this.sourcePath,
    required this.targetPath,
    this.syncIntervalSecs = 0,
    this.syncPolicy = 'interval',
    this.syncTime = '',
    this.lastSyncedAt,
    this.enabled = true,
    this.deleteAfterSync = false,
    this.createdAt,
    this.updatedAt,
  });

  factory SyncPair.fromJson(Map<String, dynamic> json) {
    return SyncPair(
      id: json['id'] as int,
      name: json['name'] as String,
      sourcePath: json['source_path'] as String,
      targetPath: json['target_path'] as String,
      syncIntervalSecs: (json['sync_interval_secs'] as int?) ?? 0,
      syncPolicy: (json['sync_policy'] as String?) ?? 'interval',
      syncTime: (json['sync_time'] as String?) ?? '',
      lastSyncedAt: json['last_synced_at'] as String?,
      enabled: json['enabled'] is int ? (json['enabled'] as int) != 0 : (json['enabled'] as bool?) ?? true,
      deleteAfterSync: json['delete_after_sync'] is int ? (json['delete_after_sync'] as int) != 0 : (json['delete_after_sync'] as bool?) ?? false,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'source_path': sourcePath,
      'target_path': targetPath,
      'sync_interval_secs': syncIntervalSecs,
      'delete_after_sync': deleteAfterSync,
      'sync_policy': syncPolicy,
      'sync_time': syncTime,
    };
  }

  SyncPair copyWith({
    int? id,
    String? name,
    String? sourcePath,
    String? targetPath,
    int? syncIntervalSecs,
    String? syncPolicy,
    String? syncTime,
    String? lastSyncedAt,
    bool? enabled,
    bool? deleteAfterSync,
    String? createdAt,
    String? updatedAt,
  }) {
    return SyncPair(
      id: id ?? this.id,
      name: name ?? this.name,
      sourcePath: sourcePath ?? this.sourcePath,
      targetPath: targetPath ?? this.targetPath,
      syncIntervalSecs: syncIntervalSecs ?? this.syncIntervalSecs,
      syncPolicy: syncPolicy ?? this.syncPolicy,
      syncTime: syncTime ?? this.syncTime,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      enabled: enabled ?? this.enabled,
      deleteAfterSync: deleteAfterSync ?? this.deleteAfterSync,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
