import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:ir_blaster_ac/core/config/app_config.dart';

/// Represents the live device state parsed from the SIRIS JSON snapshot.
class SirisDeviceState {
  final String deviceId;
  final String ac; // "ON" or "OFF"
  final int setTemp;
  final int currentTemp;
  final int humidity;
  final bool irOnLearned;
  final bool irOffLearned;
  final String status; // "ACTIVE" or "INACTIVE"
  final String wifiSsid;
  final String wifiIp;
  final String time;

  // Schedule slots
  final String schOn1;
  final String schOff1;
  final String schOn2;
  final String schOff2;
  final String schOn3;
  final String schOff3;
  final String schOn4;
  final String schOff4;
  final String schOn5;
  final String schOff5;
  final String lunchOn;
  final String lunchOff;

  SirisDeviceState({
    required this.deviceId,
    required this.ac,
    required this.setTemp,
    required this.currentTemp,
    required this.humidity,
    required this.irOnLearned,
    required this.irOffLearned,
    required this.status,
    required this.wifiSsid,
    required this.wifiIp,
    required this.time,
    required this.schOn1,
    required this.schOff1,
    required this.schOn2,
    required this.schOff2,
    required this.schOn3,
    required this.schOff3,
    required this.schOn4,
    required this.schOff4,
    required this.schOn5,
    required this.schOff5,
    required this.lunchOn,
    required this.lunchOff,
  });

  bool get isActive => status.toUpperCase() == 'ACTIVE';
  bool get isPowerOn => ac.toUpperCase() == 'ON';

  factory SirisDeviceState.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? json;
    return SirisDeviceState(
      deviceId: (data['device_id'] ?? '').toString(),
      ac: (data['ac'] ?? 'OFF').toString().toUpperCase(),
      setTemp: _toInt(data['set_temp'], 24),
      currentTemp: _toInt(data['current_temp'], 0),
      humidity: _toInt(data['hum'], 0),
      irOnLearned: data['ir_on_learned'] == true,
      irOffLearned: data['ir_off_learned'] == true,
      status: (data['status'] ?? 'INACTIVE').toString().toUpperCase(),
      wifiSsid: (data['wifi_ssid'] ?? '').toString(),
      wifiIp: (data['wifi_ip'] ?? '').toString(),
      time: (data['time'] ?? '').toString(),
      schOn1: (data['sch_on1'] ?? 'DISABLED').toString(),
      schOff1: (data['sch_off1'] ?? 'DISABLED').toString(),
      schOn2: (data['sch_on2'] ?? 'DISABLED').toString(),
      schOff2: (data['sch_off2'] ?? 'DISABLED').toString(),
      schOn3: (data['sch_on3'] ?? 'DISABLED').toString(),
      schOff3: (data['sch_off3'] ?? 'DISABLED').toString(),
      schOn4: (data['sch_on4'] ?? 'DISABLED').toString(),
      schOff4: (data['sch_off4'] ?? 'DISABLED').toString(),
      schOn5: (data['sch_on5'] ?? 'DISABLED').toString(),
      schOff5: (data['sch_off5'] ?? 'DISABLED').toString(),
      lunchOn: (data['lunch_on'] ?? 'DISABLED').toString(),
      lunchOff: (data['lunch_off'] ?? 'DISABLED').toString(),
    );
  }

  static int _toInt(dynamic val, int fallback) {
    if (val == null) return fallback;
    if (val is int) return val;
    if (val is double) return val.toInt();
    return int.tryParse(val.toString()) ?? fallback;
  }
}

/// MQTT response types from the SIRIS device.
enum SirisResponseType {
  acOnDone,
  acOffDone,
  tempSet,
  tempError,
  scheduleSet,
  scheduleCleared,
  scheduleError,
  cmdRejected,
  cmdError,
  unknown,
  jsonSnapshot,
}

/// Parsed command response from the device.
class SirisResponse {
  final SirisResponseType type;
  final String rawPayload;
  final String? detail;

  SirisResponse({
    required this.type,
    required this.rawPayload,
    this.detail,
  });
}

/// ─── MqttService ─────────────────────────────────────────────────────────
/// Singleton MQTT service for SIRIS IR Blaster communication.
///
/// CRITICAL RULES (from spec):
/// 1. retain = false on every publish
/// 2. Plain text only to command topics — never JSON
/// 3. Never send DISABLED — use SCH_CLEARx commands
/// 4. Never echo back values from JSON
/// 5. Subscribe to testir/data before sending any command
/// 6. Send STATUS on startup
/// 7. Only publish on explicit user action
/// 8. Wait for ack before confirming UI update
/// 9. If status = INACTIVE → disable controls
/// 10. If ir_on_learned = false → warn user
/// 11. Time format: HH:MM (24hr, zero padded)
/// 12. Temperature: integer only
class MqttService extends ChangeNotifier {
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;
  MqttService._internal();

  MqttServerClient? _client;
  bool _isConnecting = false;
  bool _isConnected = false;
  String _deviceId = '';

  // ── State ──────────────────────────────────────────────────────────────
  SirisDeviceState? _lastState;
  SirisDeviceState? get lastState => _lastState;
  bool get isConnected => _isConnected;
  String get deviceId => _deviceId;

  // ── Streams ────────────────────────────────────────────────────────────
  final StreamController<SirisDeviceState> _stateController =
      StreamController<SirisDeviceState>.broadcast();
  Stream<SirisDeviceState> get stateStream => _stateController.stream;

  final StreamController<SirisResponse> _responseController =
      StreamController<SirisResponse>.broadcast();
  Stream<SirisResponse> get responseStream => _responseController.stream;

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  /// Connect to the MQTT broker and subscribe to testir/data.
  /// [deviceId] — the SIRIS device identifier (e.g. "Sustainabyte_testir").
  Future<bool> connect({String? deviceId}) async {
    if (_isConnecting) return false;
    _isConnecting = true;

    _deviceId = deviceId ?? AppConfig.mqttDeviceId;

    // Disconnect existing client
    if (_client != null) {
      try {
        _client!.disconnect();
      } catch (_) {}
    }

    final broker = AppConfig.mqttBroker;
    final port = AppConfig.mqttPort;
    final username = AppConfig.mqttUsername;
    final password = AppConfig.mqttPassword;
    final clientId = 'siris_flutter_${DateTime.now().millisecondsSinceEpoch}';

    _client = MqttServerClient(broker, clientId);
    _client!.port = port;
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 60;
    _client!.autoReconnect = true;
    _client!.onDisconnected = _onDisconnected;
    _client!.onConnected = _onConnected;
    _client!.onAutoReconnect = () {
      debugPrint('🔄 [MQTT] Auto-reconnecting...');
    };
    _client!.onAutoReconnected = () {
      debugPrint('✅ [MQTT] Auto-reconnected');
      _subscribeToDataTopic();
    };

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(username, password)
        .startClean();
    _client!.connectionMessage = connMessage;

    try {
      debugPrint('📡 [MQTT] Connecting to $broker:$port...');
      await _client!.connect();

      if (_client!.connectionStatus!.state == MqttConnectionState.connected) {
        _isConnected = true;
        _isConnecting = false;

        // RULE 5: Subscribe to testir/data BEFORE sending any command
        _subscribeToDataTopic();

        // Listen for messages
        _client!.updates!.listen(_onMessage);

        // RULE 6: Send STATUS on startup
        Future.delayed(const Duration(milliseconds: 500), () {
          sendStatus();
        });

        _connectionController.add(true);
        notifyListeners();
        debugPrint('✅ [MQTT] Connected and subscribed to ${AppConfig.mqttDataTopic}');
        return true;
      }
    } catch (e) {
      debugPrint('❌ [MQTT] Connection error: $e');
    }

    _isConnecting = false;
    _isConnected = false;
    _connectionController.add(false);
    notifyListeners();
    return false;
  }

  void _subscribeToDataTopic() {
    if (_client == null) return;
    final dataTopic = AppConfig.mqttDataTopic;
    _client!.subscribe(dataTopic, MqttQos.atLeastOnce);
    debugPrint('📨 [MQTT] Subscribed to: $dataTopic');
  }

  void _onConnected() {
    debugPrint('🟢 [MQTT] Connected callback');
    _isConnected = true;
    _connectionController.add(true);
    notifyListeners();
  }

  void _onDisconnected() {
    debugPrint('🔌 [MQTT] Disconnected');
    _isConnected = false;
    _connectionController.add(false);
    notifyListeners();
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage?>>? messages) {
    if (messages == null || messages.isEmpty) return;

    for (final msg in messages) {
      final recMess = msg.payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(
          recMess.payload.message);
      final topic = msg.topic;

      debugPrint('📩 [MQTT] Topic: $topic | Payload: ${payload.length > 200 ? "${payload.substring(0, 200)}..." : payload}');

      // Try parsing as JSON (device snapshot published every 5s)
      if (payload.trim().startsWith('{')) {
        _handleJsonPayload(payload);
      } else {
        _handleStringResponse(payload.trim());
      }
    }
  }

  void _handleJsonPayload(String payload) {
    try {
      // Fix malformed JSON
      String safePayload = payload;
      if (safePayload.contains('"set_temp":,')) {
        safePayload =
            safePayload.replaceAll('"set_temp":,', '"set_temp":null,');
      }

      final json = jsonDecode(safePayload);
      final state = SirisDeviceState.fromJson(json);

      // Only accept messages from our target device
      if (state.deviceId == _deviceId || _deviceId.isEmpty) {
        _lastState = state;
        _stateController.add(state);
        _responseController.add(SirisResponse(
          type: SirisResponseType.jsonSnapshot,
          rawPayload: payload,
        ));
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ [MQTT] JSON parse error: $e');
    }
  }

  void _handleStringResponse(String payload) {
    final prefix = AppConfig.mqttPayloadPrefix;
    final upper = payload.toUpperCase();

    SirisResponse response;

    if (upper.contains('AC_ON_DONE')) {
      response = SirisResponse(
        type: SirisResponseType.acOnDone,
        rawPayload: payload,
      );
    } else if (upper.contains('AC_OFF_DONE')) {
      response = SirisResponse(
        type: SirisResponseType.acOffDone,
        rawPayload: payload,
      );
    } else if (upper.contains('TEMP_SET')) {
      final detail = payload.split(':').length > 2
          ? payload.split(':').last.trim()
          : null;
      response = SirisResponse(
        type: SirisResponseType.tempSet,
        rawPayload: payload,
        detail: detail,
      );
    } else if (upper.contains('TEMP_ERR')) {
      response = SirisResponse(
        type: SirisResponseType.tempError,
        rawPayload: payload,
        detail: payload,
      );
    } else if (upper.contains('SCH_SET')) {
      response = SirisResponse(
        type: SirisResponseType.scheduleSet,
        rawPayload: payload,
        detail: payload,
      );
    } else if (upper.contains('SCH_CLEARED')) {
      response = SirisResponse(
        type: SirisResponseType.scheduleCleared,
        rawPayload: payload,
        detail: payload,
      );
    } else if (upper.contains('SCH_ERR')) {
      response = SirisResponse(
        type: SirisResponseType.scheduleError,
        rawPayload: payload,
        detail: payload,
      );
    } else if (upper.contains('CMD_REJECTED')) {
      response = SirisResponse(
        type: SirisResponseType.cmdRejected,
        rawPayload: payload,
        detail: payload,
      );
    } else if (upper.contains('CMD_ERR')) {
      response = SirisResponse(
        type: SirisResponseType.cmdError,
        rawPayload: payload,
        detail: payload,
      );
    } else {
      response = SirisResponse(
        type: SirisResponseType.unknown,
        rawPayload: payload,
      );
    }

    _responseController.add(response);
  }

  // ── Publish Methods (RULE 1: retain=false, RULE 2: plain text only) ──

  /// Publish a raw message to a topic. Retain is ALWAYS false.
  void _publish(String topic, String message) {
    if (_client == null ||
        _client!.connectionStatus!.state != MqttConnectionState.connected) {
      debugPrint('⚠️ [MQTT] Cannot publish — not connected');
      return;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!,
        retain: false);
    debugPrint('📤 [MQTT] Published to $topic: $message');
  }

  // ── AC Power Control ──────────────────────────────────────────────────

  /// Turn AC ON.
  void turnAcOn() {
    final topic = AppConfig.getMqttControlTopic(_deviceId);
    _publish(topic, 'ON');
  }

  /// Turn AC OFF.
  void turnAcOff() {
    final topic = AppConfig.getMqttControlTopic(_deviceId);
    _publish(topic, 'OFF');
  }

  /// Request device STATUS.
  void sendStatus() {
    final topic = AppConfig.getMqttControlTopic(_deviceId);
    _publish(topic, 'STATUS');
  }

  // ── Temperature Control (RULE 12: integer only) ───────────────────────

  /// Set temperature (16–30, integer only).
  void setTemperature(int temp) {
    if (temp < 16 || temp > 30) {
      debugPrint('⚠️ [MQTT] Temperature out of range: $temp');
      return;
    }
    final topic = AppConfig.getMqttTempTopic(_deviceId);
    _publish(topic, '$temp');
  }

  // ── Schedule Control (RULE 11: HH:MM format, RULE 3: never send DISABLED) ─

  /// Set a schedule ON time. [slot] is 1–5, [time] is "HH:MM" (24hr, zero-padded).
  void setScheduleOn(int slot, String time) {
    if (!_isValidTime(time)) return;
    final topic = AppConfig.getMqttScheduleTopic(_deviceId);
    _publish(topic, 'SCH_ON$slot:$time');
  }

  /// Set a schedule OFF time. [slot] is 1–5, [time] is "HH:MM".
  void setScheduleOff(int slot, String time) {
    if (!_isValidTime(time)) return;
    final topic = AppConfig.getMqttScheduleTopic(_deviceId);
    _publish(topic, 'SCH_OFF$slot:$time');
  }

  /// Set lunch ON time.
  void setLunchOn(String time) {
    if (!_isValidTime(time)) return;
    final topic = AppConfig.getMqttScheduleTopic(_deviceId);
    _publish(topic, 'LUNCH_ON:$time');
  }

  /// Set lunch OFF time.
  void setLunchOff(String time) {
    if (!_isValidTime(time)) return;
    final topic = AppConfig.getMqttScheduleTopic(_deviceId);
    _publish(topic, 'LUNCH_OFF:$time');
  }

  // ── Schedule Clear ────────────────────────────────────────────────────

  /// Clear ALL schedule slots at once.
  void clearAllSchedules() {
    final topic = AppConfig.getMqttScheduleTopic(_deviceId);
    _publish(topic, 'SCH_CLEAR');
  }

  /// Clear a specific schedule slot (1–5).
  void clearScheduleSlot(int slot) {
    final topic = AppConfig.getMqttScheduleTopic(_deviceId);
    _publish(topic, 'SCH_CLEAR$slot');
  }

  /// Clear the lunch slot.
  void clearLunchSlot() {
    final topic = AppConfig.getMqttScheduleTopic(_deviceId);
    _publish(topic, 'SCH_CLEAR_LUNCH');
  }

  /// Get current schedule state.
  void getScheduleStatus() {
    final topic = AppConfig.getMqttScheduleTopic(_deviceId);
    _publish(topic, 'STATUS');
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  /// Validate HH:MM format (24hr, zero-padded).
  bool _isValidTime(String time) {
    final regex = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
    if (!regex.hasMatch(time)) {
      debugPrint('⚠️ [MQTT] Invalid time format: $time (expected HH:MM)');
      return false;
    }
    return true;
  }

  /// Disconnect from broker.
  void disconnect() {
    try {
      _client?.disconnect();
    } catch (_) {}
    _isConnected = false;
    _connectionController.add(false);
    notifyListeners();
  }

  /// Dispose all resources.
  @override
  void dispose() {
    disconnect();
    _stateController.close();
    _responseController.close();
    _connectionController.close();
    super.dispose();
  }
}
