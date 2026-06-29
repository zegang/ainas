import 'dart:io';

import 'package:flutter/foundation.dart';

class BackendProcessManager {
  static bool get isDesktopSupported =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  static Future<List<int>> listPids() async {
    if (!isDesktopSupported) return [];
    try {
      if (Platform.isWindows) {
        final result = await Process.run(
          'tasklist',
          ['/FI', 'IMAGENAME eq ainas-backend-cpp.exe', '/FO', 'CSV'],
        );
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().trim().split('\n');
          if (lines.length > 1) {
            return [for (int i = 1; i < lines.length; i++) _parseWindowsPid(lines[i])]
              ..removeWhere((p) => p == 0);
          }
        }
        return [];
      }

      for (final pattern in ['ainas-backend-cpp', 'backend-cpp', 'backend_cpp']) {
        final result = await Process.run('pgrep', ['-f', pattern]);
        if (result.exitCode == 0) {
          return result.stdout
              .toString()
              .trim()
              .split('\n')
              .where((s) => s.trim().isNotEmpty)
              .map((s) => int.tryParse(s.trim()) ?? 0)
              .where((p) => p > 0)
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  static int _parseWindowsPid(String line) {
    try {
      final parts = line.split('","');
      if (parts.length >= 2) {
        return int.tryParse(parts[1].replaceAll('"', '')) ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  static Future<bool> stopProcess(int pid) async {
    if (!isDesktopSupported || pid <= 0) return false;
    try {
      if (Platform.isWindows) {
        final result = await Process.run('taskkill', ['/PID', pid.toString(), '/F']);
        return result.exitCode == 0;
      }
      final result = await Process.run('kill', [pid.toString()]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> startProcess(String binaryPath, {List<String> args = const []}) async {
    if (!isDesktopSupported || binaryPath.isEmpty) return false;
    try {
      await Process.start(binaryPath, args, mode: ProcessStartMode.detached);
      return true;
    } catch (_) {
      return false;
    }
  }
}
