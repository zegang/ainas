import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/asn1.dart';

class LicenseStatus {
  final bool valid;
  final Map<String, dynamic>? data;
  final int daysRemaining;
  final DateTime? issuedDate;
  final DateTime? expiresDate;
  final String? message;

  LicenseStatus({
    required this.valid,
    this.data,
    this.daysRemaining = 0,
    this.issuedDate,
    this.expiresDate,
    this.message,
  });
}

class LicService {
  LicService._internal();
  static final LicService _instance = LicService._internal();
  factory LicService() => _instance;

  final _log = Logger('LicService');

  // The RSA public key in PEM format used to verify license signatures.
  // Replace this with your actual public key for production.
  // You can generate one with: openssl genpkey -algorithm RSA -out private.pem
  //                          && openssl rsa -pubout -in private.pem -out public.pem
  static const String _kEmbeddedPublicKey = '''
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA4KiL/FqPnScWEDW4vTtH
3B0qWxRh4HfEFowEQFMO+pFo0bC/w0rmaErPS6p+zfPIdUNXE0sO+jJMFZjyH4lu
VGYJgvfrIyvcj7qvq3stlFtU1nqf/4+Gv2ch5Bnf5I60KJ6Mx4Nv+yimXpEdzSVS
3ktzWP4+TcU5jfeHnbDLrq9hvYeke4fvGFNVfpj1dPAMDdMf8ygbgjdF5UpViAiR
Wfh+jvcotjHZbtCBlPlzv6XL1KF6lo2mU/B/Dg2BL3P9Pwx0ZwVM6RhPoa25H+KZ
mtUwbqNtVYgkaC/WFsn4RwQeHSaxnAnYaHzE2JLqWLh4EsLly41gvUbTpIKObBjg
yQIDAQAB
-----END PUBLIC KEY-----
''';

  // ── Hardware Info ─────────────────────────────────────────────────────

  String? getCpuSerial() {
    if (kIsWeb) return null;
    try {
      if (Platform.isLinux) return _linuxCpuSerial();
      if (Platform.isMacOS) return _macosCpuSerial();
      if (Platform.isWindows) return _windowsCpuSerial();
    } catch (e) {
      _log.warning('getCpuSerial failed: $e');
    }
    return null;
  }

  String? _linuxCpuSerial() {
    // On x86/x64 there is no portable CPU serial number — build composite
    final proc = File('/proc/cpuinfo');
    if (!proc.existsSync()) return null;
    final lines = proc.readAsLinesSync();
    String model = '', flags = '';
    int physId = -1, coreId = -1;
    for (final line in lines) {
      final colon = line.indexOf(':');
      if (colon == -1) continue;
      final key = line.substring(0, colon).trim();
      final val = line.substring(colon + 1).trim();
      if (key == 'model name' && model.isEmpty) model = val;
      if (key == 'flags' && flags.isEmpty) flags = val;
      if (key == 'physical id' && physId < 0) physId = int.tryParse(val) ?? -1;
      if (key == 'core id' && coreId < 0) coreId = int.tryParse(val) ?? -1;
      if (key == 'processor' && model.isNotEmpty && flags.isNotEmpty) break;
    }
    if (model.isEmpty) model = 'unknown';
    if (flags.isEmpty) flags = 'unknown';
    return '$model::$physId::$coreId::$flags';
  }

  String? _macosCpuSerial() {
    final result = Process.runSync('sysctl', ['-n', 'machdep.cpu.brand_string']);
    return result.exitCode == 0 ? result.stdout.toString().trim() : null;
  }

  String? _windowsCpuSerial() {
    final result = Process.runSync('wmic', ['cpu', 'get', 'ProcessorId', '/value']);
    if (result.exitCode != 0) return null;
    for (final line in result.stdout.toString().split('\n')) {
      if (line.trim().startsWith('ProcessorId=')) {
        return line.split('=').last.trim();
      }
    }
    return null;
  }

  String? getMotherboardSerial() {
    if (kIsWeb) return null;
    try {
      if (Platform.isLinux) return _linuxMotherboardSerial();
      if (Platform.isMacOS) return _macosMotherboardSerial();
      if (Platform.isWindows) return _windowsMotherboardSerial();
    } catch (e) {
      _log.warning('getMotherboardSerial failed: $e');
    }
    return null;
  }

  String? _linuxMotherboardSerial() {
    String? read(String p) {
      final f = File(p);
      return f.existsSync() ? f.readAsStringSync().trim() : null;
    }
    var s = read('/sys/class/dmi/id/board_serial');
    s ??= read('/sys/devices/virtual/dmi/id/board_serial');
    if (s == null || s.isEmpty) return null;
    if (s.contains('O.E.M') || s.contains('Default')) return null;
    return s;
  }

  String? _macosMotherboardSerial() {
    final result = Process.runSync('ioreg', [
      '-rd1', '-c', 'IOPlatformExpertDevice',
    ]);
    if (result.exitCode != 0) return null;
    for (final line in result.stdout.toString().split('\n')) {
      if (line.contains('IOPlatformSerialNumber')) {
        final parts = line.split('"');
        return parts.length >= 4 ? parts[3] : null;
      }
    }
    return null;
  }

  String? _windowsMotherboardSerial() {
    final result = Process.runSync('wmic', ['baseboard', 'get', 'SerialNumber', '/value']);
    if (result.exitCode != 0) return null;
    for (final line in result.stdout.toString().split('\n')) {
      if (line.trim().startsWith('SerialNumber=')) {
        return line.split('=').last.trim();
      }
    }
    return null;
  }

  String? getDiskSerial() {
    if (kIsWeb) return null;
    try {
      if (Platform.isLinux) return _linuxDiskSerial();
      if (Platform.isMacOS) return _macosDiskSerial();
      if (Platform.isWindows) return _windowsDiskSerial();
    } catch (e) {
      _log.warning('getDiskSerial failed: $e');
    }
    return null;
  }

  String? _linuxDiskSerial() {
    // Parse /proc/mounts to find root device
    final mounts = File('/proc/mounts');
    if (!mounts.existsSync()) return null;
    String rootDev = '';
    for (final line in mounts.readAsLinesSync()) {
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 2 && parts[1] == '/') {
        rootDev = parts[0];
        break;
      }
    }
    if (rootDev.isEmpty) return null;
    // Strip /dev/ prefix
    if (rootDev.startsWith('/dev/')) rootDev = rootDev.substring(5);
    // Remove trailing digits (partition number)
    while (rootDev.isNotEmpty &&
        rootDev.codeUnitAt(rootDev.length - 1) >= 48 &&
        rootDev.codeUnitAt(rootDev.length - 1) <= 57) {
      rootDev = rootDev.substring(0, rootDev.length - 1);
    }
    // Handle NVMe: nvme0n1p1 -> nvme0n1
    final pIdx = rootDev.lastIndexOf('p');
    if (pIdx != -1 && rootDev.contains('nvme') && pIdx > 0) {
      final prev = rootDev.codeUnitAt(pIdx - 1);
      if (prev >= 48 && prev <= 57) rootDev = rootDev.substring(0, pIdx);
    }
    if (rootDev.isEmpty) return null;
    // Read serial
    final serial = File('/sys/block/$rootDev/serial');
    if (serial.existsSync()) {
      final s = serial.readAsStringSync().trim();
      if (s.isNotEmpty) return s;
    }
    // Fallback: device model
    final model = File('/sys/block/$rootDev/device/model');
    if (model.existsSync()) {
      final m = model.readAsStringSync().trim();
      if (m.isNotEmpty) return m;
    }
    return null;
  }

  String? _macosDiskSerial() {
    final result = Process.runSync('system_profiler', ['SPStorageDataType']);
    if (result.exitCode != 0) return null;
    for (final line in result.stdout.toString().split('\n')) {
      if (line.contains('Serial Number')) {
        final parts = line.split(':');
        return parts.length >= 2 ? parts.sublist(1).join(':').trim() : null;
      }
    }
    return null;
  }

  String? _windowsDiskSerial() {
    final result = Process.runSync('wmic', ['diskdrive', 'get', 'SerialNumber', '/value']);
    if (result.exitCode != 0) return null;
    for (final line in result.stdout.toString().split('\n')) {
      if (line.trim().startsWith('SerialNumber=')) {
        return line.split('=').last.trim();
      }
    }
    return null;
  }

  // ── Device Fingerprint ────────────────────────────────────────────────

  String generateDeviceFingerprint() {
    final parts = [
      getCpuSerial() ?? '',
      getMotherboardSerial() ?? '',
      getDiskSerial() ?? '',
    ];
    final combined = parts.join('');
    if (combined.isEmpty) return '';
    return sha256.convert(utf8.encode(combined)).toString();
  }

  // ── Storage Key (SHA-256 of fingerprint) ─────────────────────────────

  Uint8List _storageKey() {
    final fp = generateDeviceFingerprint();
    return Uint8List.fromList(sha256.convert(utf8.encode(fp)).bytes);
  }

  // ── Storage Path ─────────────────────────────────────────────────────

  Future<File> _storageFile() async {
    final dir = await getApplicationSupportDirectory();
    await dir.exists();
    return File('${dir.path}/license.enc');
  }

  /// Returns the full path of the stored license file.
  Future<String> licenseFilePath() async {
    final file = await _storageFile();
    return file.path;
  }

  // ── RSA Signature Verification ──────────────────────────────────────

  bool _rsaVerify(String message, Uint8List signature) {
    try {
      final publicKey = _parseRsaPublicKey(_kEmbeddedPublicKey);
      if (publicKey == null) return false;

      final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
      signer.init(false, PublicKeyParameter<RSAPublicKey>(publicKey));
      return signer.verifySignature(utf8.encode(message) as Uint8List,
          RSASignature(signature));
    } catch (e) {
      _log.warning('RSA verify failed: $e');
      return false;
    }
  }

  RSAPublicKey? _parseRsaPublicKey(String pem) {
    try {
      final lines = pem.trim().split('\n');
      final b64 = lines
          .where((l) => !l.startsWith('-----'))
          .map((l) => l.trim())
          .join();
      final der = base64.decode(b64);
      final parser = ASN1Parser(Uint8List.fromList(der));
      final seq = parser.nextObject() as ASN1Sequence;
      final bitString = seq.elements![1] as ASN1BitString;
      // BIT STRING value: first byte is unused bits, rest is DER-encoded inner SEQUENCE
      final innerBytes = bitString.valueBytes!.sublist(1);
      final inner = ASN1Parser(innerBytes).nextObject() as ASN1Sequence;
      final modulus = (inner.elements![0] as ASN1Integer).integer!;
      final exponent = (inner.elements![1] as ASN1Integer).integer!;
      return RSAPublicKey(modulus, exponent);
    } catch (e) {
      _log.warning('Failed to parse RSA public key: $e');
      return null;
    }
  }

  // ── AES-256-GCM ─────────────────────────────────────────────────────

  Uint8List _aesEncrypt(Uint8List plaintext, Uint8List key) {
    final iv = Uint8List.fromList(
      List<int>.generate(12, (_) => Random.secure().nextInt(256)),
    );

    final cipher = _aesCipher(true, key, iv);
    final output = cipher.process(plaintext);
    return Uint8List.fromList([...iv, ...output]);
  }

  Uint8List? _aesDecrypt(Uint8List cipherBlob, Uint8List key) {
    if (key.length != 32 || cipherBlob.length < 12 + 16) return null;
    try {
      const ivSize = 12;
      const tagSize = 16;
      final ctSize = cipherBlob.length - ivSize - tagSize;

      final iv = cipherBlob.sublist(0, ivSize);
      final ct = cipherBlob.sublist(ivSize, ivSize + ctSize);
      final tag = cipherBlob.sublist(ivSize + ctSize, ivSize + ctSize + tagSize);

      final cipher = _aesCipher(false, key, iv);
      final plaintext = cipher.process(Uint8List.fromList([...ct, ...tag]));
      return Uint8List.fromList(plaintext);
    } catch (e) {
      _log.warning('AES decrypt failed: $e');
      return null;
    }
  }

  GCMBlockCipher _aesCipher(bool forEncryption, Uint8List key, Uint8List iv) {
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      forEncryption,
      AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)),
    );
    return cipher;
  }

  // ── License JSON Parsing ─────────────────────────────────────────────

  Map<String, dynamic>? _parseLicenseJson(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      if (data['machine_fingerprint'] == null) return null;
      if (data['issued'] == null || data['expires'] == null) return null;
      return data;
    } catch (_) {
      return null;
    }
  }

  DateTime _nowUtc() => DateTime.now().toUtc();

  // ── Platform check ──────────────────────────────────────────────────

  static bool isDesktop() {
    if (kIsWeb) return false;
    return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  }

  // ── Public API ──────────────────────────────────────────────────────

  /// Check whether a valid, non-expired, device-bound license exists.
  Future<bool> isLicensed() async {
    if (!isDesktop()) return true;
    try {
      final file = await _storageFile();
      if (!await file.exists()) return false;

      final blob = await file.readAsBytes();
      if (blob.length < 12 + 16) return false;

      final key = _storageKey();
      if (key.isEmpty) return false;

      final plaintext = _aesDecrypt(Uint8List.fromList(blob), key);
      if (plaintext == null) return false;

      final payload = utf8.decode(plaintext);
      final data = _parseLicenseJson(payload);
      if (data == null) return false;

      // Check device binding
      final deviceFp = generateDeviceFingerprint();
      if (deviceFp.isEmpty || data['machine_fingerprint'] != deviceFp) return false;

      // Check not before issued
      final issued = DateTime.tryParse(data['issued'] as String);
      if (issued == null || _nowUtc().isBefore(issued)) return false;

      // Check expiry
      final expires = DateTime.tryParse(data['expires'] as String);
      if (expires == null || _nowUtc().isAfter(expires)) return false;

      return true;
    } catch (e) {
      _log.warning('isLicensed failed: $e');
      return false;
    }
  }

  /// Returns the license JSON payload if a valid license exists, or null.
  Future<Map<String, dynamic>?> licenseInfo() async {
    if (!isDesktop()) return null;
    try {
      final file = await _storageFile();
      if (!await file.exists()) return null;

      final blob = await file.readAsBytes();
      final key = _storageKey();
      if (key.isEmpty) return null;

      final plaintext = _aesDecrypt(Uint8List.fromList(blob), key);
      if (plaintext == null) return null;

      final payload = utf8.decode(plaintext);
      return _parseLicenseJson(payload);
    } catch (_) {
      return null;
    }
  }

  /// Import a license file's content. Returns true on success.
  Future<bool> importLicense(String licenseContent) async {
    if (!isDesktop()) return true;
    try {
      final lines = licenseContent.trim().split('\n');
      if (lines.length < 2) return false;

      final payload = lines[0].trim();
      final sigB64 = lines[1].trim();
      if (payload.isEmpty || sigB64.isEmpty) return false;

      final signature = base64.decode(sigB64);

      // Verify signature against embedded public key
      if (!_rsaVerify(payload, Uint8List.fromList(signature))) return false;

      // Verify device binding
      final data = _parseLicenseJson(payload);
      if (data == null) return false;

      final deviceFp = generateDeviceFingerprint();
      if (deviceFp.isEmpty || data['machine_fingerprint'] != deviceFp) return false;

      // Check not before issued
      final issued = DateTime.tryParse(data['issued'] as String);
      if (issued == null || _nowUtc().isBefore(issued)) return false;

      // Check expiry
      final expires = DateTime.tryParse(data['expires'] as String);
      if (expires == null || _nowUtc().isAfter(expires)) return false;

      // Encrypt and store
      final key = _storageKey();
      if (key.isEmpty) return false;

      final plaintext = Uint8List.fromList(utf8.encode(payload));
      final encrypted = _aesEncrypt(plaintext, key);

      final file = await _storageFile();
      await file.writeAsBytes(encrypted.toList());
      return true;
    } catch (e) {
      _log.warning('importLicense failed: $e');
      return false;
    }
  }

  /// Returns a list of all license files on this device.
  /// Currently only a single encrypted license file is supported.
  Future<List<LicenseStatus>> listLicenses() async {
    final status = await licenseStatus();
    return status.valid ? [status] : [];
  }

  /// Delete the stored license file from disk.
  Future<bool> deleteLicense() async {
    if (!isDesktop()) return false;
    try {
      final file = await _storageFile();
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      _log.warning('deleteLicense failed: $e');
      return false;
    }
  }

  /// Days until the license expires. Returns -1 if no valid license.
  Future<int> daysRemaining() async {
    final info = await licenseInfo();
    if (info == null) return -1;
    final expiresStr = info['expires'] as String?;
    if (expiresStr == null) return -1;
    final expires = DateTime.tryParse(expiresStr);
    if (expires == null) return -1;
    return expires.difference(_nowUtc()).inDays;
  }

  /// Returns a [LicenseStatus] with full validity detail.
  Future<LicenseStatus> licenseStatus() async {
    if (!isDesktop()) {
      return LicenseStatus(valid: true, daysRemaining: 36500,
          message: 'Not required on this platform');
    }
    try {
      final file = await _storageFile();
      if (!await file.exists()) {
        return LicenseStatus(valid: false, message: 'No license file');
      }

      final blob = await file.readAsBytes();
      if (blob.length < 12 + 16) {
        return LicenseStatus(valid: false, message: 'Corrupted license data');
      }

      final key = _storageKey();
      if (key.isEmpty) {
        return LicenseStatus(valid: false, message: 'No device key');
      }

      final plaintext = _aesDecrypt(Uint8List.fromList(blob), key);
      if (plaintext == null) {
        return LicenseStatus(valid: false, message: 'Decryption failed');
      }

      final payload = utf8.decode(plaintext);
      final data = _parseLicenseJson(payload);
      if (data == null) {
        return LicenseStatus(valid: false, message: 'Invalid license format');
      }

      // Check device binding
      final deviceFp = generateDeviceFingerprint();
      final issuedDate = DateTime.tryParse(data['issued'] as String);
      final expiresDate = DateTime.tryParse(data['expires'] as String);

      if (deviceFp.isEmpty || data['machine_fingerprint'] != deviceFp) {
        return LicenseStatus(
          valid: false,
          data: data,
          message: 'Device mismatch',
          issuedDate: issuedDate,
          expiresDate: expiresDate,
        );
      }

      final now = _nowUtc();
      final remaining = expiresDate != null
          ? expiresDate.difference(now).inDays
          : 0;

      if (issuedDate == null || now.isBefore(issuedDate)) {
        return LicenseStatus(
          valid: false,
          data: data,
          daysRemaining: remaining,
          issuedDate: issuedDate,
          expiresDate: expiresDate,
          message: 'License not yet valid',
        );
      }

      if (expiresDate == null || now.isAfter(expiresDate)) {
        return LicenseStatus(
          valid: false,
          data: data,
          daysRemaining: remaining,
          issuedDate: issuedDate,
          expiresDate: expiresDate,
          message: 'License expired',
        );
      }

      return LicenseStatus(
        valid: true,
        data: data,
        daysRemaining: remaining,
        issuedDate: issuedDate,
        expiresDate: expiresDate,
        message: remaining <= 30 ? 'Expiring soon' : null,
      );
    } catch (e) {
      return LicenseStatus(valid: false, message: 'Error: $e');
    }
  }

  /// Returns a map of hardware identifiers.
  Map<String, String> hardwareInfo() {
    return {
      'cpu_serial': getCpuSerial() ?? '',
      'motherboard_serial': getMotherboardSerial() ?? '',
      'disk_serial': getDiskSerial() ?? '',
      'device_fingerprint': generateDeviceFingerprint(),
    };
  }
}
