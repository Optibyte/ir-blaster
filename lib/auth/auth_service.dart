import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _tokenKey = 'user_token';
  static const String _userEmailKey = 'user_email';

  static const String _registeredEmailKey = 'registered_email';
  static const String _registeredPasswordKey = 'registered_password';

  // Singleton pattern
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  /// Register: store email + password
  Future<void> registerUser(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_registeredEmailKey, email);
    await prefs.setString(_registeredPasswordKey, password);
  }

  /// Validate login: checks against registered email + password
  Future<bool> validateLogin(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString(_registeredEmailKey);
    final savedPassword = prefs.getString(_registeredPasswordKey);

    return email == savedEmail && password == savedPassword;
  }

  /// Save auth token + user for session
  Future<void> saveAuthDetails(String email, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userEmailKey, email);
  }

  /// Check if user is logged in
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    return token != null && token.isNotEmpty;
  }

  /// Get logged in user email
  Future<String?> getUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userEmailKey);
  }

  /// Get registered email (for forget password check)
  Future<String?> getRegisteredEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_registeredEmailKey);
  }

  /// Update password (for forget password)
  Future<void> updatePassword(String newPassword) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_registeredPasswordKey, newPassword);
  }

  /// Logout: clear session
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userEmailKey);
  }
}
