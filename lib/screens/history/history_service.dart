import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'history_entry.dart';

class HistoryService {
  static const String _storageKey = 'action_history';

  Future<void> addEntry(HistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getHistory();
    history.insert(0, entry); // Add new entry at the beginning

    // Store only last 100 entries to prevent excessive storage usage
    if (history.length > 100) {
      history.removeLast();
    }

    await prefs.setString(_storageKey, jsonEncode(
      history.map((e) => e.toJson()).toList(),
    ));
  }

  Future<List<HistoryEntry>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? historyJson = prefs.getString(_storageKey);

    if (historyJson == null) return [];

    final List<dynamic> decoded = jsonDecode(historyJson);
    return decoded.map((e) => HistoryEntry.fromJson(e)).toList();
  }

  Future<List<HistoryEntry>> getDeviceHistory(String deviceName) async {
    final allHistory = await getHistory();
    return allHistory.where((entry) => entry.deviceName == deviceName).toList();
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}