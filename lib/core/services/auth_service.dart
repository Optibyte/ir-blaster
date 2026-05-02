import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Handles mock authentication for design-only mode.
class AuthService {
  // ── Storage keys ────────────────────────────────────────────────────
  static const String _cookieKey = 'session_cookie';
  static const String _emailKey = 'user_email';
  static const String _userDataKey = 'user_data';
  static const String _companyIdKey = 'company_id';
  static const String _bucketKey = 'bucket';
  static const String _siteIdKey = 'site_id';
  static const String _zoneIdKey = 'zone_id';

  static final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  /// Mock login that always succeeds.
  static Future<String?> login(String email, String password) async {
    try {
      // Simulate network delay
      await Future.delayed(const Duration(milliseconds: 800));

      // Mock user data matching the real response structure
      final mockUser = {
        'userId': 'a96290dd-0fb2-4722-9dd6-d26621317c23',
        'name': 'Mahavir',
        'email': email,
        'role': 'site_technician',
        'company': 'a4764d8d-7b79-43e1-8e48-e62096c28cc7',
        'bucket': 'mahavir01',
        'type': 'Employee',
        'site': '3fcc7555-3fbb-4cbc-913f-18a2a3094d47',
        'zone': '8e8836ab-cea0-4e54-af84-609bffdf292a',
        'serviceType': 'EMS'
      };

      // Mock full response for console logging
      final mockResponse = {
        'status': 1,
        'message': 'Login successful.',
        'data': mockUser,
        'token': 'mock_session_token'
      };
      debugPrint(
          '🔐 [AuthService] Login Response: ${jsonEncode(mockResponse)}');

      // Persist mock session and user details
      await _storage.write(key: _cookieKey, value: 'mock_session_token');
      await _storage.write(key: _emailKey, value: email);
      await _storage.write(key: _userDataKey, value: jsonEncode(mockUser));
      await _storage.write(
          key: _companyIdKey, value: mockUser['company'] as String);
      await _storage.write(
          key: _bucketKey, value: mockUser['bucket'] as String);
      await _storage.write(key: _siteIdKey, value: mockUser['site'] as String);
      await _storage.write(key: _zoneIdKey, value: mockUser['zone'] as String);

      // Log specific storage keys for debugging
      debugPrint('📦 [Storage] Saved $_cookieKey: mock_session_token');
      debugPrint('📦 [Storage] Saved $_emailKey: $email');
      debugPrint('📦 [Storage] Saved $_userDataKey: ${jsonEncode(mockUser)}');
      debugPrint('📦 [Storage] Saved $_companyIdKey: ${mockUser['company']}');
      debugPrint('📦 [Storage] Saved $_bucketKey: ${mockUser['bucket']}');
      debugPrint('📦 [Storage] Saved $_siteIdKey: ${mockUser['site']}');

      return null; // ✅ Success
    } catch (e) {
      return 'Error: $e';
    }
  }

  /// Mock verify that returns stored user data if session exists.
  static Future<Map<String, dynamic>?> verify() async {
    try {
      final cookie = await _storage.read(key: _cookieKey);
      if (cookie == null || cookie.isEmpty) return null;

      final userDataRaw = await _storage.read(key: _userDataKey);
      if (userDataRaw != null) {
        final userData = jsonDecode(userDataRaw) as Map<String, dynamic>;
        debugPrint(
            '✅ [AuthService] Verify Response: {"status": 1, "data": $userDataRaw}');
        return userData;
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ Verify error: $e');
      return null;
    }
  }

  static Future<String?> getCookieHeader() async =>
      _storage.read(key: _cookieKey);

  static Future<Map<String, dynamic>?> getUserData() async {
    final raw = await _storage.read(key: _userDataKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<String?> getEmail() async => _storage.read(key: _emailKey);

  static Future<String?> getCompanyId() async =>
      _storage.read(key: _companyIdKey);

  static Future<String?> getBucket() async => _storage.read(key: _bucketKey);

  static Future<String?> getSiteId() async => _storage.read(key: _siteIdKey);

  static Future<String?> getZoneId() async => _storage.read(key: _zoneIdKey);

  static Future<bool> hasStoredSession() async {
    final c = await _storage.read(key: _cookieKey);
    return c != null && c.isNotEmpty;
  }

  static Future<void> logout() async {
    await _storage.delete(key: _cookieKey);
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _userDataKey);
    await _storage.delete(key: _companyIdKey);
    await _storage.delete(key: _bucketKey);
    await _storage.delete(key: _siteIdKey);
    await _storage.delete(key: _zoneIdKey);
  }
}
