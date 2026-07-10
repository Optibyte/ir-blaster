import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ir_blaster_ac/core/services/mqtt_config_service.dart';

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
        'https://optibyte.sustainabyte.ai/provisionservice/v1';
    if (rawUrl.contains('optibyte.sustainabyte.ai') &&
        !rawUrl.contains('/provisionservice/v1')) {
      return '$rawUrl/provisionservice/v1';
    }
    return rawUrl;
  }

  // ── MQTT (SIRIS IR Blaster) ──────────────────────────────────────────
  // NOTE: Username & password are now fetched dynamically from the API
  // via MqttConfigService.fetchMqttConfig(). The getters below are
  // .env-only fallbacks used if the API call hasn't completed yet.
  static String get mqttBroker => dotenv.env['MQTT_BROKER'] ?? '13.66.130.236';

  static int get mqttPort =>
      int.tryParse(dotenv.env['MQTT_PORT'] ?? '1883') ?? 1883;

  /// Fallback MQTT username — prefer MqttConfigService.cached?.username
  static String get mqttUsername {
    final cached = MqttConfigService.cached?.username;
    if (cached != null && cached.isNotEmpty) return cached;
    final envVal = dotenv.env['MQTT_USERNAME'];
    if (envVal != null && envVal.isNotEmpty) return envVal;
    return '';
  }

  /// Fallback MQTT password — prefer MqttConfigService.cached?.password
  static String get mqttPassword {
    final cached = MqttConfigService.cached?.password;
    if (cached != null && cached.isNotEmpty) return cached;
    final envVal = dotenv.env['MQTT_PASSWORD'];
    if (envVal != null && envVal.isNotEmpty) return envVal;
    return '';
  }

  /// Prefix used for subscription topics. The device publishes data on
  /// `<mqttUsername>/data`. Subscribe to this before sending any command.
  static String get mqttDataTopic =>
      dotenv.env['MQTT_DATA_TOPIC'] ?? '$mqttUsername/data';

  static String _defaultMqttDeviceId = '';
  /// The device_id used in MQTT topic paths & payload prefixes
  static String get mqttDeviceId =>
      dotenv.env['MQTT_DEVICE_ID'] ?? _defaultMqttDeviceId;

  static set mqttDeviceId(String value) {
    if (value.isNotEmpty) {
      _defaultMqttDeviceId = value;
    }
  }

  // ── Per-device topic builders (SIRIS Spec) ───────────────────────────
  //
  // Control : <mqttTopic>/<deviceId>/control
  // Temp    : <mqttTopic>/<deviceId>/control/set_temp
  // Schedule: <mqttTopic>/<deviceId>/schedule
  //
  // These accept a deviceId parameter so the app can work with
  // multiple devices in the future.

  /// AC ON/OFF/STATUS control topic.
  static String getMqttControlTopic(String deviceId) =>
      '$mqttTopic/$deviceId/control';

  /// Temperature set topic.
  static String getMqttTempTopic(String deviceId) =>
      '$mqttTopic/$deviceId/control/set_temp';

  /// Schedule control topic (set times, clear slots, STATUS).
  static String getMqttScheduleTopic(String deviceId) =>
      '$mqttTopic/$deviceId/schedule';

  /// WiFi control and status topic.
  static String getMqttWifiTopic(String deviceId) =>
      '$mqttTopic/$deviceId/wifi';

  // ── Legacy getters (for backward compatibility) ──────────────────────
  static String get mqttTopic {
    final cachedTopic = MqttConfigService.cached?.topic;
    if (cachedTopic != null && cachedTopic.isNotEmpty) {
      return cachedTopic;
    }
    final envTopic = dotenv.env['MQTT_TOPIC'];
    if (envTopic != null && envTopic.isNotEmpty) {
      return envTopic;
    }
    return mqttUsername;
  }

  static String get mqttControlTopic =>
      dotenv.env['MQTT_CONTROL_TOPIC'] ?? '$mqttTopic/$mqttDeviceId/control';

  static String get mqttScheduleTopic =>
      dotenv.env['MQTT_SCHEDULE_TOPIC'] ?? '$mqttTopic/$mqttDeviceId/schedule';

  static String get mqttStatusTopic =>
      dotenv.env['MQTT_STATUS_TOPIC'] ?? '$mqttTopic/$mqttDeviceId/status';

  static String getMqttStatusTopic(String deviceId) =>
      '$mqttTopic/$deviceId/status';

  /// Prefix used in MQTT payloads, e.g. ":STATUS_OFFLINE"
  static String get mqttPayloadPrefix =>
      dotenv.env['MQTT_PAYLOAD_PREFIX'] ?? mqttDeviceId;

  /// Default starting set temperature for AC control (24°C).
  static const double defaultSetTemp = 24.0;
}
