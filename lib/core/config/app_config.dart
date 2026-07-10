import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralised access to environment variables loaded from `.env`.
/// Always access config through this class — never hardcode URLs.
class AppConfig {
  AppConfig._(); // prevent instantiation

  /// Base URL for the authentication service.
  static String get authBaseUrl =>
      dotenv.env['AUTH_BASE_URL'] ?? 'https://optibyte.sustainabyte.ai';

  // ── Derived auth endpoints ────────────────────────────────────────────
  static String get loginEndpoint => '$authBaseUrl/authservice/v1/login';
  static String get verifyEndpoint => '$authBaseUrl/authservice/v1/verify';

  /// Base URL for the ProvisionService backend (equipment, systems, etc.)
  static String get provisionBaseUrl {
    final rawUrl = dotenv.env['PROVISION_BASE_URL'] ??
        'https://optibyte.sustainabyte.ai/provisioning/v1';
    if (rawUrl.contains('optibyte.sustainabyte.ai') &&
        !rawUrl.contains('/provisioning/v1')) {
      return '$rawUrl/provisioning/v1';
    }
    return rawUrl;
  }

  // ── MQTT (SIRIS IR Blaster) ──────────────────────────────────────────
  static String get mqttBroker => dotenv.env['MQTT_BROKER'] ?? '13.66.130.236';

  static int get mqttPort =>
      int.tryParse(dotenv.env['MQTT_PORT'] ?? '1883') ?? 1883;

  static String get mqttUsername => dotenv.env['MQTT_USERNAME'] ?? 'testir';

  static String get mqttPassword => dotenv.env['MQTT_PASSWORD'] ?? 'ir@123';

  /// Prefix used for subscription topics. The device publishes data on
  /// `testir/data`. Subscribe to this before sending any command.
  static String get mqttDataTopic =>
      dotenv.env['MQTT_DATA_TOPIC'] ?? 'testir/data';

  /// The device_id used in MQTT topic paths & payload prefixes.
  /// Defaults to "Sustainabyte_testir" per the SIRIS spec.
  static String get mqttDeviceId =>
      dotenv.env['MQTT_DEVICE_ID'] ?? 'Sustainabyte_testir';

  // ── Per-device topic builders (SIRIS Spec) ───────────────────────────
  //
  // Control : testir/<deviceId>/control
  // Temp    : testir/<deviceId>/control/set_temp
  // Schedule: testir/<deviceId>/schedule
  //
  // These accept a deviceId parameter so the app can work with
  // multiple devices in the future.

  /// AC ON/OFF/STATUS control topic.
  static String getMqttControlTopic(String deviceId) =>
      'testir/$deviceId/control';

  /// Temperature set topic.
  static String getMqttTempTopic(String deviceId) =>
      'testir/$deviceId/control/set_temp';

  /// Schedule control topic (set times, clear slots, STATUS).
  static String getMqttScheduleTopic(String deviceId) =>
      'testir/$deviceId/schedule';

  // ── Legacy getters (for backward compatibility) ──────────────────────
  static String get mqttTopic =>
      dotenv.env['MQTT_TOPIC'] ?? 'sustainabyte_demo';

  static String get mqttControlTopic =>
      dotenv.env['MQTT_CONTROL_TOPIC'] ?? 'testir/Sustainabyte_testir/control';

  static String get mqttScheduleTopic =>
      dotenv.env['MQTT_SCHEDULE_TOPIC'] ?? 'testir/Sustainabyte_testir/schedule';

  static String get mqttStatusTopic =>
      dotenv.env['MQTT_STATUS_TOPIC'] ?? 'testir/Sustainabyte_testir/status';

  static String getMqttStatusTopic(String deviceId) =>
      'testir/$deviceId/status';

  /// Prefix used in MQTT payloads, e.g. "Sustainabyte_testir:STATUS_OFFLINE"
  static String get mqttPayloadPrefix =>
      dotenv.env['MQTT_PAYLOAD_PREFIX'] ?? 'Sustainabyte_testir';
}
