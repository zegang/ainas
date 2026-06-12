import 'package:flutter/material.dart';

/// Custom design tokens for the AI-NAS project.
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  final Color folderIconColor;
  final Color fileIconColor;
  final Color successColor;
  final Color storageTrackColor;
  final Map<String, Color> extensionColors;

  const AppThemeExtension({
    required this.folderIconColor,
    required this.fileIconColor,
    required this.successColor,
    required this.storageTrackColor,
    required this.extensionColors,
  });

  /// Resolves a color based on the file extension (case-insensitive).
  /// Returns [fileIconColor] if no specific mapping is found.
  Color getFileColor(String? extension) {
    if (extension == null) return fileIconColor;
    return extensionColors[extension.toLowerCase()] ?? fileIconColor;
  }

  @override
  ThemeExtension<AppThemeExtension> copyWith({
    Color? folderIconColor,
    Color? fileIconColor,
    Color? successColor,
    Color? storageTrackColor,
    Map<String, Color>? extensionColors,
  }) {
    return AppThemeExtension(
      folderIconColor: folderIconColor ?? this.folderIconColor,
      fileIconColor: fileIconColor ?? this.fileIconColor,
      successColor: successColor ?? this.successColor,
      storageTrackColor: storageTrackColor ?? this.storageTrackColor,
      extensionColors: extensionColors ?? this.extensionColors,
    );
  }

  @override
  ThemeExtension<AppThemeExtension> lerp(ThemeExtension<AppThemeExtension>? other, double t) {
    if (other is! AppThemeExtension) return this;
    return AppThemeExtension(
      folderIconColor: Color.lerp(folderIconColor, other.folderIconColor, t)!,
      fileIconColor: Color.lerp(fileIconColor, other.fileIconColor, t)!,
      successColor: Color.lerp(successColor, other.successColor, t)!,
      storageTrackColor: Color.lerp(storageTrackColor, other.storageTrackColor, t)!,
      // Maps don't lerp linearly; we switch at the midpoint
      extensionColors: t < 0.5 ? extensionColors : other.extensionColors,
    );
  }
}

class AppTheme {
  static const _seedColor = Colors.blue;

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    );
    return _buildTheme(colorScheme).copyWith(
      extensions: [
        AppThemeExtension(
          folderIconColor: Colors.amber[700]!,
          fileIconColor: Colors.blueGrey[600]!,
          successColor: Colors.green[700]!,
          storageTrackColor: Colors.grey[300]!,
          extensionColors: {
            'pdf': Colors.red[700]!,
            'xlsx': Colors.green[700]!,
            'xls': Colors.green[700]!,
            'docx': Colors.blue[700]!,
          },
        ),
      ],
    );
  }

  static ThemeData get dark {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    );
    return _buildTheme(colorScheme).copyWith(
      extensions: [
        AppThemeExtension(
          folderIconColor: Colors.amber[300]!,
          fileIconColor: Colors.blueGrey[200]!,
          successColor: Colors.green[300]!,
          storageTrackColor: Colors.grey[800]!,
          extensionColors: {
            'pdf': Colors.red[300]!,
            'xlsx': Colors.green[300]!,
            'xls': Colors.green[300]!,
            'docx': Colors.blue[300]!,
          },
        ),
      ],
    );
  }

  static ThemeData _buildTheme(ColorScheme colorScheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surface,
        selectedIconTheme: IconThemeData(color: colorScheme.primary),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}