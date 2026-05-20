import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class LocalCacheService {
  static const String _dashboardCacheKey = 'cache_dashboard_summary';
  static const String _devicePrefix = 'cache_device_';
  static const String _wifiSsidKey = 'wifi_ssid';
  static const String _wifiPasswordKey = 'wifi_password';

  /// Save dashboard data to local storage
  static Future<void> saveDashboardData(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dashboardCacheKey, jsonEncode({
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'data': data,
      }));
    } catch (e) {
      debugPrint('⚠️ [Cache] Error saving dashboard: $e');
    }
  }

  /// Retrieve dashboard data from local storage
  static Future<Map<String, dynamic>?> getDashboardData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cached = prefs.getString(_dashboardCacheKey);
      if (cached != null) {
        return jsonDecode(cached) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('⚠️ [Cache] Error reading dashboard: $e');
    }
    return null;
  }

  /// Save specific device data (Temp, Hum, Power)
  static Future<void> saveDeviceStatus(String deviceId, Map<String, dynamic> status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_devicePrefix$deviceId', jsonEncode({
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'status': status,
      }));
    } catch (e) {
      debugPrint('⚠️ [Cache] Error saving device status: $e');
    }
  }

  /// Retrieve specific device data
  static Future<Map<String, dynamic>?> getDeviceStatus(String deviceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cached = prefs.getString('$_devicePrefix$deviceId');
      if (cached != null) {
        return jsonDecode(cached) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('⚠️ [Cache] Error reading device status: $e');
    }
    return null;
  }

  /// Save equipment list for a specific system
  static Future<void> saveEquipmentList(String systemId, List<dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('equip_list_$systemId', jsonEncode({
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'data': data,
      }));
    } catch (e) {
      debugPrint('⚠️ [Cache] Error saving equip list: $e');
    }
  }

  /// Retrieve equipment list for a specific system
  static Future<List<dynamic>?> getEquipmentList(String systemId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cached = prefs.getString('equip_list_$systemId');
      if (cached != null) {
        final decoded = jsonDecode(cached);
        return decoded['data'] as List<dynamic>;
      }
    } catch (e) {
      debugPrint('⚠️ [Cache] Error reading equip list: $e');
    }
    return null;
  }

  /// Save WiFi credentials
  static Future<void> saveWifiCredentials(String ssid, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_wifiSsidKey, ssid);
      await prefs.setString(_wifiPasswordKey, password);
      debugPrint('✅ [Cache] WiFi credentials saved.');
    } catch (e) {
      debugPrint('⚠️ [Cache] Error saving WiFi credentials: $e');
    }
  }

  /// Retrieve WiFi credentials
  static Future<Map<String, String>> getWifiCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'ssid': prefs.getString(_wifiSsidKey) ?? '',
        'password': prefs.getString(_wifiPasswordKey) ?? '',
      };
    } catch (e) {
      debugPrint('⚠️ [Cache] Error reading WiFi credentials: $e');
      return {'ssid': '', 'password': ''};
    }
  }

  /// Clear all cached data (used during logout)
  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      debugPrint('🧹 [Cache] All local storage cleared.');
    } catch (e) {
      debugPrint('⚠️ [Cache] Error clearing cache: $e');
    }
  }
}
