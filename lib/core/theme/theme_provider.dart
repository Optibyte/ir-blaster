import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeKey = 'is_dark_mode';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  
  bool _isDarkMode = true; // Default to dark mode as requested

  bool get isDarkMode => _isDarkMode;

  ThemeProvider() {
    _loadTheme();
  }

  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  Future<void> _loadTheme() async {
    final storedValue = await _storage.read(key: _themeKey);
    if (storedValue != null) {
      _isDarkMode = storedValue == 'true';
      notifyListeners();
    }
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    await _storage.write(key: _themeKey, value: _isDarkMode.toString());
    notifyListeners();
  }

  Future<void> setDarkMode(bool isDark) async {
    if (_isDarkMode == isDark) return;
    _isDarkMode = isDark;
    await _storage.write(key: _themeKey, value: _isDarkMode.toString());
    notifyListeners();
  }
}
