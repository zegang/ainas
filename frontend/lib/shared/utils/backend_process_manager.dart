import 'dart:io';

import 'package:flutter/foundation.dart';

class ProcessInfo {
  final int pid;
  final String commandLine;
  final int memoryKb;
  final String uptime;
  final double cpuPercent;

  ProcessInfo({
    required this.pid,
    this.commandLine = '',
    this.memoryKb = 0,
    this.uptime = '',
    this.cpuPercent = 0.0,
  });
}

class BackendProcessManager {
  static bool get isDesktopSupported =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  static Future<List<ProcessInfo>> listProcessDetails() async {
    final pids = await listPids();
    if (pids.isEmpty) return [];
    final results = <ProcessInfo>[];
    for (final pid in pids) {
      results.add(await _processInfo(pid));
    }
    return results;
  }

  static Future<ProcessInfo> _processInfo(int pid) async {
    if (Platform.isLinux) {
      return _linuxProcessInfo(pid);
    }
    if (Platform.isMacOS) {
      return _macosProcessInfo(pid);
    }
    if (Platform.isWindows) {
      return _windowsProcessInfo(pid);
    }
    return ProcessInfo(pid: pid);
  }

  static Future<ProcessInfo> _linuxProcessInfo(int pid) async {
    String cmdline = '';
    int memoryKb = 0;
    String uptime = '';
    double cpu = 0.0;
    try {
      final fCmd = File('/proc/$pid/cmdline');
      if (await fCmd.exists()) {
        cmdline = (await fCmd.readAsBytes())
            .map((b) => b == 0 ? 32 : b)
            .where((b) => b >= 32)
            .map((b) => String.fromCharCode(b))
            .join()
            .trim();
      }
      final fStatus = File('/proc/$pid/status');
      if (await fStatus.exists()) {
        for (final line in await fStatus.readAsLines()) {
          if (line.startsWith('VmRSS:')) {
            memoryKb = int.tryParse(line.split(RegExp(r'\s+'))[1]) ?? 0;
          }
        }
      }
      final fStat = File('/proc/$pid/stat');
      if (await fStat.exists()) {
        final content = await fStat.readAsString();
        final idx = content.lastIndexOf(')');
        if (idx >= 0) {
          final fields = content.substring(idx + 2).split(' ');
          if (fields.length >= 22) {
            final startTicks = int.tryParse(fields[19]) ?? 0;
            final clkTck = _clockTicksPerSecond();
            final uptimeSeconds = _systemUptimeSeconds();
            final runSeconds = uptimeSeconds - (startTicks / clkTck);
            if (runSeconds > 0) {
              uptime = _formatDuration(Duration(seconds: runSeconds.toInt()));
            }
          }
          if (fields.length >= 15) {
            final utime = int.tryParse(fields[11]) ?? 0;
            final stime = int.tryParse(fields[12]) ?? 0;
            final clkTck = _clockTicksPerSecond();
            final totalSeconds = (utime + stime) / clkTck;
            final uptimeSeconds = _systemUptimeSeconds();
            if (uptimeSeconds > 0) {
              cpu = (totalSeconds / uptimeSeconds * 100).clamp(0, 100);
            }
          }
        }
      }
    } catch (_) {}
    return ProcessInfo(pid: pid, commandLine: cmdline, memoryKb: memoryKb, uptime: uptime, cpuPercent: cpu);
  }

  static int _clockTicksPerSecond() {
    try {
      return int.parse(File('/proc/self/auxv').readAsBytesSync().last.toString());
    } catch (_) {
      return 100; // common default
    }
  }

  static double _systemUptimeSeconds() {
    try {
      final content = File('/proc/uptime').readAsStringSync();
      return double.tryParse(content.split(' ').first) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static String _formatDuration(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours.remainder(24)}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    return '${d.inSeconds}s';
  }

  static Future<ProcessInfo> _macosProcessInfo(int pid) async {
    try {
      final result = await Process.run('ps', ['-o', 'pid=,comm=,rss=,pcpu=,etime=', '-p', pid.toString()]);
      if (result.exitCode == 0) {
        final line = result.stdout.toString().trim();
        if (line.isEmpty) return ProcessInfo(pid: pid);
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 5) {
          return ProcessInfo(
            pid: pid,
            commandLine: parts[1],
            memoryKb: int.tryParse(parts[2]) ?? 0,
            cpuPercent: double.tryParse(parts[3]) ?? 0.0,
            uptime: parts[4],
          );
        }
      }
    } catch (_) {}
    return ProcessInfo(pid: pid);
  }

  static Future<ProcessInfo> _windowsProcessInfo(int pid) async {
    try {
      final result = await Process.run('wmic', [
        'process', 'where', 'ProcessId=$pid',
        'get', 'CommandLine,WorkingSetSize',
        '/format:csv',
      ]);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().trim().split('\n');
        for (int i = 1; i < lines.length; i++) {
          final cells = lines[i].split(',');
          if (cells.length >= 2) {
            return ProcessInfo(
              pid: pid,
              commandLine: cells[0].trim(),
              memoryKb: (int.tryParse(cells[1].trim()) ?? 0) ~/ 1024,
            );
          }
        }
      }
    } catch (_) {}
    return ProcessInfo(pid: pid);
  }

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
