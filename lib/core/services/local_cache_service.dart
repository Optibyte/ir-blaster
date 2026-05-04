import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class LocalCacheService {
  static const String _dashboardCacheKey = 'cache_dashboard_summary';
  static const String _devicePrefix = 'cache_device_';

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
}
