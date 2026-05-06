import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:ir_blaster_ac/core/services/local_cache_service.dart';
import 'package:ir_blaster_ac/core/config/app_config.dart';

/// Handles authentication and session management using ProvisionService API.
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

  /// Performs a real login by hitting the auth service.
  static Future<String?> login(String email, String password) async {
    try {
      debugPrint('🔐 [AuthService] Attempting login for: $email');
      
      final response = await http.post(
        Uri.parse(AppConfig.loginEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      debugPrint('🔐 [AuthService] Login Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        
        if (body['status'] == 1) {
          final userData = body['data'];
          final token = body['token'] ?? 'valid_session';

          // Persist session and user details from the REAL response
          await _storage.write(key: _cookieKey, value: token);
          await _storage.write(key: _emailKey, value: email);
          await _storage.write(key: _userDataKey, value: jsonEncode(userData));
          
          // Use dynamic fields from API response
          await _storage.write(key: _companyIdKey, value: userData['company']?.toString() ?? '');
          await _storage.write(key: _bucketKey, value: userData['bucket']?.toString() ?? '');
          await _storage.write(key: _siteIdKey, value: userData['site']?.toString() ?? '');
          await _storage.write(key: _zoneIdKey, value: userData['zone']?.toString() ?? '');

          debugPrint('✅ [AuthService] Login successful. Data persisted for bucket: ${userData['bucket']}');
          return null; // Success
        } else {
          return body['message'] ?? 'Login failed';
        }
      } else {
        return 'Server error: ${response.statusCode}';
      }
    } catch (e) {
      debugPrint('❌ [AuthService] Login Exception: $e');
      return 'Connection error: $e';
    }
  }

  /// Verifies current session by hitting the verify endpoint.
  static Future<Map<String, dynamic>?> verify() async {
    try {
      final token = await _storage.read(key: _cookieKey);
      if (token == null || token.isEmpty) return null;

      final response = await http.get(
        Uri.parse(AppConfig.verifyEndpoint),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['status'] == 1) {
          return body['data'];
        }
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

    // Also clear the general cache (SharedPreferences)
    await LocalCacheService.clearAll();
  }
}
