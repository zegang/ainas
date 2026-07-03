import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'settings_service.dart';
import 'db_service.dart';

class UserService with ChangeNotifier {
  UserService._internal();

  static final UserService _instance = UserService._internal();

  factory UserService() => _instance;

  final _log = Logger('UserService');

  String get _baseUrl => SettingsService().baseUrl;

  DbService _db = SharedPrefDbService();

  set dbService(DbService service) {
    _db = service;
  }

  static const String _loggedInKey = 'nas_logged_in';
  static const String _usernameKey = 'nas_username';
  static const String _vipStatusKey = 'nas_vip_status';
  static const String _roleKey = 'nas_role';

  bool isLoggedIn = false;
  String username = 'Guest';
  String vipStatus = 'Visitor';
  String role = '';

  bool get isAdmin => role == 'admin';

  Future<void> loadSettings() async {
    isLoggedIn = (await _db.getBool(_loggedInKey)) ?? false;
    username = (await _db.getString(_usernameKey)) ?? 'Guest';
    vipStatus = (await _db.getString(_vipStatusKey)) ?? (isLoggedIn ? 'VIP Member' : 'Visitor');
    role = (await _db.getString(_roleKey)) ?? '';
    if (!isLoggedIn) {
      username = 'Guest';
      vipStatus = 'Visitor';
      role = '';
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>?> getUserInfo() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/user/info'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final name = data['username'] as String?;
        if (name != null && name.isNotEmpty) {
          username = name;
        }
        vipStatus = data['vip_status'] as String? ?? vipStatus;
        role = data['role'] as String? ?? role;
        notifyListeners();
        return data;
      }
    } catch (e) {
      _log.warning('getUserInfo failed (endpoint may not exist): $e');
    }
    return null;
  }

  Future<bool> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/user/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username, 'password': password}),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final name = data['username'] as String? ?? username;
        final vip = data['vip_status'] as String? ?? 'VIP Member';
        final r = data['role'] as String? ?? '';
        await _db.setBool(_loggedInKey, true);
        await _db.setString(_usernameKey, name);
        await _db.setString(_vipStatusKey, vip);
        await _db.setString(_roleKey, r);
        isLoggedIn = true;
        this.username = name;
        vipStatus = vip;
        role = r;
        notifyListeners();
        _log.info('User logged in: $name (role: $r)');
        return true;
      }
      _log.warning('Login failed: ${response.statusCode} ${response.body}');
      return false;
    } catch (e) {
      _log.warning('Login API call failed, falling back to local: $e');
    }

    await _db.setBool(_loggedInKey, true);
    await _db.setString(_usernameKey, username);
    await _db.setString(_vipStatusKey, 'VIP Member');
    await _db.setString(_roleKey, '');
    isLoggedIn = true;
    this.username = username;
    vipStatus = 'VIP Member';
    role = '';
    notifyListeners();
    _log.info('User logged in (local): $username');
    return true;
  }

  Future<void> logout() async {
    try {
      await http
          .post(Uri.parse('$_baseUrl/api/user/logout'))
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      _log.warning('logout API call failed (endpoint may not exist): $e');
    }
    await _db.setBool(_loggedInKey, false);
    await _db.setString(_usernameKey, 'Guest');
    await _db.setString(_vipStatusKey, 'Visitor');
    await _db.setString(_roleKey, '');
    isLoggedIn = false;
    username = 'Guest';
    vipStatus = 'Visitor';
    role = '';
    notifyListeners();
    _log.info('User logged out');
  }

  /// Register a user with the given role.
  /// Returns null on success, or an error message string on failure.
  /// For admin role: falls back to local-only registration if backend is unreachable.
  /// For user role: requires backend to succeed.
  Future<String?> register(String username, String password,
                           {String role = 'user'}) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/user/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
          'role': role,
        }),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 201 || response.statusCode == 200) {
        _log.info('User registered via server: $username (role: $role)');
        return null;
      }
      final data = json.decode(response.body);
      final msg = data['message'] as String? ?? 'Registration failed';
      _log.warning('Register failed: $msg');
      // For admin, fall through to local fallback below
      if (role != 'admin') return msg;
    } catch (e) {
      _log.warning('Register API call failed: $e');
      if (role != 'admin') return 'Failed to connect to server';
    }

    // Admin fallback: store locally
    if (role == 'admin') {
      await _db.setBool(_loggedInKey, true);
      await _db.setString(_usernameKey, username);
      await _db.setString(_vipStatusKey, 'VIP Member');
      await _db.setString(_roleKey, 'admin');
      isLoggedIn = true;
      this.username = username;
      vipStatus = 'VIP Member';
      this.role = 'admin';
      notifyListeners();
      _log.info('Admin registered locally: $username');
      return null;
    }

    return 'Registration failed';
  }

  Future<bool> setPassword(String oldPassword, String newPassword) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/api/user/password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'old_password': oldPassword,
          'new_password': newPassword,
        }),
      );
      if (response.statusCode == 200) {
        _log.info('Password changed');
        return true;
      }
      _log.warning('setPassword failed: ${response.statusCode} ${response.body}');
      return false;
    } catch (e) {
      _log.warning('setPassword failed (endpoint may not exist): $e');
      return false;
    }
  }

  Future<bool> setIcon(String filePath) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/api/user/icon'),
      );
      request.files.add(await http.MultipartFile.fromPath('icon', filePath));
      final response = await request.send();
      if (response.statusCode == 200) {
        _log.info('User icon updated');
        return true;
      }
      _log.warning('setIcon failed: ${response.statusCode}');
      return false;
    } catch (e) {
      _log.warning('setIcon failed (endpoint may not exist): $e');
      return false;
    }
  }
}
