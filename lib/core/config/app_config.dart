import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralised access to environment variables loaded from `.env`.
/// Always access config through this class — never hardcode URLs.
class AppConfig {
  AppConfig._(); // prevent instantiation

  /// Base URL for the authentication service.
  static String get authBaseUrl =>
      dotenv.env['AUTH_BASE_URL'] ??
      (throw Exception('AUTH_BASE_URL not set in .env'));

  // ── Derived endpoints ───────────────────────────────────────────────
  static String get loginEndpoint  => '$authBaseUrl/login';
  static String get verifyEndpoint => '$authBaseUrl/verify';

  /// Base URL for the ProvisionService backend (equipment, systems, etc.)
  static String get provisionBaseUrl =>
      dotenv.env['PROVISION_BASE_URL'] ??
      (throw Exception('PROVISION_BASE_URL not set in .env'));
}
