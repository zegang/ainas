import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'storage_mobile_page.dart';
import 'storage_desktop_page.dart';

class StoragePage extends StatelessWidget {
  const StoragePage({super.key});

  bool get _isDesktop =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  Widget build(BuildContext context) {
    if (_isDesktop) {
      return const StorageDesktopPage();
    }
    return const StorageMobilePage();
  }
}
