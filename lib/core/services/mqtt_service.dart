import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:ir_blaster_ac/core/config/app_config.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:ir_blaster_ac/core/services/mqtt_config_service.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'dart:typed_data';

/// Represents the live device state parsed from the SIRIS JSON snapshot.
class SirisDeviceState {
  final String deviceId;
  final String imei;
  final String ac; // "ON" or "OFF"
  final int setTemp;
  final int currentTemp;
  final int humidity;
  final bool irOnLearned;
  final bool irOffLearned;
  final String status; // "ACTIVE" or "INACTIVE"
  final String wifiSsid;
  final String wifiIp;
  final String wifiNetwork; // PRIMARY or SECONDARY
  final int wifiRssi;
  final String time;
  final String primarySsid;
  final String secondarySsid;
 
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
    required this.imei,
    required this.ac,
    required this.setTemp,
    required this.currentTemp,
    required this.humidity,
    required this.irOnLearned,
    required this.irOffLearned,
    required this.status,
    required this.wifiSsid,
    required this.wifiIp,
    required this.wifiNetwork,
    required this.wifiRssi,
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
    this.primarySsid = '',
    this.secondarySsid = '',
  });

  SirisDeviceState copyWith({
    String? deviceId,
    String? imei,
    String? ac,
    int? setTemp,
    int? currentTemp,
    int? humidity,
    bool? irOnLearned,
    bool? irOffLearned,
    String? status,
    String? wifiSsid,
    String? wifiIp,
    String? wifiNetwork,
    int? wifiRssi,
    String? time,
    String? primarySsid,
    String? secondarySsid,
    String? schOn1,
    String? schOff1,
    String? schOn2,
    String? schOff2,
    String? schOn3,
    String? schOff3,
    String? schOn4,
    String? schOff4,
    String? schOn5,
    String? schOff5,
    String? lunchOn,
    String? lunchOff,
  }) {
    return SirisDeviceState(
      deviceId: deviceId ?? this.deviceId,
      imei: imei ?? this.imei,
      ac: ac ?? this.ac,
      setTemp: setTemp ?? this.setTemp,
      currentTemp: currentTemp ?? this.currentTemp,
      humidity: humidity ?? this.humidity,
      irOnLearned: irOnLearned ?? this.irOnLearned,
      irOffLearned: irOffLearned ?? this.irOffLearned,
      status: status ?? this.status,
      wifiSsid: wifiSsid ?? this.wifiSsid,
      wifiIp: wifiIp ?? this.wifiIp,
      wifiNetwork: wifiNetwork ?? this.wifiNetwork,
      wifiRssi: wifiRssi ?? this.wifiRssi,
      time: time ?? this.time,
      primarySsid: primarySsid ?? this.primarySsid,
      secondarySsid: secondarySsid ?? this.secondarySsid,
      schOn1: schOn1 ?? this.schOn1,
      schOff1: schOff1 ?? this.schOff1,
      schOn2: schOn2 ?? this.schOn2,
      schOff2: schOff2 ?? this.schOff2,
      schOn3: schOn3 ?? this.schOn3,
      schOff3: schOff3 ?? this.schOff3,
      schOn4: schOn4 ?? this.schOn4,
      schOff4: schOff4 ?? this.schOff4,
      schOn5: schOn5 ?? this.schOn5,
      schOff5: schOff5 ?? this.schOff5,
      lunchOn: lunchOn ?? this.lunchOn,
      lunchOff: lunchOff ?? this.lunchOff,
    );
  }

  bool get isActive =>
      status.toUpperCase() == 'ACTIVE' ||
      status.toUpperCase() == 'ON' ||
      status.toUpperCase() == 'OFF';
  bool get isPowerOn => ac.toUpperCase() == 'ON';

  factory SirisDeviceState.fromJson(Map<String, dynamic> json) {
    // Resolve the root object containing the device metadata.
    Map<String, dynamic> root = json;
    if (json['data'] is Map<String, dynamic>) {
      final innerData = json['data'] as Map<String, dynamic>;
      if (innerData.containsKey('device_id') || innerData.containsKey('deviceId')) {
        root = innerData;
      }
    }

    // Resolve the payload object containing telemetry values.
    Map<String, dynamic> payload = root;
    if (root['data'] is Map<String, dynamic>) {
      payload = root['data'] as Map<String, dynamic>;
    }

    return SirisDeviceState(
      deviceId: (root['device_id'] ?? root['deviceId'] ?? '').toString(),
      imei: (root['imei'] ?? '').toString(),
      ac: (payload['ac'] ?? root['ac'] ?? 'OFF').toString().toUpperCase(),
      setTemp: _toInt(root['set_temp'] ?? payload['set_temp'] ?? root['setTemp'] ?? payload['setTemp'], 24),
      currentTemp: _toInt(root['current_temp'] ?? payload['temp'] ?? payload['current_temp'] ?? root['currentTemp'] ?? payload['currentTemp'], 0),
      humidity: _toInt(root['hum'] ?? payload['hum'] ?? root['humidity'] ?? payload['humidity'], 0),
      irOnLearned: (root['ir_on_learned'] ?? payload['ir_on_learned'] ?? root['irOnLearned'] ?? payload['irOnLearned']) == true,
      irOffLearned: (root['ir_off_learned'] ?? payload['ir_off_learned'] ?? root['irOffLearned'] ?? payload['irOffLearned']) == true,
      status: (root['status'] ?? payload['status'] ?? 'ACTIVE').toString().toUpperCase(),
      wifiSsid: (root['wifi_ssid'] ?? payload['wifi_ssid'] ?? root['wifiSsid'] ?? payload['wifiSsid'] ?? '').toString(),
      wifiIp: (root['wifi_ip'] ?? payload['wifi_ip'] ?? root['wifiIp'] ?? payload['wifiIp'] ?? '').toString(),
      wifiNetwork: (root['wifi_network'] ?? payload['wifi_network'] ?? root['wifiNetwork'] ?? payload['wifiNetwork'] ?? '').toString(),
      wifiRssi: _toInt(root['wifi_rssi'] ?? payload['wifi_rssi'] ?? root['wifiRssi'] ?? payload['wifiRssi'], 0),
      time: (payload['time'] ?? root['time'] ?? '').toString(),
      schOn1: (root['sch_on1'] ?? payload['sch_on1'] ?? 'DISABLED').toString(),
      schOff1: (root['sch_off1'] ?? payload['sch_off1'] ?? 'DISABLED').toString(),
      schOn2: (root['sch_on2'] ?? payload['sch_on2'] ?? 'DISABLED').toString(),
      schOff2: (root['sch_off2'] ?? payload['sch_off2'] ?? 'DISABLED').toString(),
      schOn3: (root['sch_on3'] ?? payload['sch_on3'] ?? 'DISABLED').toString(),
      schOff3: (root['sch_off3'] ?? payload['sch_off3'] ?? 'DISABLED').toString(),
      schOn4: (root['sch_on4'] ?? payload['sch_on4'] ?? 'DISABLED').toString(),
      schOff4: (root['sch_off4'] ?? payload['sch_off4'] ?? 'DISABLED').toString(),
      schOn5: (root['sch_on5'] ?? payload['sch_on5'] ?? 'DISABLED').toString(),
      schOff5: (root['sch_off5'] ?? payload['sch_off5'] ?? 'DISABLED').toString(),
      lunchOn: (root['lunch_on'] ?? payload['lunch_on'] ?? 'DISABLED').toString(),
      lunchOff: (root['lunch_off'] ?? payload['lunch_off'] ?? 'DISABLED').toString(),
      primarySsid: (root['wifi_primary_ssid'] ?? root['primary_ssid'] ?? payload['wifi_primary_ssid'] ?? payload['primary_ssid'] ?? '').toString(),
      secondarySsid: (root['wifi_secondary_ssid'] ?? root['secondary_ssid'] ?? payload['wifi_secondary_ssid'] ?? payload['secondary_ssid'] ?? '').toString(),
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
  wifiPrimarySet,
  wifiSecondarySet,
  wifiResetBtOpen,
  wifiInfo,
  wifiError,
  wifiRollback,
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
  int _connectionAttempt = 0;
  bool _isConnected = false;
  String _deviceId = '';
  String _companyId = '';
  Timer? _sseWatchdogTimer;
  BluetoothConnection? _bluetoothConnection;
  BluetoothConnection? get bluetoothConnection => _bluetoothConnection;
  set bluetoothConnection(BluetoothConnection? conn) {
    _bluetoothConnection = conn;
    if (conn != null && conn.isConnected) {
      _listenBluetoothConnection(conn);
    }
  }

  BluetoothDevice? bluetoothDevice;
  bool get isBluetoothConnected => _bluetoothConnection?.isConnected == true;
  String? _imei;
  StreamSubscription? _sseSub;

  bool _isSseConnected = false;
  bool get isSseConnected => _isSseConnected;

  DateTime? _sseLastDataTime;
  DateTime? get sseLastDataTime => _sseLastDataTime;

  String? _sseLastPayload;
  String? get sseLastPayload => _sseLastPayload;

  String get sseStreamUrl {
    final queryParams = <String>[];
    if (_companyId.isNotEmpty) {
      queryParams.add('companyid=$_companyId');
    }
    if (_deviceId.isNotEmpty) {
      queryParams.add('deviceId=$_deviceId');
    }
    if (_imei != null && _imei!.isNotEmpty) {
      queryParams.add('imei=$_imei');
    }
    return '${AppConfig.provisionBaseUrl}/mqtt/stream?${queryParams.join('&')}';
  }

  String _incomingBtBuffer = '';
  void _listenBluetoothConnection(BluetoothConnection conn) {
    conn.input?.listen((Uint8List data) {
      final chunk = String.fromCharCodes(data);
      _incomingBtBuffer += chunk;
      
      String line;
      while ((line = _extractBtLine()) != "") {
        _handleBtLine(line.trim());
      }
    }, onError: (err) {
      debugPrint('❌ [Bluetooth] Rx Error: $err');
    }, onDone: () {
      debugPrint('📡 [Bluetooth] Connection closed by remote');
      _bluetoothConnection = null;
      bluetoothDevice = null;
      notifyListeners();
    });
  }

  String _extractBtLine() {
    if (_incomingBtBuffer.isEmpty) return "";
    final nIdx = _incomingBtBuffer.indexOf('\n');
    final rIdx = _incomingBtBuffer.indexOf('\r');

    if (nIdx == -1 && rIdx == -1) return "";
    int idx;
    if (nIdx == -1) {
      idx = rIdx;
    } else if (rIdx == -1) {
      idx = nIdx;
    } else {
      idx = (nIdx < rIdx) ? nIdx : rIdx;
    }

    final line = _incomingBtBuffer.substring(0, idx);
    int cut = idx + 1;
    if (idx + 1 < _incomingBtBuffer.length) {
      final a = _incomingBtBuffer[idx];
      final b = _incomingBtBuffer[idx + 1];
      if (a == '\r' && b == '\n') cut = idx + 2;
    }
    _incomingBtBuffer = _incomingBtBuffer.substring(cut);
    return line;
  }

  void _handleBtLine(String line) {
    if (line.isEmpty) return;
    debugPrint('📡 [Bluetooth] RX: $line');
    
    if (line.startsWith("TEMP:")) {
      final valStr = line.replaceFirst("TEMP:", "").trim();
      final val = int.tryParse(valStr);
      if (val != null) {
        _updateLocalBluetoothState(currentTemp: val);
      }
    } else if (line.startsWith("STATUS:") || line.startsWith("STATE:")) {
      final parts = line.split(":");
      if (parts.length > 1) {
        final subParts = parts[1].split(",");
        if (subParts.isNotEmpty) {
          final pwr = subParts[0].toUpperCase() == "ON" ? "ON" : "OFF";
          int? temp;
          if (subParts.length > 1) {
            temp = int.tryParse(subParts[1]);
          }
          _updateLocalBluetoothState(ac: pwr, setTemp: temp);
        }
      }
    }
  }

  void _updateLocalBluetoothState({String? ac, int? setTemp, int? currentTemp}) {
    if (_deviceId.isEmpty) return;
    final lowerId = _deviceId.toLowerCase();
    final existingState = _deviceStates[lowerId] ?? lastState ?? SirisDeviceState(
      deviceId: _deviceId,
      imei: _imei ?? _deviceId,
      ac: 'OFF',
      setTemp: 24,
      currentTemp: 24,
      humidity: 50,
      irOnLearned: true,
      irOffLearned: true,
      status: 'ACTIVE',
      wifiSsid: '',
      wifiIp: '',
      wifiNetwork: 'PRIMARY',
      wifiRssi: -50,
      time: '12:00',
      schOn1: 'DISABLED',
      schOff1: 'DISABLED',
      schOn2: 'DISABLED',
      schOff2: 'DISABLED',
      schOn3: 'DISABLED',
      schOff3: 'DISABLED',
      schOn4: 'DISABLED',
      schOff4: 'DISABLED',
      schOn5: 'DISABLED',
      schOff5: 'DISABLED',
      lunchOn: 'DISABLED',
      lunchOff: 'DISABLED',
    );
    final newState = existingState.copyWith(
      ac: ac,
      setTemp: setTemp,
      currentTemp: currentTemp,
    );
    _deviceStates[lowerId] = newState;
    _recordLastReceivedTime(lowerId);
    _lastState = newState;
    _stateController.add(newState);
    notifyListeners();
  }

  Future<void> sendBluetoothCommand(String cmd) async {
    if (_bluetoothConnection == null || !_bluetoothConnection!.isConnected) {
      debugPrint('⚠️ [Bluetooth] Connection is not active.');
      return;
    }
    try {
      debugPrint('📡 [Bluetooth] TX: $cmd');
      _bluetoothConnection!.output.add(Uint8List.fromList(utf8.encode("$cmd\r\n")));
      await _bluetoothConnection!.output.allSent;
      
      if (cmd == 'SEND:ON') {
        _updateLocalBluetoothState(ac: 'ON');
      } else if (cmd == 'SEND:OFF') {
        _updateLocalBluetoothState(ac: 'OFF');
      } else if (cmd.startsWith('SEND:TEMP_')) {
        final tStr = cmd.replaceFirst('SEND:TEMP_', '');
        final t = int.tryParse(tStr);
        if (t != null) {
          _updateLocalBluetoothState(setTemp: t);
        }
      }

      if (!cmd.startsWith("GET_") && !cmd.startsWith("STATUS")) {
        sendBluetoothCommand("STATUS");
      }
    } catch (e) {
      debugPrint('❌ [Bluetooth] Failed to send command: $e');
    }
  }

  // ── State ──────────────────────────────────────────────────────────────
  final Map<String, SirisDeviceState> _deviceStates = {};
  final Map<String, DateTime> _deviceLastReceivedTime = {};

  void _recordLastReceivedTime(String id) {
    if (id.isEmpty) return;
    _deviceLastReceivedTime[id.toLowerCase()] = DateTime.now();
  }

  SirisDeviceState? _lastState;
  SirisDeviceState? get lastState => _lastState;
  bool get isConnected => _isConnected;
  String get deviceId => _deviceId;

  SirisDeviceState? getLastStateFor(String id) {
    if (id.isEmpty) return null;
    final lowerId = id.toLowerCase();
    
    SirisDeviceState? state;
    if (_deviceStates.containsKey(lowerId)) {
      state = _deviceStates[lowerId];
    } else {
      for (var entry in _deviceStates.entries) {
        final st = entry.value;
        if (st.deviceId.toLowerCase() == lowerId ||
            st.imei.toLowerCase() == lowerId ||
            st.deviceId.toLowerCase().contains(lowerId) ||
            lowerId.contains(st.deviceId.toLowerCase()) ||
            st.imei.toLowerCase().contains(lowerId) ||
            lowerId.contains(st.imei.toLowerCase())) {
          state = st;
          break;
        }
      }
    }

    if (state != null) {
      final lastTime = _deviceLastReceivedTime[state.deviceId.toLowerCase()] ??
          _deviceLastReceivedTime[state.imei.toLowerCase()];
      if (lastTime == null || DateTime.now().difference(lastTime) > const Duration(seconds: 30)) {
        return state.copyWith(status: 'INACTIVE');
      }
      return state;
    }
    return null;
  }

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

  /// Connect to the MQTT broker and subscribe to data.
  /// [deviceId] — the SIRIS device identifier.
  /// [companyId] — optional company ID to fetch MQTT credentials for.
  /// [imei] — the physical IMEI or unique identifier of the device for status matching.
  Future<bool> connect({String? deviceId, String? companyId, String? imei}) async {
    final currentAttempt = ++_connectionAttempt;
    _isConnecting = true;
    _isConnected = false;

    _deviceId = deviceId ?? AppConfig.mqttDeviceId;
    _imei = imei;

    _companyId = (companyId != null && companyId.isNotEmpty)
        ? companyId
        : await AuthService.getCompanyId() ?? '';

    // Start SSE stream in background as HTTP real-time update fallback
    _startSseStream(_companyId, _deviceId, _imei);

    // Disconnect existing client and clean up
    if (_client != null) {
      _client!.autoReconnect = false;
      try {
        _client!.disconnect();
      } catch (_) {}
      _client = null;
    }

    // ── Fetch MQTT credentials from API ──────────────────────────────
    // Calls GET /provisionservice/v1/companies/{companyId}/mqtt-configs
    // Falls back to .env / AppConfig defaults if the API is unreachable.
    final mqttCreds = await MqttConfigService.fetchMqttConfig(
      companyId: companyId,
      type: 'AC',
    );

    final broker = AppConfig.mqttBroker;
    final port = AppConfig.mqttPort;
    final username = mqttCreds?.username.isNotEmpty == true
        ? mqttCreds!.username
        : AppConfig.mqttUsername;
    final password = mqttCreds?.password.isNotEmpty == true
        ? mqttCreds!.password
        : AppConfig.mqttPassword;
    final clientId = 'siris_flutter_${DateTime.now().millisecondsSinceEpoch}';

    debugPrint(
        '🔑 [MQTT] Using credentials: user=$username (source: ${mqttCreds != null ? "API" : ".env/fallback"})');

    _client = MqttServerClient(broker, clientId);
    _client!.port = port;
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 60;
    _client!.autoReconnect = true;
    _client!.onDisconnected = _onDisconnected;
    _client!.onConnected = _onConnected;
    _client!.onAutoReconnect = () {
      debugPrint('🔄 [MQTT] Auto-reconnecting...');
      _isConnected = false;
      _connectionController.add(false);
      notifyListeners();
    };
    _client!.onAutoReconnected = () {
      debugPrint('✅ [MQTT] Auto-reconnected');
      _isConnected = true;
      _connectionController.add(true);
      notifyListeners();
      if (_companyId.isNotEmpty) {
        debugPrint('🔄 [MQTT] Auto-reconnected -> restarting SSE stream...');
        _startSseStream(_companyId, _deviceId, _imei);
      }
      Future.delayed(const Duration(milliseconds: 500), () {
        sendStatus();
      });
    };

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(username, password)
        .startClean();
    _client!.connectionMessage = connMessage;

    try {
      debugPrint(
          '📡 [MQTT] Connecting attempt $currentAttempt to $broker:$port for $_deviceId...');
      await _client!.connect();

      // Discard if a newer connection attempt was started in the meantime
      if (currentAttempt != _connectionAttempt) {
        debugPrint(
            '🚫 [MQTT] Discarding outdated connection attempt $currentAttempt');
        return false;
      }

      if (_client != null &&
          _client!.connectionStatus!.state == MqttConnectionState.connected) {
        _isConnected = true;
        _isConnecting = false;

        // RULE 6: Send STATUS on startup
        Future.delayed(const Duration(milliseconds: 500), () {
          sendStatus();
        });

        _connectionController.add(true);
        notifyListeners();
        debugPrint(
            '✅ [MQTT] Connected (Publish Only). Telemetry is retrieved via SSE Stream.');
        return true;
      }
    } catch (e) {
      debugPrint('❌ [MQTT] Connection error for attempt $currentAttempt: $e');
    }

    // Only update state if this is still the active attempt
    if (currentAttempt == _connectionAttempt) {
      _isConnecting = false;
      _isConnected = false;
      _connectionController.add(false);
      notifyListeners();
    }
    return false;
  }

  void _subscribeToDataTopic() {
    if (_client == null) return;
    final dataTopic = AppConfig.mqttDataTopic;
    _client!.subscribe(dataTopic, MqttQos.atLeastOnce);
    debugPrint('📨 [MQTT] Subscribed to: $dataTopic');

    if (_deviceId.isNotEmpty) {
      final statusTopic = AppConfig.getMqttStatusTopic(_deviceId);
      _client!.subscribe(statusTopic, MqttQos.atLeastOnce);
      debugPrint('📨 [MQTT] Subscribed to: $statusTopic');
    }
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
      final payload =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      final topic = msg.topic;

      debugPrint(
          '📩 [MQTT] Topic: $topic | Payload: ${payload.length > 200 ? "${payload.substring(0, 200)}..." : payload}');

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

      // Check if this is a stream control/connection handshake message (no telemetry data payload)
      if (json['data'] == null && (json['message'] != null || json['cacheStatus'] != null)) {
        debugPrint('ℹ️ [SSE] Stream control message: ${json['message']} (cacheStatus: ${json['cacheStatus']})');
        // Do NOT push INACTIVE state here. The SSE handshake is a stream control
        // message and does not reflect the physical device's WiFi/online state.
        // Online status is driven by actual telemetry data and the watchdog timer.
        return;
      }

      final state = SirisDeviceState.fromJson(json);

      // Cache state for all devices to support instantaneous UI updates on switch
      if (state.deviceId.isNotEmpty) {
        _deviceStates[state.deviceId.toLowerCase()] = state;
        if (state.isActive) {
          _recordLastReceivedTime(state.deviceId);
        }
      }
      if (state.imei.isNotEmpty) {
        _deviceStates[state.imei.toLowerCase()] = state;
        if (state.isActive) {
          _recordLastReceivedTime(state.imei);
        }
      }

      // Only accept messages from our target device
      final bool isMatch = _deviceId.isEmpty ||
          state.deviceId.toLowerCase() == _deviceId.toLowerCase() ||
          state.imei.toLowerCase() == _deviceId.toLowerCase() ||
          (_imei != null && _imei!.isNotEmpty && state.imei.toLowerCase() == _imei!.toLowerCase()) ||
          (_imei != null && _imei!.isNotEmpty && state.deviceId.toLowerCase() == _imei!.toLowerCase()) ||
          state.deviceId
                  .toLowerCase()
                  .replaceAll('_', '')
                  .replaceAll('-', '') ==
              _deviceId.toLowerCase().replaceAll('_', '').replaceAll('-', '');

      if (isMatch) {
        if (_deviceId.isNotEmpty) {
          _deviceStates[_deviceId.toLowerCase()] = state;
          if (state.isActive) {
            _recordLastReceivedTime(_deviceId);
          }
        }
        // Dynamically update _deviceId if it matches via substring/case/IMEI mapping,
        // so that subsequent control publishes target the correct physical device ID.
        // Avoid overwriting a specific device ID with the generic AppConfig.mqttDeviceId fallback.
        final fallbackId = AppConfig.mqttDeviceId.toLowerCase();
        if (state.deviceId.isNotEmpty &&
            _deviceId != state.deviceId &&
            !(state.deviceId.toLowerCase() == fallbackId &&
                _deviceId.toLowerCase() != fallbackId)) {
          debugPrint('🔄 [MQTT] Updating device ID from $_deviceId to ${state.deviceId} to match physical hardware');
          _deviceId = state.deviceId;
        }

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

  void _resetSseWatchdog(String companyId, String deviceId, String? imei) {
    _sseWatchdogTimer?.cancel();
    _sseWatchdogTimer = Timer(const Duration(seconds: 25), () {
      debugPrint('⚠️ [SSE] No data received for 25 seconds. Reconnecting SSE stream...');
      _startSseStream(companyId, deviceId, imei);
    });
  }

  Future<void> _startSseStream(String companyId, String deviceId, String? imei) async {
    _sseWatchdogTimer?.cancel();
    await _sseSub?.cancel();
    _isSseConnected = false;
    notifyListeners();
    if (companyId.isEmpty || (deviceId.isEmpty && (imei == null || imei.isEmpty))) {
      return;
    }
    _resetSseWatchdog(companyId, deviceId, imei);

    try {
      final client = HttpClient();
      final queryParams = <String>[];
      if (companyId.isNotEmpty) {
        queryParams.add('companyid=$companyId');
      }
      if (deviceId.isNotEmpty) {
        queryParams.add('deviceId=$deviceId');
      }
      if (imei != null && imei.isNotEmpty) {
        queryParams.add('imei=$imei');
      }
      final uri = Uri.parse('${AppConfig.provisionBaseUrl}/mqtt/stream?${queryParams.join('&')}');
      
      debugPrint('🌐 [SSE] Connecting to: $uri');
      final request = await client.getUrl(uri);
      request.headers.set('Accept', 'text/event-stream');
      request.headers.set('Cache-Control', 'no-cache');
      
      final token = await AuthService.getCookieHeader();
      if (token != null) {
        request.headers.set('Authorization', 'Bearer $token');
        request.headers.set('Cookie', 'auth_token=$token');
      }

      final response = await request.close();
      if (response.statusCode == 200) {
        debugPrint('🟢 [SSE] Connected successfully');
        _isSseConnected = true;
        notifyListeners();
        
        _sseSub = response
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          _resetSseWatchdog(companyId, deviceId, imei);
          if (line.startsWith('data:')) {
            final dataContent = line.substring(5).trim();
            if (dataContent.isNotEmpty && dataContent.startsWith('{')) {
              debugPrint('📩 [SSE] Received data: $dataContent');
              _sseLastDataTime = DateTime.now();
              _sseLastPayload = dataContent;
              notifyListeners();
              _handleJsonPayload(dataContent);
            }
          }
        }, onError: (e) {
          debugPrint('❌ [SSE] Error in stream: $e');
          _isSseConnected = false;
          notifyListeners();
          Future.delayed(const Duration(seconds: 5), () {
            if (_deviceId == deviceId) {
              _startSseStream(companyId, deviceId, imei);
            }
          });
        }, onDone: () {
          debugPrint('⚠️ [SSE] Stream closed. Reconnecting in 5 seconds...');
          _isSseConnected = false;
          notifyListeners();
          Future.delayed(const Duration(seconds: 5), () {
            if (_deviceId == deviceId) {
              _startSseStream(companyId, deviceId, imei);
            }
          });
        });
      } else {
        debugPrint('❌ [SSE] Connection failed with status: ${response.statusCode}. Retrying in 5 seconds...');
        _isSseConnected = false;
        notifyListeners();
        Future.delayed(const Duration(seconds: 5), () {
          if (_deviceId == deviceId) {
            _startSseStream(companyId, deviceId, imei);
          }
        });
      }
    } catch (e) {
      debugPrint('❌ [SSE] Exception starting stream: $e. Retrying in 5 seconds...');
      _isSseConnected = false;
      notifyListeners();
      Future.delayed(const Duration(seconds: 5), () {
        if (_deviceId == deviceId) {
          _startSseStream(companyId, deviceId, imei);
        }
      });
    }
  }

  void _updateCachedDeviceState(String deviceId, {String? ac, int? setTemp, int? currentTemp}) {
    if (deviceId.isEmpty) return;

    final String lookupId = deviceId.toLowerCase();
    final existing = _deviceStates[lookupId] ??
        _lastState ??
        SirisDeviceState(
          deviceId: deviceId,
          imei: '',
          ac: 'OFF',
          setTemp: 24,
          currentTemp: 0,
          humidity: 0,
          irOnLearned: true,
          irOffLearned: true,
          status: 'ACTIVE',
          wifiSsid: '',
          wifiIp: '',
          wifiNetwork: '',
          wifiRssi: 0,
          time: '',
          schOn1: 'DISABLED', schOff1: 'DISABLED',
          schOn2: 'DISABLED', schOff2: 'DISABLED',
          schOn3: 'DISABLED', schOff3: 'DISABLED',
          schOn4: 'DISABLED', schOff4: 'DISABLED',
          schOn5: 'DISABLED', schOff5: 'DISABLED',
          lunchOn: 'DISABLED', lunchOff: 'DISABLED',
          primarySsid: '',
          secondarySsid: '',
        );

    final updated = existing.copyWith(
      deviceId: existing.deviceId.isNotEmpty ? existing.deviceId : deviceId,
      ac: ac ?? existing.ac,
      setTemp: setTemp ?? existing.setTemp,
      currentTemp: currentTemp ?? existing.currentTemp,
      status: 'ACTIVE',
      time: DateTime.now().toString(),
    );

    _deviceStates[lookupId] = updated;
    _recordLastReceivedTime(lookupId);
    if (updated.deviceId.isNotEmpty) {
      _deviceStates[updated.deviceId.toLowerCase()] = updated;
      _recordLastReceivedTime(updated.deviceId);
    }
    if (updated.imei.isNotEmpty) {
      _deviceStates[updated.imei.toLowerCase()] = updated;
      _recordLastReceivedTime(updated.imei);
    }

    _lastState = updated;
    _stateController.add(updated);
    notifyListeners();
    debugPrint('📝 [MQTT] Updated cached state for $deviceId: ac=${updated.ac}, setTemp=${updated.setTemp}');
  }

  void _handleStringResponse(String payload) {
    final prefix = AppConfig.mqttPayloadPrefix;
    final upper = payload.toUpperCase();

    String? responseDeviceId;
    final parts = payload.split(':');
    if (parts.isNotEmpty && parts[0].isNotEmpty) {
      final candidate = parts[0].trim();
      if (!candidate.contains(' ') &&
          candidate.toUpperCase() != 'TEMP_SET' &&
          candidate.toUpperCase() != 'TEMP_PARTIAL' &&
          candidate.toUpperCase() != 'AC_ON_DONE' &&
          candidate.toUpperCase() != 'AC_OFF_DONE' &&
          candidate.toUpperCase() != 'SCH_SET' &&
          candidate.toUpperCase() != 'SCH_CLEARED' &&
          candidate.toUpperCase() != 'CMD_REJECTED') {
        responseDeviceId = candidate;
      }
    }

    SirisResponse response;

    if (upper.contains('AC_ON_DONE')) {
      if (responseDeviceId != null) {
        _updateCachedDeviceState(responseDeviceId, ac: 'ON');
      }
      response = SirisResponse(
        type: SirisResponseType.acOnDone,
        rawPayload: payload,
      );
    } else if (upper.contains('AC_OFF_DONE')) {
      if (responseDeviceId != null) {
        _updateCachedDeviceState(responseDeviceId, ac: 'OFF');
      }
      response = SirisResponse(
        type: SirisResponseType.acOffDone,
        rawPayload: payload,
      );
    } else if (upper.contains('TEMP_SET')) {
      final detail =
          payload.split(':').length > 2 ? payload.split(':').last.trim() : null;
      if (responseDeviceId != null && detail != null) {
        final parsedTemp = int.tryParse(detail);
        if (parsedTemp != null) {
          _updateCachedDeviceState(responseDeviceId, setTemp: parsedTemp);
        }
      }
      response = SirisResponse(
        type: SirisResponseType.tempSet,
        rawPayload: payload,
        detail: detail,
      );
    } else if (upper.contains('TEMP_PARTIAL')) {
      final detail =
          payload.split(':').length > 2 ? payload.split(':').last.trim() : null;
      if (responseDeviceId != null && detail != null) {
        final parsedTemp = int.tryParse(detail);
        if (parsedTemp != null) {
          _updateCachedDeviceState(responseDeviceId, setTemp: parsedTemp);
        }
      }
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
    } else if (upper.contains('WIFI_PRIMARY_SET')) {
      final detail = payload.split(':').last.trim();
      response = SirisResponse(
        type: SirisResponseType.wifiPrimarySet,
        rawPayload: payload,
        detail: detail,
      );
    } else if (upper.contains('WIFI_SECONDARY_SET')) {
      final detail = payload.split(':').last.trim();
      response = SirisResponse(
        type: SirisResponseType.wifiSecondarySet,
        rawPayload: payload,
        detail: detail,
      );
    } else if (upper.contains('WIFI_RESET_BT_OPEN')) {
      response = SirisResponse(
        type: SirisResponseType.wifiResetBtOpen,
        rawPayload: payload,
      );
    } else if (upper.contains('WIFI_INFO')) {
      final parts = payload.split(':');
      final detail = parts.length > 2 ? parts.sublist(2).join(':') : null;
      response = SirisResponse(
        type: SirisResponseType.wifiInfo,
        rawPayload: payload,
        detail: detail,
      );

      try {
        String? responseDeviceId;
        if (parts.isNotEmpty && parts[0].isNotEmpty) {
          final candidate = parts[0].trim();
          if (!candidate.contains(' ') &&
              candidate.toUpperCase() != 'WIFI_INFO') {
            responseDeviceId = candidate;
          }
        }

        String primarySsid = '';
        String secondarySsid = '';
        String active = 'PRIMARY';
        int rssi = 0;

        for (final part in parts) {
          final kv = part.split('=');
          if (kv.length == 2) {
            final key = kv[0].trim().toLowerCase();
            final value = kv[1].trim();
            if (key == 'primary') {
              primarySsid = value;
            } else if (key == 'secondary') {
              secondarySsid = value;
            } else if (key == 'active') {
              active = value.toUpperCase();
            } else if (key == 'rssi') {
              rssi = int.tryParse(value) ?? 0;
            }
          }
        }

        final connectedSsid = (active == 'SECONDARY') ? secondarySsid : primarySsid;

        final lookupId = responseDeviceId ?? _deviceId;
        final baseState = _deviceStates[lookupId.toLowerCase()] ?? _lastState ?? SirisDeviceState(
          deviceId: lookupId,
          imei: '',
          ac: 'OFF',
          setTemp: 24,
          currentTemp: 0,
          humidity: 0,
          irOnLearned: true,
          irOffLearned: true,
          status: 'ACTIVE',
          wifiSsid: '',
          wifiIp: '',
          wifiNetwork: '',
          wifiRssi: 0,
          time: '',
          schOn1: 'DISABLED', schOff1: 'DISABLED',
          schOn2: 'DISABLED', schOff2: 'DISABLED',
          schOn3: 'DISABLED', schOff3: 'DISABLED',
          schOn4: 'DISABLED', schOff4: 'DISABLED',
          schOn5: 'DISABLED', schOff5: 'DISABLED',
          lunchOn: 'DISABLED', lunchOff: 'DISABLED',
          primarySsid: '',
          secondarySsid: '',
        );

        final newState = baseState.copyWith(
          deviceId: baseState.deviceId.isNotEmpty ? baseState.deviceId : lookupId,
          status: 'ACTIVE',
          wifiSsid: connectedSsid,
          wifiNetwork: active,
          wifiRssi: rssi,
          primarySsid: primarySsid,
          secondarySsid: secondarySsid,
        );

        if (lookupId.isNotEmpty) {
          _deviceStates[lookupId.toLowerCase()] = newState;
          _recordLastReceivedTime(lookupId);
          if (newState.deviceId.isNotEmpty) {
            _deviceStates[newState.deviceId.toLowerCase()] = newState;
            _recordLastReceivedTime(newState.deviceId);
          }
          if (newState.imei.isNotEmpty) {
            _deviceStates[newState.imei.toLowerCase()] = newState;
            _recordLastReceivedTime(newState.imei);
          }
        }

        _lastState = newState;
        _stateController.add(newState);
        notifyListeners();
      } catch (e) {
        debugPrint('❌ Error parsing WIFI_INFO: $e');
      }
    } else if (upper.contains('WIFI_ROLLBACK')) {
      final detail = payload.split(':').last.trim();
      response = SirisResponse(
        type: SirisResponseType.wifiRollback,
        rawPayload: payload,
        detail: detail,
      );
    } else if (upper.contains('WIFI_ERR')) {
      final detail = payload.split(':').last.trim();
      response = SirisResponse(
        type: SirisResponseType.wifiError,
        rawPayload: payload,
        detail: detail,
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
  bool _publish(String topic, String message) {
    if (_client == null ||
        _client!.connectionStatus!.state != MqttConnectionState.connected) {
      debugPrint('⚠️ [MQTT] Cannot publish — not connected. Topic: $topic, Message: $message');
      return false;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!,
        retain: false);
    debugPrint('📤 [MQTT] Published to $topic: $message');
    return true;
  }

  /// Send a custom control command to the control topic.
  void sendControlCommand(String command) {
    if (isBluetoothConnected) {
      sendBluetoothCommand(command);
    } else {
      final topic = AppConfig.getMqttControlTopic(_deviceId);
      _publish(topic, command);
    }
  }

  // ── AC Power Control ──────────────────────────────────────────────────

  /// Turn AC ON.
  void turnAcOn() {
    if (isBluetoothConnected) {
      sendBluetoothCommand('SEND:ON');
    } else {
      final topic = AppConfig.getMqttControlTopic(_deviceId);
      _publish(topic, 'ON');
    }
  }

  /// Turn AC OFF.
  void turnAcOff() {
    if (isBluetoothConnected) {
      sendBluetoothCommand('SEND:OFF');
    } else {
      final topic = AppConfig.getMqttControlTopic(_deviceId);
      _publish(topic, 'OFF');
    }
  }

  /// Request device STATUS.
  void sendStatus() {
    if (isBluetoothConnected) {
      sendBluetoothCommand('STATUS');
    } else {
      final topic = AppConfig.getMqttControlTopic(_deviceId);
      _publish(topic, 'STATUS');
    }
  }

  // ── Temperature Control (RULE 12: integer only) ───────────────────────

  /// Set temperature (16–30, integer only).
  /// Publishes to ALL known command paths to ensure firmware compatibility:
  ///   1. Plain integer to control topic (same as ON/OFF — primary path)
  ///   2. Plain integer to control/set_temp sub-topic (SIRIS spec)
  ///   3. TEMP_CN:<int> to control topic (legacy firmware format)
  void setTemperature(int temp) {
    if (temp < 16 || temp > 30) {
      debugPrint('⚠️ Temperature out of range: $temp');
      return;
    }

    if (isBluetoothConnected) {
      sendBluetoothCommand('SEND:TEMP_$temp');
    } else {
      final ctrlTopic = AppConfig.getMqttControlTopic(_deviceId);
      final tempTopic = AppConfig.getMqttTempTopic(_deviceId);

      // 1. PRIMARY: Plain integer on the control topic (device subscribes here for ON/OFF/STATUS)
      _publish(ctrlTopic, '$temp');

      // 2. SIRIS spec: Plain integer on the dedicated set_temp sub-topic
      _publish(tempTopic, '$temp');

      // 3. Legacy format: TEMP_CN:<int> on control topic (some firmware versions)
      _publish(ctrlTopic, 'TEMP_CN:$temp');

      debugPrint('🌡️ [MQTT] Temperature $temp sent to 3 paths for $_deviceId');
    }
  }

  // ── Schedule Control (RULE 11: HH:MM format, RULE 3: never send DISABLED) ─

  /// Optimistically update a schedule slot in local state and emit to stream.
  /// This ensures the UI reflects the change immediately without waiting for
  /// the device's STATUS response via SSE.
  void updateScheduleOptimistic({
    int? slot,
    String? onTime,
    String? offTime,
    bool clear = false,
  }) {
    if (_lastState == null) return;

    final Map<String, String?> updates = {};
    if (slot != null) {
      if (clear) {
        updates['schOn$slot'] = 'DISABLED';
        updates['schOff$slot'] = 'DISABLED';
      } else {
        if (onTime != null) updates['schOn$slot'] = onTime;
        if (offTime != null) updates['schOff$slot'] = offTime;
      }
    }

    final updated = _lastState!.copyWith(
      schOn1: updates['schOn1'],
      schOff1: updates['schOff1'],
      schOn2: updates['schOn2'],
      schOff2: updates['schOff2'],
      schOn3: updates['schOn3'],
      schOff3: updates['schOff3'],
      schOn4: updates['schOn4'],
      schOff4: updates['schOff4'],
      schOn5: updates['schOn5'],
      schOff5: updates['schOff5'],
    );

    _lastState = updated;
    final lookupId = updated.deviceId.toLowerCase();
    if (lookupId.isNotEmpty) {
      _deviceStates[lookupId] = updated;
    }
    _stateController.add(updated);
    notifyListeners();
    debugPrint('📅 [MQTT] Optimistic schedule update emitted for slot $slot');
  }

  void updateLunchOptimistic({
    String? lunchOn,
    String? lunchOff,
    bool clear = false,
  }) {
    if (_lastState == null) return;

    final updated = _lastState!.copyWith(
      lunchOn: clear ? 'DISABLED' : (lunchOn ?? _lastState!.lunchOn),
      lunchOff: clear ? 'DISABLED' : (lunchOff ?? _lastState!.lunchOff),
    );

    _lastState = updated;
    final lookupId = updated.deviceId.toLowerCase();
    if (lookupId.isNotEmpty) {
      _deviceStates[lookupId] = updated;
    }
    _stateController.add(updated);
    notifyListeners();
    debugPrint('📅 [MQTT] Optimistic lunch update emitted');
  }

  String? _normalizeTime(String time) {
    // Allow single-digit hour e.g. '8:00' -> '08:00'
    final regex = RegExp(r'^([01]?\d|2[0-3]):([0-5]\d)$');
    final match = regex.firstMatch(time);
    if (match == null) {
      debugPrint('⚠️ [MQTT] Invalid time format: $time (expected HH:MM)');
      return null;
    }
    final hour = match.group(1)!.padLeft(2, '0');
    final minute = match.group(2)!.padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Set a schedule ON time. [slot] is 1–5, [time] is "HH:MM" (24hr, zero-padded).
  void setScheduleOn(int slot, String time) {
    final normalized = _normalizeTime(time);
    if (normalized == null) return;
    debugPrint('📅 [MQTT] Setting Schedule ON slot $slot -> $normalized');
    if (isBluetoothConnected) {
      sendBluetoothCommand('SCH_ON$slot:$normalized');
    } else {
      final topic = AppConfig.getMqttScheduleTopic(_deviceId);
      _publish(topic, 'SCH_ON$slot:$normalized');
    }
  }

  /// Set a schedule OFF time. [slot] is 1–5, [time] is "HH:MM".
  void setScheduleOff(int slot, String time) {
    final normalized = _normalizeTime(time);
    if (normalized == null) return;
    debugPrint('📅 [MQTT] Setting Schedule OFF slot $slot -> $normalized');
    if (isBluetoothConnected) {
      sendBluetoothCommand('SCH_OFF$slot:$normalized');
    } else {
      final topic = AppConfig.getMqttScheduleTopic(_deviceId);
      _publish(topic, 'SCH_OFF$slot:$normalized');
    }
  }

  /// Set lunch ON time.
  void setLunchOn(String time) {
    final normalized = _normalizeTime(time);
    if (normalized == null) return;
    if (isBluetoothConnected) {
      sendBluetoothCommand('LUNCH_ON:$normalized');
    } else {
      final topic = AppConfig.getMqttScheduleTopic(_deviceId);
      _publish(topic, 'LUNCH_ON:$normalized');
    }
  }

  /// Set lunch OFF time.
  void setLunchOff(String time) {
    final normalized = _normalizeTime(time);
    if (normalized == null) return;
    if (isBluetoothConnected) {
      sendBluetoothCommand('LUNCH_OFF:$normalized');
    } else {
      final topic = AppConfig.getMqttScheduleTopic(_deviceId);
      _publish(topic, 'LUNCH_OFF:$normalized');
    }
  }

  // ── Schedule Clear ────────────────────────────────────────────────────

  /// Clear ALL schedule slots at once.
  void clearAllSchedules() {
    debugPrint('📅 [MQTT] Clearing ALL schedules');
    if (isBluetoothConnected) {
      sendBluetoothCommand('SCH_CLEAR');
    } else {
      final topic = AppConfig.getMqttScheduleTopic(_deviceId);
      _publish(topic, 'SCH_CLEAR');
    }
  }

  /// Clear a specific schedule slot (1–5).
  void clearScheduleSlot(int slot) {
    debugPrint('📅 [MQTT] Clearing schedule slot $slot');
    if (isBluetoothConnected) {
      sendBluetoothCommand('SCH_CLEAR$slot');
    } else {
      final topic = AppConfig.getMqttScheduleTopic(_deviceId);
      _publish(topic, 'SCH_CLEAR$slot');
    }
  }

  /// Clear the lunch slot.
  void clearLunchSlot() {
    if (isBluetoothConnected) {
      sendBluetoothCommand('SCH_CLEAR_LUNCH');
    } else {
      final topic = AppConfig.getMqttScheduleTopic(_deviceId);
      _publish(topic, 'SCH_CLEAR_LUNCH');
    }
  }

  /// Get current schedule state.
  void getScheduleStatus() {
    debugPrint('📅 [MQTT] Requesting schedule STATUS');
    if (isBluetoothConnected) {
      sendBluetoothCommand('SCH_STATUS');
    } else {
      final topic = AppConfig.getMqttScheduleTopic(_deviceId);
      _publish(topic, 'STATUS');
    }
  }

  // ── WiFi Configuration & Reset ────────────────────────────────────────

  /// Send a WiFi reset command to reopen the 60s Bluetooth provisioning window.
  void sendWifiReset() {
    final wifiTopic = AppConfig.getMqttWifiTopic(_deviceId);
    _publish(wifiTopic, 'WIFI_RESET');
  }

  /// Request WiFi info via MQTT.
  void requestWifiStatus() {
    final wifiTopic = AppConfig.getMqttWifiTopic(_deviceId);
    _publish(wifiTopic, 'STATUS');
  }

  /// Set primary WiFi credentials via MQTT.
  void setPrimaryWifiMqtt(String ssid, String password) {
    final wifiTopic = AppConfig.getMqttWifiTopic(_deviceId);
    _publish(wifiTopic, 'PRIMARY:$ssid,$password');
  }

  /// Send a WiFi connect command to switch to/connect to the configured WiFi.
  void sendWifiConnect() {
    final wifiTopic = AppConfig.getMqttWifiTopic(_deviceId);
    _publish(wifiTopic, 'WIFI_CONNECT');
  }

  /// Set secondary WiFi credentials via MQTT.
  void setSecondaryWifiMqtt(String ssid, String password) {
    final wifiTopic = AppConfig.getMqttWifiTopic(_deviceId);
    _publish(wifiTopic, 'SECONDARY:$ssid,$password');
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
    _sseWatchdogTimer?.cancel();
    _sseWatchdogTimer = null;
    _sseSub?.cancel();
    _sseSub = null;
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
