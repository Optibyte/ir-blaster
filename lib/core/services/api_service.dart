import 'dart:convert';
import 'dart:async';

/// Mock ApiService for design-only mode.
class ApiService {
  /// Mock energy summary data.
  Future<Map<String, dynamic>> fetchEnergySummary({
    required DateTime start,
    required DateTime stop,
  }) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 600));

    return {
      "status": 1,
      "data": {
        "totalConsumption": 1450.8,
        "previousConsumption": 1320.4,
        "peakDemand": 52.1,
        "averageDemand": 30.5
      }
    };
  }

  /// Mock grouped energy summary.
  Future<Map<String, dynamic>> fetchGroupedEnergySummary({
    required DateTime start,
    required DateTime stop,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));

    return {
      "status": 1,
      "data": [
        {"name": "Lobby AC", "value": 450.0},
        {"name": "Server Room AC", "value": 850.5},
        {"name": "Office AC", "value": 150.3},
      ]
    };
  }

  /// Mock top equipment consumption.
  Future<Map<String, dynamic>> fetchTopEquipmentConsumption({
    String timeRange = 'today',
    int limit = 5,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));

    return {
      "status": 1,
      "data": [
        {"name": "Server Room AC", "value": 350.2},
        {"name": "Lobby Main AC", "value": 280.5},
        {"name": "Conference AC", "value": 120.4},
        {"name": "Office 1 AC", "value": 95.8},
        {"name": "Office 2 AC", "value": 88.2},
      ]
    };
  }
}
