import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralised access to environment variables loaded from `.env`.
/// Always access config through this class — never hardcode URLs.
class AppConfig {
  AppConfig._(); // prevent instantiation

  /// Base URL for the authentication service.
  static String get authBaseUrl =>
      dotenv.env['AUTH_BASE_URL'] ??
      (throw Exception('AUTH_BASE_URL not set in .env'));

  // ── Derived auth endpoints ────────────────────────────────────────────
  static String get loginEndpoint => '$authBaseUrl/login';
  static String get verifyEndpoint => '$authBaseUrl/verify';

  /// Base URL for the ProvisionService backend (equipment, systems, etc.)
  static String get provisionBaseUrl =>
      dotenv.env['PROVISION_BASE_URL'] ??
      (throw Exception('PROVISION_BASE_URL not set in .env'));

  // ── MQTT (IR Blaster) ────────────────────────────────────────────────
  static String get mqttBroker => dotenv.env['MQTT_BROKER'] ?? '13.66.130.236';

  static int get mqttPort =>
      int.tryParse(dotenv.env['MQTT_PORT'] ?? '1883') ?? 1883;

  static String get mqttTopic => dotenv.env['MQTT_TOPIC'] ?? 'sustainabyte_demo';

  static String get mqttControlTopic =>
      dotenv.env['MQTT_CONTROL_TOPIC'] ?? 'testir/sustainabyte_demo/control';

  static String get mqttScheduleTopic =>
      dotenv.env['MQTT_SCHEDULE_TOPIC'] ?? 'testir/sustainabyte_demo/schedule';

  static String get mqttStatusTopic =>
      dotenv.env['MQTT_STATUS_TOPIC'] ?? 'testir/sustainabyte_demo/status';

  static String get mqttUsername => dotenv.env['MQTT_USERNAME'] ?? 'testir';

  static String get mqttPassword => dotenv.env['MQTT_PASSWORD'] ?? 'ir@123';

  /// Prefix used in MQTT payloads, e.g. "sustainabyte_testir:STATUS_OFFLINE"
  static String get mqttPayloadPrefix =>
      dotenv.env['MQTT_PAYLOAD_PREFIX'] ?? 'Sustainabyte_testir';
}

