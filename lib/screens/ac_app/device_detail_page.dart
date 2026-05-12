import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'dart:async';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:ir_blaster_ac/widgets/trends_table.dart';
import 'package:ir_blaster_ac/core/config/app_config.dart';
import 'package:ir_blaster_ac/core/services/local_cache_service.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class DeviceDetailPage extends StatefulWidget {
  final String deviceName;
  final String systemId;
  final String systemShortId;

  const DeviceDetailPage({
    Key? key,
    required this.deviceName,
    required this.systemId,
    required this.systemShortId,
  }) : super(key: key);

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage>
    with SingleTickerProviderStateMixin {
  // UI State
  double _setTemperature = 24.0; // Fixed static value
  double _actualTemperature = 0.0;
  bool _isOnline = false; // Tracks WIFI/Online status (initialized to inactive)
  ScaffoldMessengerState? _messenger;
  int _humidity = 0;
  String _scheduleOn1 = '--:--';
  String _scheduleOff1 = '--:--';
  String _scheduleOn2 = '--:--';
  String _scheduleOff2 = '--:--';
  String _scheduleOn3 = '--:--';
  String _scheduleOff3 = '--:--';
  String _lunchOn = '--:--';
  String _lunchOff = '--:--';
  bool _isAuto = false;
  bool _isPowerOn = true; // Tracks the MQTT Power Status
  DateTime? _inactiveStartTime; // Track when device became inactive
  String _inactiveTimeString = 'N/A'; // Display string for inactive time

  // Chart & Log State
  final List<_ChartData> _tempHistory = [];
  final List<Map<String, dynamic>> _recentLogs = [];

  // Equipment State
  List<Map<String, dynamic>> _equipmentsData = [];
  List<String> _equipments = [];
  bool _isLoadingEquipments = true;
  bool _isTelemetryLoading = true;
  String _selectedEquipmentName = '';
  String _selectedEquipmentId = '';
  String _selectedEquipmentTypeId = '';
  String _selectedEquipmentShortId = '';
  String _deviceId = ''; // IMEI

  // Stream State
  StreamSubscription? _subscription;
  DateTime _lastUpdateTime = DateTime.now(); // For throttling UI updates
  DateTime _lastManualCommandTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isPowerCommandLock = false;
  DateTime _lastSetStateTime = DateTime.now(); // For throttling UI rebuilds

  // Animation State
  AnimationController? _pulseController;

  // Polling State
  Timer? _pollTimer;
  Timer? _inactiveTimeUpdateTimer; // Timer to update inactive time display
  Timer? _statusWatchdogTimer; // Timer to detect device disconnects
  MqttServerClient? _persistentMqttClient;
  String _subscribedDeviceId = '';
  DateTime _lastMessageReceivedTime = DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.of(context);
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _selectedEquipmentName = widget.deviceName;
    _fetchEquipments();

    // Seed initial data for chart
    for (int i = 0; i < 10; i++) {
      _tempHistory.add(
        _ChartData(
          DateTime.now().subtract(Duration(minutes: 10 - i)),
          30 + math.Random().nextDouble() * 5,
        ),
      );
    }

    _setupPersistentMqtt();
    _loadCachedStatus();
    _loadCachedEquipments();

    // Telemetry is no longer "loading" once we have the persistent connection active
    if (mounted) {
      setState(() => _isTelemetryLoading = false);
    }

    // Setup timer to update inactive time display every second
    _inactiveTimeUpdateTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && _inactiveStartTime != null) {
        _updateInactiveTimeString();
      }
    });

    // Efficient Watchdog: Periodically check if we haven't received a message in 10 seconds
    _statusWatchdogTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted && _isOnline) {
        if (DateTime.now().difference(_lastMessageReceivedTime) >
            const Duration(seconds: 10)) {
          setState(() {
            _isOnline = false;
            _inactiveStartTime = DateTime.now();
            debugPrint(
                '⚠️ [Watchdog] No messages received for 10s. Setting to OFFLINE.');
          });
        }
      }
    });
  }

  Future<void> _loadCachedEquipments() async {
    final cached = await LocalCacheService.getEquipmentList(widget.systemId);
    if (cached != null && mounted) {
      _applyEquipmentData(cached);
    }
  }

  void _applyEquipmentData(List<dynamic> equipmentList) {
    if (!mounted) return;
    setState(() {
      try {
        _equipmentsData =
            equipmentList.map((e) => Map<String, dynamic>.from(e)).toList();
        _equipments = _equipmentsData
            .map((e) => e['name']?.toString() ?? 'Unknown')
            .toList();
        _isLoadingEquipments = false;

        if (_equipmentsData.isNotEmpty) {
          final initialIndex = _equipmentsData.indexWhere(
            (e) => e['name'] == widget.deviceName,
          );
          final targetIndex = initialIndex != -1 ? initialIndex : 0;
          final Map<String, dynamic> eData = _equipmentsData[targetIndex];

          _selectedEquipmentId = (eData['equipmentId'] ??
                      eData['EquipmentId'] ??
                      eData['id'] ??
                      eData['Id'])
                  ?.toString() ??
              '';
          _selectedEquipmentName =
              (eData['name'] ?? eData['Name'])?.toString() ?? '';
          _selectedEquipmentTypeId =
              (eData['equipmentTypeId'] ?? eData['EquipmentTypeId'])
                      ?.toString() ??
                  '';
          _selectedEquipmentShortId = (eData['shortId'] ??
                      eData['ShortId'] ??
                      eData['equipmentShortId'] ??
                      eData['SystemShortId'])
                  ?.toString() ??
              '';

          // Prioritize IMEI for MQTT communication as requested
          final imei = (eData['imei'] ?? eData['Imei'])?.toString() ?? '';
          _deviceId = imei.isNotEmpty
              ? imei
              : (_selectedEquipmentShortId.isNotEmpty
                  ? _selectedEquipmentShortId
                  : _selectedEquipmentId);

          debugPrint(
              '📡 [DeviceDetail] Active Device ID (Topic): $_deviceId (IMEI: $imei)');

          // Re-trigger MQTT setup with the new ID if it changed
          _setupPersistentMqtt();
        }
      } catch (e) {
        debugPrint('âš ï¸  Error mapping equipment data: $e');
      }
    });
  }

  Future<void> _loadCachedStatus() async {
    final cached =
        await LocalCacheService.getDeviceStatus(widget.systemShortId);
    if (cached != null && mounted) {
      final status = cached['status'];
      setState(() {
        if (status['temp'] != null)
          _actualTemperature = (status['temp'] as num).toDouble();
        if (status['hum'] != null) _humidity = (status['hum'] as num).toInt();
        if (status['power'] != null) _isPowerOn = status['power'] as bool;
        // WiFi Online status is no longer loaded from cache to ensure it always starts as INACTIVE
        // and only becomes ACTIVE when a fresh MQTT status JSON is received.
      });
    }
  }

  @override
  void dispose() {
    _closeStream();
    _pulseController?.dispose();
    _pollTimer?.cancel();
    _inactiveTimeUpdateTimer?.cancel();
    _statusWatchdogTimer?.cancel();
    _persistentMqttClient?.disconnect();
    // Safely clear any active snackbars using the stored messenger reference
    _messenger?.clearSnackBars();
    super.dispose();
  }

  void _closeStream() {
    _subscription?.cancel();
    _subscription = null;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _fetchEquipments() async {
    final companyId = await AuthService.getCompanyId() ?? '';
    final siteId = await AuthService.getSiteId() ?? '';
    final bucket = await AuthService.getBucket() ?? '';
    final token = await AuthService.getCookieHeader() ?? '';

    final url =
        '${AppConfig.provisionBaseUrl}/systems/equipment/${widget.systemId}'
        '?companyId=$companyId&siteId=$siteId&bucket=$bucket';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final dynamic listData = data['data'];

        if (listData != null && listData is List && mounted) {
          final List<dynamic> equipmentList = listData;
          _applyEquipmentData(equipmentList);
          // Save to cache
          LocalCacheService.saveEquipmentList(widget.systemId, equipmentList);
        } else if (mounted) {
          setState(() => _isLoadingEquipments = false);
        }
      }
    } catch (e) {
      debugPrint('Error fetching equipments: $e');
      if (mounted) {
        setState(() => _isLoadingEquipments = false);
      }
    }
  }

  Future<void> _onEquipmentSelected(
    String equipmentId,
    String name,
    String typeId,
    String shortId,
  ) async {
    debugPrint(
      '🔄 SWITCHING EQUIPMENT: ID=$equipmentId, Name=$name, ShortId=$shortId',
    );
    if (_selectedEquipmentId == equipmentId &&
        _selectedEquipmentShortId.isNotEmpty) return;

    _closeStream();

    // Resolve IMEI using the helper function to avoid redundancy
    final String resolvedDeviceId = await _fetchEquipmentImei(equipmentId);
    final String deviceId =
        resolvedDeviceId.isNotEmpty ? resolvedDeviceId : shortId;

    setState(() {
      _selectedEquipmentId = equipmentId;
      _selectedEquipmentName = name;
      _selectedEquipmentTypeId = typeId;
      _selectedEquipmentShortId = shortId;
      _deviceId = deviceId; // Set to IMEI if found, else fallback to shortId
      _isLoadingEquipments = true;
      _isOnline =
          false; // Reset to inactive until confirmed by new device status JSON
      _isTelemetryLoading = true;
      _tempHistory.clear();
      _recentLogs.clear();
    });

    // The deviceId is already resolved above

    if (mounted) {
      setState(() {
        _deviceId = deviceId;
        _isLoadingEquipments = false;
        _setupPersistentMqtt();
      });

      if (deviceId.isNotEmpty) {
        // HTTP Stream disabled to fix lag - all telemetry is now handled via direct MQTT
        // _connectToStream(imei);
      } else {
        setState(() => _isTelemetryLoading = false);
      }
    }
  }

  Future<void> _togglePower(bool value) async {
    debugPrint('ðŸ”” [ACTION] POWER TOGGLE: IMEI=$_deviceId, NewValue=$value');
    final companyId = await AuthService.getCompanyId() ?? '';
    final token = await AuthService.getCookieHeader() ?? '';

    // 1. Fetch MQTT Configs
    final configUrl =
        '${AppConfig.provisionBaseUrl}/companies/$companyId/mqtt-configs';
    Map<String, dynamic>? selectedConfig;

    try {
      final response = await http.get(
        Uri.parse(configUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> configs = data['data'] ?? [];

        // Find config with type 'ac_compressor'
        selectedConfig = configs.firstWhere(
          (c) => c['type'] == 'ac_compressor',
          orElse: () => null,
        );
      }
    } catch (e) {
      debugPrint('â Œ Error fetching MQTT configs: $e');
    }

    if (selectedConfig == null) {
      debugPrint('âš ï¸  No AC Compressor MQTT config found, using defaults.');
    }

    _publishMqttCommand(value ? 'ON' : 'OFF');

    if (mounted) {
      _messenger?.showSnackBar(
        SnackBar(
          content: Text(
              'Power ${value ? 'ON' : 'OFF'} for Device: ${_deviceId.isEmpty ? 'testir' : _deviceId}'),
          backgroundColor: value ? Colors.green : Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  bool _isConnectingMqtt = false;

  Future<void> _setupPersistentMqtt() async {
    if (_isConnectingMqtt) return;
    if (_persistentMqttClient?.connectionStatus?.state ==
            MqttConnectionState.connected &&
        _subscribedDeviceId == _deviceId) {
      return;
    }

    // Disconnect existing client if we're switching devices
    if (_persistentMqttClient?.connectionStatus?.state ==
        MqttConnectionState.connected) {
      _persistentMqttClient!.disconnect();
    }

    _isConnectingMqtt = true;

    final String broker = AppConfig.mqttBroker;
    final String topic = AppConfig.mqttTopic;
    final String username = AppConfig.mqttUsername;
    final String password = AppConfig.mqttPassword;

    _persistentMqttClient = MqttServerClient(
      broker,
      'flutter_live_${DateTime.now().millisecondsSinceEpoch}',
    );
    _persistentMqttClient!.port = 1883;
    _persistentMqttClient!.logging(on: false);
    _persistentMqttClient!.keepAlivePeriod = 60;
    _persistentMqttClient!.onDisconnected =
        () => debugPrint('ðŸ”Œ [MQTT Live] Disconnected');

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(
            'flutter_live_${DateTime.now().millisecondsSinceEpoch}')
        .authenticateAs(username, password)
        .startClean();
    _persistentMqttClient!.connectionMessage = connMessage;

    try {
      debugPrint('ðŸ“¡ [MQTT Live] Connecting...');
      await _persistentMqttClient!.connect();
      _isConnectingMqtt = false;
      if (_persistentMqttClient!.connectionStatus!.state ==
          MqttConnectionState.connected) {
        final statusTopic = _getDeviceTopic('status');
        debugPrint(
            'âœ… [MQTT Live] Connected. Subscribing to root testir and $statusTopic');
        _persistentMqttClient!.subscribe('testir', MqttQos.atLeastOnce);
        _persistentMqttClient!.subscribe('testir/#', MqttQos.atLeastOnce);
        _persistentMqttClient!.subscribe(statusTopic, MqttQos.atLeastOnce);
        _subscribedDeviceId = _deviceId;

        _persistentMqttClient!.updates!
            .listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
          final recMess = c![0].payload as MqttPublishMessage;
          final String topic = c![0].topic;
          final pt =
              MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
          _handleMqttTelemetry(topic, pt);
        });
      }
    } catch (e) {
      _isConnectingMqtt = false;
      debugPrint('? [MQTT Live] Connection Error: $e');
      Future.delayed(const Duration(seconds: 3), () => _setupPersistentMqtt());
    }
  }

  void _handleMqttTelemetry(String topic, String payload) {
    final String statusTopic = _getDeviceTopic('status');
    final bool isStatusTopic = topic == statusTopic;
    bool hasChanges = false;
    final String upperPayload = payload.trim().toUpperCase();

    // 0. Handle JSON Payload
    if (payload.trim().startsWith('{')) {
      try {
        // Fix potentially malformed JSON from device (e.g., "set_temp":,)
        String safePayload = payload;
        if (safePayload.contains('"set_temp":,')) {
          safePayload =
              safePayload.replaceAll('"set_temp":,', '"set_temp":null,');
        }

        final data = jsonDecode(safePayload);
        final Map<String, dynamic> p = (data['data'] != null)
            ? Map<String, dynamic>.from(data['data'])
            : Map<String, dynamic>.from(data);

        // Robust Device ID extraction from JSON
        final String incomingDeviceId =
            (p['device_id'] ?? p['deviceId'] ?? data['device_id'] ?? '')
                .toString();

        // Activation logic:
        // 1. Matches specific device topic
        // 2. Matches current device ID (IMEI/ShortId)
        // 3. Matches legacy/default 'Sustainabyte_testir' ID
        final bool isMatchingDevice = isStatusTopic ||
            (incomingDeviceId.isNotEmpty &&
                incomingDeviceId.toLowerCase() == _deviceId.toLowerCase()) ||
            incomingDeviceId == 'Sustainabyte_testir';

        if (isMatchingDevice) {
          // Efficiently reset watchdog by simply updating the timestamp
          _lastMessageReceivedTime = DateTime.now();

          if (p['temp'] != null || p['current_temp'] != null) {
            _actualTemperature =
                (p['temp'] ?? p['current_temp'] as num).toDouble();
            hasChanges = true;
          }
          if (p['hum'] != null) {
            _humidity = (p['hum'] as num).toInt();
            hasChanges = true;
          }
          if (p['ac'] != null || p['ACStatus'] != null) {
            final acVal = (p['ac'] ?? p['ACStatus']).toString().toUpperCase();
            _isPowerCommandLock = false;
            _isPowerOn = (acVal == 'ON' || acVal == '1' || acVal == 'TRUE');
            hasChanges = true;
          }

          // STRICT GATING for WiFi/Online Status
          // We strictly require an explicit status field in the JSON to maintain ACTIVE state.
          final rawStatus =
              p['status'] ?? p['Status'] ?? p['online'] ?? p['Online'];

          if (rawStatus != null) {
            final String stVal = rawStatus.toString().toUpperCase();
            final bool wasOnline = _isOnline;
            _isOnline = (stVal == 'ACTIVE' || stVal == 'ONLINE');

            if (_isOnline != wasOnline) {
              if (_isOnline) {
                _inactiveStartTime = null;
              } else {
                _inactiveStartTime = DateTime.now();
              }
              hasChanges = true;
              debugPrint(
                  '📡 [MQTT] Status Updated: $_isOnline (Topic: $topic, ID: $incomingDeviceId)');
            }
          } else {
            // "otherwise i want an inactive" - if status field is missing entirely, ensure it is inactive.
            final bool wasOnline = _isOnline;
            _isOnline = false;
            if (_isOnline != wasOnline) {
              _inactiveStartTime = DateTime.now();
              hasChanges = true;
              debugPrint(
                  '📡 [MQTT] Status Updated: $_isOnline (Topic: $topic, ID: $incomingDeviceId) - Missing status field');
            }
          }

          // Schedule parsing from JSON (now inside the device matching block)
          bool scheduleChanged = false;
          if (p['sch_on1'] != null) {
            _scheduleOn1 = p['sch_on1'].toString();
            scheduleChanged = true;
          }
          if (p['sch_off1'] != null) {
            _scheduleOff1 = p['sch_off1'].toString();
            scheduleChanged = true;
          }
          if (p['sch_on2'] != null) {
            _scheduleOn2 = p['sch_on2'].toString();
            scheduleChanged = true;
          }
          if (p['sch_off2'] != null) {
            _scheduleOff2 = p['sch_off2'].toString();
            scheduleChanged = true;
          }
          if (p['sch_on3'] != null) {
            _scheduleOn3 = p['sch_on3'].toString();
            scheduleChanged = true;
          }
          if (p['sch_off3'] != null) {
            _scheduleOff3 = p['sch_off3'].toString();
            scheduleChanged = true;
          }
          if (p['lunch_on'] != null) {
            _lunchOn = p['lunch_on'].toString();
            scheduleChanged = true;
          }
          if (p['lunch_off'] != null) {
            _lunchOff = p['lunch_off'].toString();
            scheduleChanged = true;
          }

          if (scheduleChanged) {
            hasChanges = true;
            debugPrint('✅ [MQTT JSON] Mapped Schedules for $incomingDeviceId');
          }
        } else {
          // Log background messages from other devices occasionally
          if (DateTime.now().second % 60 == 0) {
            debugPrint(
                'ℹ️ [MQTT] Background message for: $incomingDeviceId (Active: $_deviceId)');
          }
        }
      } catch (e) {
        debugPrint('❌ Error parsing MQTT JSON: $e');
      }
    } else {
      // 1. Explicit Schedule & Lunch Parsing
      if (upperPayload.contains('SCH_ON1')) {
        _scheduleOn1 = _extractTime(payload);
        hasChanges = true;
      } else if (upperPayload.contains('SCH_ON2')) {
        _scheduleOn2 = _extractTime(payload);
        hasChanges = true;
      } else if (upperPayload.contains('SCH_ON3')) {
        _scheduleOn3 = _extractTime(payload);
        hasChanges = true;
      } else if (upperPayload.contains('SCH_OFF1')) {
        _scheduleOff1 = _extractTime(payload);
        hasChanges = true;
      } else if (upperPayload.contains('SCH_OFF2')) {
        _scheduleOff2 = _extractTime(payload);
        hasChanges = true;
      } else if (upperPayload.contains('SCH_OFF3')) {
        _scheduleOff3 = _extractTime(payload);
        hasChanges = true;
      } else if (upperPayload.contains('LUNCH_ON')) {
        _lunchOn = _extractTime(payload);
        hasChanges = true;
      } else if (upperPayload.contains('LUNCH_OFF')) {
        _lunchOff = _extractTime(payload);
        hasChanges = true;
      }

      // 2. Clearing Commands
      if (upperPayload.contains('SCH_CLEAR_LUNCH')) {
        // "This will clear all scedule"
        _scheduleOn1 = '--:--';
        _scheduleOff1 = '--:--';
        _scheduleOn2 = '--:--';
        _scheduleOff2 = '--:--';
        _scheduleOn3 = '--:--';
        _scheduleOff3 = '--:--';
        _lunchOn = '--:--';
        _lunchOff = '--:--';
        hasChanges = true;
      } else if (upperPayload.contains('SCH_CLEAR1')) {
        _scheduleOn1 = '--:--';
        _scheduleOff1 = '--:--';
        hasChanges = true;
      } else if (upperPayload.contains('SCH_CLEAR2')) {
        _scheduleOn2 = '--:--';
        _scheduleOff2 = '--:--';
        hasChanges = true;
      } else if (upperPayload == 'SCH_CLEAR' ||
          upperPayload.endsWith(':SCH_CLEAR')) {
        // "this one specific lunch clear"
        _lunchOn = '--:--';
        _lunchOff = '--:--';
        hasChanges = true;
      }

      // 3. Status & Power Matches
      final bool isTargetDeviceMessage = isStatusTopic ||
          (payload.contains(_deviceId) && _deviceId.isNotEmpty) ||
          payload.contains('Sustainabyte_testir');

      if (isTargetDeviceMessage) {
        _lastMessageReceivedTime = DateTime.now();
        if (upperPayload == 'ON_SUCCESS' ||
            upperPayload == 'STATUS_ON' ||
            upperPayload.contains('AC:ON')) {
          _isPowerCommandLock = false;
          _isPowerOn = true;
          hasChanges = true;
        } else if (upperPayload == 'OFF_SUCCESS' ||
            upperPayload == 'STATUS_OFF' ||
            upperPayload.contains('AC:OFF')) {
          _isPowerCommandLock = false;
          _isPowerOn = false;
          hasChanges = true;
        } else if (upperPayload.contains('OFFLINE') ||
            upperPayload.contains('INACTIVE')) {
          final bool wasOnline = _isOnline;
          _isOnline = false;
          if (wasOnline != _isOnline) {
            _inactiveStartTime = DateTime.now();
            hasChanges = true;
            debugPrint(
                '📡 [MQTT String] Status Updated: $_isOnline (Payload: $payload)');
          }
        } else if (upperPayload.contains('ONLINE') ||
            upperPayload.contains('ACTIVE')) {
          final bool wasOnline = _isOnline;
          _isOnline = true;
          if (wasOnline != _isOnline) {
            _inactiveStartTime = null;
            hasChanges = true;
            debugPrint(
                '📡 [MQTT String] Status Updated: $_isOnline (Payload: $payload)');
          }
        }
      }

      if (upperPayload.startsWith('TEMP:')) {
        final valStr = upperPayload.split(':').last.trim();
        final val = double.tryParse(valStr);
        if (val != null) {
          _actualTemperature = val;
          hasChanges = true;
        }
      } else if (upperPayload.startsWith('HUM:')) {
        final valStr = upperPayload.split(':').last.trim();
        final val = double.tryParse(valStr);
        if (val != null) {
          _humidity = val.toInt();
          hasChanges = true;
        }
      }
    }

    if (hasChanges) {
      // Throttle UI updates, disk I/O, and data processing to avoid lag
      final now = DateTime.now();
      if (now.difference(_lastSetStateTime) >
          const Duration(milliseconds: 200)) {
        _lastSetStateTime = now;
        _lastUpdateTime = now;

        // 1. Process logs and history only when UI updates
        _tempHistory.add(_ChartData(now, _actualTemperature));
        if (_tempHistory.length > 20) _tempHistory.removeAt(0);

        _recentLogs.insert(0, {
          'time': now.toString().split('.').first.split(' ').last,
          'temp': _actualTemperature.toStringAsFixed(1),
          'hum': _humidity,
          'ac': _isPowerOn ? 'ON' : 'OFF',
          'online': _isOnline,
        });
        if (_recentLogs.length > 5) _recentLogs.removeLast();

        // 2. Save to cache
        LocalCacheService.saveDeviceStatus(widget.systemShortId, {
          'temp': _actualTemperature,
          'hum': _humidity,
          'power': _isPowerOn,
          // 'online' status is no longer cached to ensure it always starts as inactive on page load
        });

        if (mounted) setState(() {});
      }
    }
  }

  String _extractTime(String payload) {
    if (payload.contains(":")) {
      final parts = payload.split(":");
      String potentialTime = "";
      if (parts.length >= 3) {
        potentialTime =
            '${parts[parts.length - 2].trim()}:${parts.last.trim()}';
      } else {
        potentialTime = parts.last.trim();
      }
      if (RegExp(r"^\d{1,2}:\d{2}$").hasMatch(potentialTime)) {
        return potentialTime;
      }
    }
    return "--:--";
  }

  void _updateInactiveTimeString() {
    if (_inactiveStartTime != null) {
      final duration = DateTime.now().difference(_inactiveStartTime!);
      final hours = duration.inHours;
      final minutes = duration.inMinutes.remainder(60);
      final seconds = duration.inSeconds.remainder(60);

      setState(() {
        if (hours > 0) {
          _inactiveTimeString = '${hours}h ${minutes}m ago';
        } else if (minutes > 0) {
          _inactiveTimeString = '${minutes}m ${seconds}s ago';
        } else {
          _inactiveTimeString = '${seconds}s ago';
        }
      });
    }
  }

  String _getDeviceTopic(String type) {
    // Dynamically construct topic based on the selected device ID (IMEI/ShortId)
    // Fallback to Sustainabyte_testir for compatibility with legacy hardware
    final String id = _deviceId.isEmpty ? 'Sustainabyte_testir' : _deviceId;
    return 'testir/Sustainabyte_testir/$type';
  }

  Future<void> _publishMqttCommand(String message,
      {String? topic, bool allowOffline = false}) async {
    if (!_isOnline && !allowOffline) {
      _showOfflineWarning();
      return;
    }
    final String targetTopic = topic ?? _getDeviceTopic('control');

    // Fast Path: Reuse existing persistent connection
    if (_persistentMqttClient != null &&
        _persistentMqttClient!.connectionStatus!.state ==
            MqttConnectionState.connected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(message);
      _persistentMqttClient!
          .publishMessage(targetTopic, MqttQos.atLeastOnce, builder.payload!);
      _handleOptimisticUpdate(message);
      return;
    }

    // Slow Path: Fallback to one-off connection
    final String broker = AppConfig.mqttBroker;
    final String username = AppConfig.mqttUsername;
    final String password = AppConfig.mqttPassword;

    final client = MqttServerClient(
      broker,
      'flutter_cmd_${DateTime.now().millisecondsSinceEpoch}',
    );
    client.port = 1883;
    client.logging(on: false);
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(
            'flutter_cmd_${DateTime.now().millisecondsSinceEpoch}')
        .authenticateAs(username, password)
        .startClean();

    try {
      await client.connect();
      if (client.connectionStatus!.state == MqttConnectionState.connected) {
        final builder = MqttClientPayloadBuilder();
        builder.addString(message);
        client.publishMessage(
            targetTopic, MqttQos.atLeastOnce, builder.payload!);
        _handleOptimisticUpdate(message);
        await Future.delayed(const Duration(milliseconds: 500));
        client.disconnect();
      }
    } catch (e) {
      debugPrint('❌ [MQTT CMD] Error: $e');
    }
  }

  void _handleOptimisticUpdate(String message) {
    if (!mounted) return;
    setState(() {
      _lastManualCommandTime = DateTime.now();
      _isPowerCommandLock = true;
      if (message == 'ON') {
        _isPowerOn = true;
      } else if (message == 'OFF') {
        _isPowerOn = false;
      }
    });
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && _isPowerCommandLock) {
        setState(() => _isPowerCommandLock = false);
      }
    });
  }

  Future<String> _fetchEquipmentImei(String equipmentId) async {
    final companyId = await AuthService.getCompanyId() ?? '';
    final siteId = await AuthService.getSiteId() ?? '';
    final bucket = await AuthService.getBucket() ?? '';
    final token = await AuthService.getCookieHeader() ?? '';

    final url = '${AppConfig.provisionBaseUrl}/equipments/$equipmentId'
        '?companyId=$companyId&siteId=$siteId&bucket=$bucket';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Assuming IMEI is in data['data']['imei'] or similar field
        // Looking at the user's provided JSON, I don't see imei, but they said "take from the imei is an device_id"
        // Let's check the first equipment structure again
        final equipData = data['data'];
        if (equipData is List && equipData.isNotEmpty) {
          final first = equipData[0];
          return (first['imei'] ??
                      first['Imei'] ??
                      first['shortId'] ??
                      first['ShortId'] ??
                      '')
                  ?.toString() ??
              '';
        } else if (equipData is Map) {
          return (equipData['imei'] ??
                      equipData['Imei'] ??
                      equipData['shortId'] ??
                      equipData['ShortId'] ??
                      '')
                  ?.toString() ??
              '';
        }
      }
    } catch (e) {
      debugPrint('Error fetching IMEI: $e');
    }
    return '';
  }

  Future<void> _connectToStream(String imei) async {
    final companyId = await AuthService.getCompanyId() ?? '';
    final token = await AuthService.getCookieHeader() ?? '';

    // The error "not upgraded to websocket" suggests this is an HTTP Stream (SSE/NDJSON)
    // rather than a true WebSocket. We will use http.Client to listen to the stream.
    final url =
        '${AppConfig.provisionBaseUrl}/mqtt/stream?companyid=$companyId&deviceId=$imei';

    debugPrint('ðŸŒ  [HTTP Stream] Connecting to: $url');

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      request.headers['Authorization'] = 'Bearer $token';
      request.headers['Accept'] = 'text/event-stream'; // Standard for SSE

      final response = await client.send(request);

      if (response.statusCode == 200) {
        if (mounted) {
          setState(() => _isTelemetryLoading = false);
        }
        _subscription = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter()) // Handle line-by-line JSON
            .listen(
          (line) {
            if (line.trim().isEmpty) return;
            debugPrint('ðŸ“¥ [HTTP Stream] Data: $line');
            _parseAndMapData(line);
          },
          onError: (error) {
            debugPrint('â Œ [HTTP Stream] Error: $error');
          },
          onDone: () {
            debugPrint('ðŸ”Œ [HTTP Stream] Stream closed');
            client.close();
          },
        );

        // Background polling removed as per user request to stop continuous MQTT traffic.
        _pollTimer?.cancel();
      } else {
        debugPrint(
            'â Œ [HTTP Stream] Connection failed: ${response.statusCode}');
        if (mounted) {
          setState(() => _isTelemetryLoading = false);
        }
      }
    } catch (e) {
      debugPrint('â Œ [HTTP Stream] Connection Exception: $e');
      if (mounted) {
        setState(() => _isTelemetryLoading = false);
      }
    }
  }

  void _parseAndMapData(String line) {
    try {
      // Remove "data: " prefix if it's SSE format
      String jsonStr = line;
      if (line.startsWith('data: ')) {
        jsonStr = line.substring(6).trim();
      } else {
        jsonStr = line.trim();
      }

      if (jsonStr.isEmpty) return;

      // 1. Decode JSON
      final data = jsonDecode(jsonStr);
      Map<String, dynamic>? payload;

      if (data['data'] != null && data['data']['data'] != null) {
        payload = Map<String, dynamic>.from(data['data']['data']);
      } else if (data['data'] != null) {
        payload = Map<String, dynamic>.from(data['data']);
      }

      if (payload != null && mounted) {
        bool hasChanges = false;

        // Temperature and Humidity parsing removed from stream as per request.
        // They are now handled via persistent MQTT subscription in _handleMqttTelemetry.

        bool newPowerOn = _isPowerOn;
        if ((payload['ac'] != null || payload['ACStatus'] != null) &&
            !_isPowerCommandLock) {
          newPowerOn =
              (payload['ac'] ?? payload['ACStatus']).toString() == 'ON';
          if (newPowerOn != _isPowerOn) hasChanges = true;
        }

        // Connection status updates from HTTP Stream disabled.
        // All status logic is now centralized in _handleMqttTelemetry for consistency.
        bool newOnline = _isOnline;

        bool newAuto = _isAuto;
        if (payload['auto'] != null || payload['isAuto'] != null) {
          newAuto = (payload['auto'] ?? payload['isAuto']) == true;
          if (newAuto != _isAuto) hasChanges = true;
        }

        if (mounted) {
          setState(() {
            _isTelemetryLoading = false;

            if (hasChanges) {
              if (!_isPowerCommandLock) _isPowerOn = newPowerOn;
              _isOnline = newOnline;
              _isAuto = newAuto;
              _lastUpdateTime = DateTime.now();

              _recentLogs.insert(0, {
                'time': payload!['time'] ??
                    DateTime.now().toString().split('.').first.split(' ').last,
                'temp': _actualTemperature.toStringAsFixed(1),
                'hum': _humidity,
                'ac': _isPowerOn ? 'ON' : 'OFF',
              });
              if (_recentLogs.length > 5) _recentLogs.removeLast();
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error parsing Stream data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Listener(
      onPointerDown: (_) => _messenger?.hideCurrentSnackBar(),
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF1B172E) : const Color(0xFFF8FAFC),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios,
              color: isDark ? Colors.white : const Color(0xFF1B172E),
              size: 20,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _selectedEquipmentName,
                style: GoogleFonts.poppins(
                  color: isDark ? Colors.white : const Color(0xFF1B172E),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ID: ${_deviceId.isEmpty ? 'testir' : _deviceId}',
                    style: GoogleFonts.poppins(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (!_isOnline && _inactiveTimeString != 'N/A') ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'OFFLINE • $_inactiveTimeString',
                        style: GoogleFonts.poppins(
                          color: Colors.redAccent,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          actions: [
            if (_pulseController != null)
              FadeTransition(
                opacity: Tween(begin: 0.3, end: 1.0).animate(
                  CurvedAnimation(
                    parent: _pulseController!,
                    curve: Curves.easeInOut,
                  ),
                ),
                child: IconButton(
                  onPressed: () => _showDataInsights(isDark),
                  icon: Icon(
                    Icons.analytics_outlined,
                    color: isDark
                        ? const Color(0xFF6CC042)
                        : const Color(0xFF10B981),
                    size: 24,
                  ),
                  tooltip: 'Trends',
                ),
              )
            else
              const SizedBox(width: 48),
            const SizedBox(width: 8),
          ],
          centerTitle: true,
        ),
        body: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _buildEquipmentTabs(isDark, colorScheme),
                  const SizedBox(height: 32), // Space between tabs and gauge
                  RepaintBoundary(
                    child: _InteractiveThermostatGauge(
                      setTemp: _setTemperature,
                      actualTemp: _actualTemperature,
                      isDark: isDark,
                      isOnline: _isOnline,
                      colorScheme: colorScheme,
                      onTempChanged: (double val) {
                        setState(() => _setTemperature = val);
                        _publishMqttCommand('TEMP_CN:${val.toInt()}');
                      },
                      onClearTemp: () {
                        setState(() => _setTemperature = 24.0);
                        _publishMqttCommand('TEMP_CN:24');
                      },
                      onDisabledInteraction: _showOfflineWarning,
                    ),
                  ),
                  const SizedBox(height: 32), // Space below gauge
                  _buildDetailStats(isDark, colorScheme),
                  const SizedBox(height: 40),
                ],
              ),
            ),
            if (_isLoadingEquipments || _isTelemetryLoading)
              Positioned.fill(child: _buildFullPageSkeleton(isDark)),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }

  Widget _buildFullPageSkeleton(bool isDark) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: isDark ? const Color(0xFF1B172E) : Colors.white,
      child: SingleChildScrollView(
        physics:
            const NeverScrollableScrollPhysics(), // Prevent scrolling while loading
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Tabs Skeleton
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: List.generate(
                  3,
                  (i) => Container(
                    width: 80,
                    height: 36,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 48),
            // Gauge Skeleton
            Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 50),
            // Stats Skeleton
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Schedule Skeleton
                  Container(
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Lunch Skeleton
                  Container(
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  const SizedBox(height: 100), // Ensure bottom is covered
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendsSection(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Temperature Trends',
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          RepaintBoundary(
            child: SizedBox(
              height: 150,
              child: SfCartesianChart(
                margin: EdgeInsets.zero,
                primaryXAxis: DateTimeAxis(isVisible: false),
                primaryYAxis: NumericAxis(
                  isVisible: false,
                  minimum: 20,
                  maximum: 40,
                ),
                plotAreaBorderWidth: 0,
                series: <CartesianSeries<_ChartData, DateTime>>[
                  SplineAreaSeries<_ChartData, DateTime>(
                    dataSource: _tempHistory,
                    xValueMapper: (_ChartData data, _) => data.time,
                    yValueMapper: (_ChartData data, _) => data.temp,
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF6CC042).withOpacity(0.3),
                        const Color(0xFF6CC042).withOpacity(0.0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderColor: const Color(0xFF6CC042),
                    borderWidth: 2,
                    animationDuration: 0,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsSection(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Activity Log',
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white70 : Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                children: [
                  _tableHeader('TIME', isDark),
                  _tableHeader('TEMP', isDark),
                  _tableHeader('AC', isDark),
                ],
              ),
              ..._recentLogs.map(
                (log) => TableRow(
                  children: [
                    _tableCell(log['time'].toString().split(' ').last, isDark),
                    _tableCell('${log['temp']}°', isDark),
                    _tableCell(
                      log['ac']?.toString() ?? 'N/A',
                      isDark,
                      color: log['ac'] == 'ON'
                          ? const Color(0xFF6CC042)
                          : Colors.redAccent,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(String text, bool isDark) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: GoogleFonts.poppins(
            color: Colors.white24,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  Widget _tableCell(String text, bool isDark, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: GoogleFonts.poppins(
            color: color ?? (isDark ? Colors.white70 : Colors.black87),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      );

  void _showDataInsights(bool isDark) async {
    final companyId = await AuthService.getCompanyId() ?? '';
    final siteId = await AuthService.getSiteId() ?? '';
    final bucket = await AuthService.getBucket() ?? '';

    // Find the current equipment data for debugging
    final selectedData = _equipmentsData.firstWhere(
      (e) => e['equipmentId']?.toString() == _selectedEquipmentId,
      orElse: () => {},
    );

    debugPrint('ðŸ”  DEBUGGING TRENDS NAVIGATION:');
    debugPrint('ðŸ†” Selected Equipment ID: $_selectedEquipmentId');
    debugPrint('ðŸ ·ï¸  Selected Short ID: $_selectedEquipmentShortId');
    debugPrint('ðŸ“± Device ID (IMEI): $_deviceId');
    debugPrint('ðŸ“¦ Full Equipment Data: $selectedData');

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _TrendsPage(
          isDark: isDark,
          systemId: widget.systemId,
          systemName: widget.deviceName, // This holds the system name
          systemShortId: widget.systemShortId,
          equipmentId: _selectedEquipmentId,
          equipmentName: _selectedEquipmentName,
          equipmentTypeId: _selectedEquipmentTypeId,
          equipmentShortId: _selectedEquipmentShortId,
          companyId: companyId,
          siteId: siteId,
          bucket: bucket,
        ),
      ),
    );
  }

  Widget _buildEquipmentTabs(bool isDark, ColorScheme colorScheme) {
    if (_equipments.isEmpty) return const SizedBox();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // First two equipments
          ..._equipmentsData.take(2).map(
                (e) => _buildTab(
                  e['name']?.toString() ?? 'N/A',
                  e['equipmentId']?.toString() == _selectedEquipmentId,
                  isDark,
                  colorScheme,
                  e['equipmentId']?.toString() ?? '',
                  e['equipmentTypeId']?.toString() ?? '',
                  e['shortId']?.toString() ?? '',
                ),
              ),

          // More button
          GestureDetector(
            onTap: () => _showAllEquipmentsPopup(isDark, colorScheme),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  Text(
                    'More',
                    style: GoogleFonts.poppins(
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.double_arrow_rounded,
                    color: const Color(0xFF6CC042),
                    size: 14,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionPill({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(
    String label,
    bool isActive,
    bool isDark,
    ColorScheme colorScheme,
    String equipmentId,
    String equipmentTypeId,
    String shortId,
  ) {
    return GestureDetector(
      onTap: () =>
          _onEquipmentSelected(equipmentId, label, equipmentTypeId, shortId),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: isActive
              ? LinearGradient(
                  colors: [
                    const Color(
                      0xFF8B5CF6,
                    ).withOpacity(0.2), // Changed from blue to purple
                    const Color(0xFF8B5CF6).withOpacity(0.05),
                  ],
                )
              : null,
          color: !isActive
              ? (isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.grey.withOpacity(0.1))
              : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? const Color(0xFF8B5CF6).withOpacity(0.5)
                : Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            color: isActive
                ? const Color(0xFF8B5CF6)
                : (isDark ? Colors.white70 : Colors.black54),
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _showAllEquipmentsPopup(bool isDark, ColorScheme colorScheme) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1B172E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Select Equipment',
              style: GoogleFonts.poppins(
                color: isDark ? Colors.white : const Color(0xFF1B172E),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF6CC042).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Total: ${_equipmentsData.length}',
                style: GoogleFonts.poppins(
                  color: const Color(0xFF6CC042),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _equipmentsData.length,
            itemBuilder: (context, index) {
              final eData = _equipmentsData[index];
              final String e = eData['name']?.toString() ?? 'Unknown';
              final String id = eData['equipmentId']?.toString() ?? '';
              final isSelected = id == _selectedEquipmentId;
              return ListTile(
                onTap: () {
                  _onEquipmentSelected(
                    id,
                    e,
                    eData['equipmentTypeId']?.toString() ?? '',
                    (eData['shortId'] ?? eData['equipmentShortId'])
                            ?.toString() ??
                        '',
                  );
                  Navigator.pop(context);
                },
                leading: Icon(
                  Icons.ac_unit,
                  color: isSelected
                      ? const Color(0xFF6CC042)
                      : (isDark ? Colors.white24 : Colors.black26),
                ),
                title: Text(
                  e,
                  style: GoogleFonts.poppins(
                    color: isSelected
                        ? (isDark ? Colors.white : const Color(0xFF1B172E))
                        : (isDark ? Colors.white60 : Colors.black54),
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check_circle, color: Color(0xFF6CC042))
                    : null,
              );
            },
          ),
        ),
      ),
    );
  }

  void _showActualTempPopup(double temp) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.3),
      isScrollControlled: true,
      builder: (context) => Container(
        height: 280,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF1B172E),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
          border: Border.all(
            color: const Color(0xFF6CC042).withOpacity(0.3),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6CC042).withOpacity(0.1),
              blurRadius: 30,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Icon(
              Icons.cloud_queue_rounded,
              color: const Color(0xFF6CC042),
              size: 54,
            ),
            const SizedBox(height: 16),
            Text(
              'CURRENT TEMPERATURE',
              style: GoogleFonts.poppins(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${temp.toStringAsFixed(1)}°C',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 56,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF6CC042).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.water_drop_rounded,
                    color: Color(0xFF6CC042),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'HUMIDITY: $_humidity%',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF6CC042),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickControls(bool isDark, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _controlButton(
            icon: Icons.power_settings_new_rounded,
            label: 'POWER',
            isActive: _isPowerOn,
            activeColor: const Color(0xFFEF4444),
            onTap: () {
              _togglePower(!_isPowerOn);
            },
            isDark: isDark,
          ),
          _controlButton(
            icon: Icons.ac_unit_rounded,
            label: 'MODE',
            isActive: true,
            activeColor: const Color(0xFF3B82F6),
            onTap: () {},
            isDark: isDark,
          ),
          _controlButton(
            icon: Icons.air_rounded,
            label: 'FAN',
            isActive: true,
            activeColor: const Color(0xFF10B981),
            onTap: () {},
            isDark: isDark,
          ),
          _controlButton(
            icon: Icons.more_horiz_rounded,
            label: 'MORE',
            isActive: false,
            activeColor: Colors.white,
            onTap: () {},
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isActive
                  ? activeColor.withOpacity(0.15)
                  : (isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.black.withOpacity(0.05)),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isActive
                    ? activeColor.withOpacity(0.3)
                    : Colors.white.withOpacity(0.05),
                width: 1.5,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: activeColor.withOpacity(0.2),
                        blurRadius: 15,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              color: isActive
                  ? activeColor
                  : (isDark ? Colors.white38 : Colors.black38),
              size: 26,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white24 : Colors.black26,
              fontSize: 8,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailStats(bool isDark, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // 1. Primary Controls (Power and Schedule) - Immediately below Circle Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // WIFI Toggle
              _buildActionButton(
                icon: _isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                label: 'WIFI',
                isActive: true,
                activeColor: _isOnline
                    ? const Color(0xFF6CC042)
                    : const Color(0xFFEF4444),
                isDark: isDark,
                onTap: () {
                  if (!_isOnline) {
                    debugPrint('🔄 [MQTT] User requested WiFi re-sync');
                    _setupPersistentMqtt();
                    _messenger?.showSnackBar(
                      const SnackBar(
                        content: Text('Re-syncing connection status...'),
                        duration: Duration(seconds: 3),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
              const SizedBox(width: 20),
              // ON Button
              _buildActionButton(
                icon: Icons.power_settings_new_rounded,
                label: 'ON',
                isActive: _isPowerOn,
                activeColor: const Color(0xFF6CC042),
                isDark: isDark,
                onTap: () {
                  _publishMqttCommand('ON');
                },
              ),
              const SizedBox(width: 20),
              // OFF Button
              _buildActionButton(
                icon: Icons.power_off_rounded,
                label: 'OFF',
                isActive: !_isPowerOn,
                activeColor: const Color(0xFFEF4444),
                isDark: isDark,
                onTap: () {
                  _publishMqttCommand('OFF');
                },
              ),
              const SizedBox(width: 20),
              // Schedule Control
              _buildActionButton(
                icon: Icons.calendar_month_rounded,
                label: 'SCHEDULE',
                isActive: true,
                activeColor: const Color(0xFF8B5CF6),
                isDark: isDark,
                onTap: () {
                  if (_isOnline) {
                    _showSchedulePicker(isDark);
                  } else {
                    _showOfflineWarning();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 32),

          // 2. Status and Humidity (Responsive Row/Column)
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 340) {
                return Column(
                  children: [
                    _buildStatusCard(isDark),
                    if (_isOnline) const SizedBox(height: 12),
                    if (_isOnline) _buildHumidityCard(isDark),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: _buildStatusCard(isDark)),
                  if (_isOnline) const SizedBox(width: 12),
                  if (_isOnline) Expanded(child: _buildHumidityCard(isDark)),
                ],
              );
            },
          ),
          const SizedBox(height: 24),

          // 3. Schedule Visualization Sections
          if (_isOnline) ...[
            RepaintBoundary(child: _buildScheduleSection(isDark)),
            const SizedBox(height: 12),
            RepaintBoundary(child: _buildLunchSection(isDark)),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final borderColor = isActive
        ? activeColor.withOpacity(0.4)
        : (isDark ? Colors.white12 : Colors.black12);
    final iconColor = isActive
        ? (isDark ? Colors.white : activeColor)
        : (isDark ? Colors.white38 : Colors.black38);

    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isActive
                  ? activeColor.withOpacity(isDark ? 0.15 : 0.1)
                  : (isDark ? Colors.white.withOpacity(0.03) : Colors.white),
              shape: BoxShape.circle,
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: activeColor.withOpacity(0.25),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [
                      if (!isDark)
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                    ],
              border: Border.all(
                color: borderColor,
                width: 1.5,
              ),
            ),
            child: Center(
              child: Icon(
                icon,
                color: iconColor,
                size: 26,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.poppins(
            color: isActive
                ? (isDark ? Colors.white70 : activeColor)
                : (isDark ? Colors.white24 : Colors.black26),
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF26213A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: const Color(0xFF0F172A).withOpacity(0.05),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AC STATUS',
                style: GoogleFonts.poppins(
                  color: isDark ? Colors.white24 : Colors.black45,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'ID: ${_deviceId.isEmpty ? 'testir' : _deviceId}',
                  style: GoogleFonts.poppins(
                    color: isDark ? Colors.white10 : Colors.black12,
                    fontSize: 7,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              _isOnline
                  ? Text(
                      'ONLINE',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF6CC042),
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : Text(
                      'OFFLINE',
                      style: GoogleFonts.poppins(
                        color: Colors.redAccent,
                        fontSize: 7,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                _isOnline ? Icons.ac_unit_rounded : Icons.power_off_rounded,
                color: _isOnline ? const Color(0xFF6CC042) : Colors.white24,
                size: 18,
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isOnline ? 'ACTIVE' : 'INACTIVE',
                    style: GoogleFonts.poppins(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (!_isOnline && _inactiveTimeString != 'N/A')
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        _inactiveTimeString,
                        style: GoogleFonts.poppins(
                          color: isDark ? Colors.white54 : Colors.black54,
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHumidityCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF26213A) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: const Color(0xFF0F172A).withOpacity(0.05),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HUMIDITY',
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white24 : Colors.black45,
              fontSize: 8,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: _humidity / 100,
                      strokeWidth: 3,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFFF59E0B),
                      ),
                    ),
                    const Icon(
                      Icons.water_drop_rounded,
                      size: 10,
                      color: Color(0xFFF59E0B),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$_humidity%',
                style: GoogleFonts.poppins(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleSection(bool isDark) {
    return GestureDetector(
      onTap: () => _showSchedulePicker(isDark),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF26213A) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: const Color(0xFF0F172A).withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.schedule_rounded,
                      color: Color(0xFF8B5CF6), size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  'Daily Schedule',
                  style: GoogleFonts.outfit(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (_isAuto) _buildAutoBadge(),
              ],
            ),
            const SizedBox(height: 20),
            _buildScheduleItem('Schedule 1', _scheduleOn1, _scheduleOff1,
                const Color(0xFF6CC042), isDark),
            const SizedBox(height: 12),
            _buildScheduleItem('Schedule 2', _scheduleOn2, _scheduleOff2,
                const Color(0xFF3B82F6), isDark),
            const SizedBox(height: 12),
            _buildScheduleItem('Schedule 3', _scheduleOn3, _scheduleOff3,
                const Color(0xFFF59E0B), isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleItem(
      String label, String on, String off, Color color, bool isDark) {
    final bool isActive = on != '--:--' && off != '--:--';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.03)
            : Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive ? color.withOpacity(0.2) : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: GoogleFonts.outfit(
                  color: isActive
                      ? color
                      : (isDark ? Colors.white24 : Colors.black26),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isActive ? 'Running' : 'Inactive',
                style: GoogleFonts.outfit(
                  color: isActive
                      ? (isDark ? Colors.white38 : Colors.black38)
                      : (isDark
                          ? Colors.white.withOpacity(0.1)
                          : Colors.black12),
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          const Spacer(),
          _timeChip('ON', on, isActive ? color : null, isDark),
          const SizedBox(width: 8),
          _timeChip('OFF', off, isActive ? Colors.redAccent : null, isDark),
        ],
      ),
    );
  }

  Widget _timeChip(String label, String time, Color? activeColor, bool isDark) {
    final isActive = activeColor != null;
    final bool isActuallySet =
        time != '--:--' && time.toUpperCase() != 'DISABLED';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isActive
            ? activeColor.withOpacity(0.12)
            : (isDark
                ? Colors.white.withOpacity(0.02)
                : Colors.grey.withOpacity(0.03)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? activeColor.withOpacity(0.3)
              : (isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.black.withOpacity(0.03)),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(
              color: isActive
                  ? activeColor
                  : (isDark ? Colors.white10 : Colors.black12),
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          if (!isActuallySet)
            Icon(
              Icons.timer_off_outlined,
              size: 12,
              color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.black.withOpacity(0.05),
            )
          else
            const SizedBox(height: 12), // Spacer to maintain height
          const SizedBox(height: 2),
          ImageFiltered(
            imageFilter: !isActuallySet
                ? ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5)
                : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
            child: Text(
              isActuallySet ? time : '-- : --',
              style: GoogleFonts.outfit(
                color: isActive
                    ? (isDark ? Colors.white : Colors.black87)
                    : (isDark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.black.withOpacity(0.1)),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLunchSection(bool isDark) {
    final bool isActive = _lunchOn != '--:--' && _lunchOff != '--:--';
    return GestureDetector(
      onTap: () => _showSchedulePicker(isDark),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF26213A) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.05)
                : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: const Color(0xFF0F172A).withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.restaurant_rounded,
                      color: Colors.orange, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  'Lunch Schedule',
                  style: GoogleFonts.outfit(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (isActive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '1H DURATION',
                      style: GoogleFonts.outfit(
                        color: Colors.orange,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.03)
                    : Colors.grey.withOpacity(0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive
                      ? Colors.orange.withOpacity(0.2)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _lunchTimeItem('BREAK START', _lunchOn, isDark),
                  Container(
                      width: 1,
                      height: 30,
                      color: isDark
                          ? Colors.white.withAlpha(26)
                          : Colors.black.withAlpha(26)),
                  _lunchTimeItem('BREAK END', _lunchOff, isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lunchTimeItem(String label, String time, bool isDark) {
    final bool isSet = time != '--:--';
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(
            color: isDark ? Colors.white24 : Colors.black26,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          time,
          style: GoogleFonts.outfit(
            color: isSet
                ? (isDark ? Colors.white : Colors.black87)
                : (isDark ? Colors.white12 : Colors.black12),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildAutoBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF6CC042).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'AUTO',
        style: GoogleFonts.outfit(
          color: const Color(0xFF6CC042),
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _showSchedulePicker(bool isDark) {
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: _ScheduleControlDialog(
          isDark: isDark,
          schedules: [
            {'on': _scheduleOn1, 'off': _scheduleOff1},
            {'on': _scheduleOn2, 'off': _scheduleOff2},
            {'on': _scheduleOn3, 'off': _scheduleOff3},
          ],
          lunch: {'on': _lunchOn, 'off': _lunchOff},
          onCommand: (type, index, time) =>
              _publishMqttSchedule(type, index, time),
        ),
      ),
    );
  }

  Future<void> _publishMqttSchedule(
      String type, int index, String? time) async {
    if (mounted) {
      setState(() {
        if (type == 'SCH_ON') {
          if (index == 1) _scheduleOn1 = time!;
          if (index == 2) _scheduleOn2 = time!;
          if (index == 3) _scheduleOn3 = time!;
        }
        if (type == 'SCH_OFF') {
          if (index == 1) _scheduleOff1 = time!;
          if (index == 2) _scheduleOff2 = time!;
          if (index == 3) _scheduleOff3 = time!;
        }
        if (type == 'LUNCH_ON') _lunchOn = time!;
        if (type == 'LUNCH_OFF') _lunchOff = time!;
        if (type == 'SCH_CLEAR') {
          if (index == 1) {
            _scheduleOn1 = '--:--';
            _scheduleOff1 = '--:--';
          }
          if (index == 2) {
            _scheduleOn2 = '--:--';
            _scheduleOff2 = '--:--';
          }
          if (index == 3) {
            _scheduleOn3 = '--:--';
            _scheduleOff3 = '--:--';
          }
          if (index == 4) {
            _lunchOn = '--:--';
            _lunchOff = '--:--';
          }
        }
        if (type == 'SCH_CLEAR_ALL') {
          _scheduleOn1 = '--:--';
          _scheduleOff1 = '--:--';
          _scheduleOn2 = '--:--';
          _scheduleOff2 = '--:--';
          _scheduleOn3 = '--:--';
          _scheduleOff3 = '--:--';
          _lunchOn = '--:--';
          _lunchOff = '--:--';
        }
      });
    }

    String payloadStr = '';
    if (type == 'SCH_CLEAR_ALL') {
      payloadStr = 'SCH_CLEAR';
    } else if (type == 'SCH_CLEAR') {
      payloadStr = index <= 3 ? 'SCH_CLEAR$index' : 'SCH_CLEAR_LUNCH';
    } else {
      payloadStr = '$type${index <= 3 ? index : ''}:$time';
    }

    // Publish to daily schedule topic using unified topic generator
    _publishMqttCommand(payloadStr,
        topic: _getDeviceTopic('schedule'), allowOffline: true);
  }

  void _showOfflineWarning() {
    if (!mounted) return;

    // Only show if this route is currently active to prevent it showing "outside"
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    _messenger?.hideCurrentSnackBar();
    _messenger?.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.wifi_off_rounded,
                  color: Color(0xFFEF4444), size: 18),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Connection Lost',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      )),
                  Text('Device is currently unreachable',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.white60,
                        fontWeight: FontWeight.w400,
                      )),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1B172E),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        elevation: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
              color: const Color(0xFFEF4444).withOpacity(0.2), width: 1.5),
        ),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 30),
        action: SnackBarAction(
          label: 'RE-SYNC',
          textColor: const Color(0xFFEF4444),
          onPressed: () {
            _setupPersistentMqtt();
          },
        ),
      ),
    );
  }
}

class _ChartData {
  _ChartData(this.time, this.temp);
  final DateTime time;
  final double temp;
}

// Background parser for chart data to prevent UI thread blocking
List<_ChartData> _parseChartDataInBackground(String responseBody) {
  try {
    final data = jsonDecode(responseBody);
    final List<dynamic> params = data['data']?['parameters'] ?? [];
    List<dynamic> points = [];
    if (params.isNotEmpty) {
      points = params[0]['values'] ?? [];
    }

    int step = 1;
    if (points.length > 150) {
      step = points.length ~/ 150;
    }

    final List<_ChartData> result = [];
    for (int i = 0; i < points.length; i += step) {
      final p = points[i];
      final timeStr = p['time']?.toString() ?? DateTime.now().toString();
      final val = double.tryParse(p['value']?.toString() ?? '0.0') ?? 0.0;
      result.add(_ChartData(DateTime.parse(timeStr).toLocal(), val));
    }
    return result;
  } catch (e) {
    return [];
  }
}

class _TrendsPage extends StatefulWidget {
  final bool isDark;
  final String systemId;
  final String systemName;
  final String systemShortId;
  final String equipmentId;
  final String equipmentName;
  final String equipmentTypeId;
  final String equipmentShortId;
  final String companyId;
  final String siteId;
  final String bucket;

  const _TrendsPage({
    required this.isDark,
    required this.systemId,
    required this.systemName,
    required this.systemShortId,
    required this.equipmentId,
    required this.equipmentName,
    required this.equipmentTypeId,
    required this.equipmentShortId,
    required this.companyId,
    required this.siteId,
    required this.bucket,
  });

  @override
  State<_TrendsPage> createState() => _TrendsPageState();
}

class _TrendsPageState extends State<_TrendsPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  List<dynamic> _parameters = [];
  String? _selectedParamId;
  List<_ChartData> _chartData = [];
  bool _isLoading = true;
  bool _isChartLoading = false;
  DateTimeRange _dateRange = DateTimeRange(
    start: DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    ),
    end: DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    ),
  );

  @override
  void initState() {
    super.initState();
    debugPrint(
      'ðŸ“Š TRENDS OPENED WITH: ID=${widget.equipmentId}, ShortId=${widget.equipmentShortId}, TypeId=${widget.equipmentTypeId}',
    );
    _fetchParameters();
  }

  Future<void> _fetchParameters() async {
    final token = await AuthService.getCookieHeader() ?? '';
    final url =
        '${AppConfig.provisionBaseUrl}/systems/parameters/${widget.equipmentTypeId}'
        '?companyId=${widget.companyId}&siteId=${widget.siteId}&bucket=${widget.bucket}';

    debugPrint('ðŸ“Š FETCH PARAMETERS URL: $url');
    debugPrint('ðŸ”‘ TOKEN STATUS: ${token.isNotEmpty ? "PRESET" : "MISSING"}');

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );
      debugPrint('ðŸ“¥ RESPONSE STATUS: ${response.statusCode}');
      debugPrint('ðŸ“¦ RESPONSE BODY: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _parameters = data['data'] ?? [];
          if (_parameters.isNotEmpty) {
            // Smart auto-select: Try to find a temperature or status parameter first
            final smartIndex = _parameters.indexWhere((p) {
              final name = p['name']?.toString().toLowerCase() ?? '';
              return name.contains('temp') ||
                  name.contains('status') ||
                  name.contains('on/off');
            });
            _selectedParamId = _parameters[smartIndex != -1 ? smartIndex : 0]
                    ['shortId']
                ?.toString();
            _fetchChartData();
          }
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('âŒ Error fetching parameters: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchChartData() async {
    if (_selectedParamId == null) return;

    setState(() => _isChartLoading = true);
    final token = await AuthService.getCookieHeader() ?? '';

    final startTime = DateTime(
      _dateRange.start.year,
      _dateRange.start.month,
      _dateRange.start.day,
      0,
      0,
      0,
    ).toUtc().toIso8601String();
    final endTime = DateTime(
      _dateRange.end.year,
      _dateRange.end.month,
      _dateRange.end.day,
      23,
      59,
      59,
    ).toUtc().toIso8601String();

    final url = '${AppConfig.provisionBaseUrl}/parameters/chart-data'
        '?startTime=$startTime&endTime=$endTime'
        '&parameterShortIds=$_selectedParamId'
        '&systemId=${widget.systemId}'
        '&equipmentShortId=${widget.equipmentShortId}'
        '&bucket=${widget.bucket}&companyId=${widget.companyId}&siteId=${widget.siteId}';

    debugPrint('ðŸ“ˆ FETCH CHART URL: $url');

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );
      debugPrint('ðŸ“Š CHART STATUS: ${response.statusCode}');

      if (response.statusCode == 200) {
        final points = _parseChartDataInBackground(response.body);

        if (mounted) {
          setState(() {
            _chartData = points;
            _isChartLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('âŒ Error fetching chart data: $e');
      if (mounted) setState(() => _isChartLoading = false);
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _dateRange,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: widget.isDark
              ? ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: Color(0xFF6CC042),
                    onPrimary: Colors.white,
                    surface: Color(0xFF1B172E),
                    onSurface: Colors.white,
                  ),
                )
              : ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: Color(0xFF6CC042),
                  ),
                ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _dateRange = picked);
      _fetchChartData();
    }
  }

  String _formatDateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    return DateFormat('MMM dd').format(date);
  }

  IconData _getPickerIcon() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final start = DateTime(
      _dateRange.start.year,
      _dateRange.start.month,
      _dateRange.start.day,
    );
    final end = DateTime(
      _dateRange.end.year,
      _dateRange.end.month,
      _dateRange.end.day,
    );

    if (start == end) {
      if (start == today) return Icons.today_rounded;
      if (start == yesterday) return Icons.history_rounded;
    }
    return Icons.calendar_today_rounded;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = widget.isDark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1B172E) : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: isDark ? Colors.white : Colors.black,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(
              'Analytics & Trends',
              style: GoogleFonts.poppins(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.systemName,
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF6CC042),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? Colors.white54 : Colors.black54,
                    size: 12,
                  ),
                ),
                Text(
                  widget.equipmentName,
                  style: GoogleFonts.poppins(
                    color: isDark ? Colors.white54 : Colors.black54,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? _buildFullPageTrendsSkeleton(isDark)
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.05)
                                : Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedParamId,
                              dropdownColor: isDark
                                  ? const Color(0xFF2D264D)
                                  : Colors.white,
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Color(0xFF6CC042),
                              ),
                              style: GoogleFonts.poppins(
                                color: isDark ? Colors.white : Colors.black,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              items: _parameters
                                  .map(
                                    (p) => DropdownMenuItem<String>(
                                      value: p['shortId']?.toString(),
                                      child: Text(
                                        p['name']?.toString() ?? 'Unknown',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedParamId = val);
                                  _fetchChartData();
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _selectDateRange,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6CC042).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF6CC042).withOpacity(0.3),
                            ),
                          ),
                          child: Icon(
                            _getPickerIcon(),
                            color: const Color(0xFF6CC042),
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Container(
                    height: 300,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.grey.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: _isChartLoading
                        ? _buildChartSkeleton(isDark)
                        : _chartData.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.query_stats_rounded,
                                      color: Colors.white.withOpacity(0.1),
                                      size: 48,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No Data Available',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white.withOpacity(0.2),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : SfCartesianChart(
                                margin: EdgeInsets.zero,
                                plotAreaBorderWidth: 0,
                                primaryXAxis: DateTimeAxis(
                                  dateFormat: DateFormat('h:mm a'),
                                  majorGridLines:
                                      const MajorGridLines(width: 0),
                                  axisLine: const AxisLine(width: 0),
                                  labelStyle: GoogleFonts.poppins(
                                    color: Colors.white24,
                                    fontSize: 9,
                                  ),
                                ),
                                primaryYAxis: NumericAxis(
                                  majorGridLines: MajorGridLines(
                                    width: 1,
                                    color: Colors.white.withOpacity(0.05),
                                    dashArray: const [5, 5],
                                  ),
                                  axisLine: const AxisLine(width: 0),
                                  labelStyle: GoogleFonts.poppins(
                                    color: Colors.white24,
                                    fontSize: 9,
                                  ),
                                ),
                                series: <CartesianSeries<_ChartData, DateTime>>[
                                  AreaSeries<_ChartData, DateTime>(
                                    dataSource: _chartData,
                                    xValueMapper: (_ChartData data, _) =>
                                        data.time,
                                    yValueMapper: (_ChartData data, _) =>
                                        data.temp,
                                    color: const Color(
                                      0xFFD4145A,
                                    ), // Pink/Magenta from image
                                    borderColor: const Color(0xFFFF2D55),
                                    borderWidth: 2,
                                    gradient: LinearGradient(
                                      colors: [
                                        const Color(0xFFD4145A)
                                            .withOpacity(0.4),
                                        const Color(0xFFD4145A)
                                            .withOpacity(0.0),
                                      ],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                    ),
                                    animationDuration: 0,
                                  ),
                                ],
                                trackballBehavior: TrackballBehavior(
                                  enable: true,
                                  activationMode: ActivationMode.singleTap,
                                  tooltipSettings: InteractiveTooltip(
                                    enable: true,
                                    format: 'point.x : point.y',
                                    color: const Color(0xFFD4145A),
                                    textStyle: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                  ),
                  const SizedBox(height: 24),
                  TrendsTable(
                    isDark: isDark,
                    systemId: widget.systemId,
                    systemShortId: widget.systemShortId,
                    equipmentShortId: widget.equipmentShortId,
                    companyId: widget.companyId,
                    siteId: widget.siteId,
                    bucket: widget.bucket,
                    dateRange: _dateRange,
                    parameters: _parameters,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _infoCard(String label, String val, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.03)
              : Colors.black.withOpacity(0.03),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                color: Colors.white24,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              val,
              style: GoogleFonts.poppins(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullPageTrendsSkeleton(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          // Dropdown Row Skeleton
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(isDark ? 0.05 : 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(isDark ? 0.05 : 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Chart Box Skeleton
          Container(
            height: 300,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(isDark ? 0.05 : 0.1),
              borderRadius: BorderRadius.circular(28),
            ),
            child: _buildChartSkeleton(isDark),
          ),
          const SizedBox(height: 24),
          // Info Cards Row Skeleton
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(isDark ? 0.03 : 0.06),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(isDark ? 0.03 : 0.06),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartSkeleton(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(isDark ? 0.05 : 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              5,
              (index) => Container(
                width: 40,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(isDark ? 0.05 : 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceControlPage extends StatefulWidget {
  final String equipmentName;
  final double initialTemp;
  final double actualTemp;
  final bool isDark;
  final bool isOnline;

  const _DeviceControlPage({
    required this.equipmentName,
    required this.initialTemp,
    required this.actualTemp,
    required this.isDark,
    required this.isOnline,
  });

  @override
  State<_DeviceControlPage> createState() => _DeviceControlPageState();
}

class _DeviceControlPageState extends State<_DeviceControlPage> {
  double _setTemp = 0.0;
  double _actualTemp = 0.0;
  double _humidity = 45.0;
  bool _isScheduleEnabled = true;
  bool _isLunchEnabled = true;
  TimeOfDay _scheduleStartTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _scheduleEndTime = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _lunchStartTime = const TimeOfDay(hour: 12, minute: 30);
  TimeOfDay _lunchEndTime = const TimeOfDay(hour: 13, minute: 30);

  // Unified Schedule Variables (Strings)
  String _scheduleOn1 = '--:--';
  String _scheduleOff1 = '--:--';
  String _lunchOn = '--:--';
  String _lunchOff = '--:--';

  @override
  void initState() {
    super.initState();
    _setTemp = widget.initialTemp;
    _actualTemp = widget.actualTemp;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final primaryColor = const Color(0xFF6CC042);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1B172E) : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: isDark ? Colors.white : Colors.black,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Controls - ${widget.equipmentName}',
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
        child: Column(
          children: [
            const SizedBox(height: 10),
            // Gauge Section
            _InteractiveThermostatGauge(
              setTemp: _setTemp,
              actualTemp: _actualTemp,
              isDark: isDark,
              isOnline: widget.isOnline,
              colorScheme: colorScheme,
              onTempChanged: (newTemp) {
                setState(() => _setTemp = newTemp);
                // In this sub-page, we still publish commands if interaction is enabled
                // _publishMqttCommand('TEMP_CN:${newTemp.toInt()}'); // Needs access to _publishMqttCommand or pass it
              },
              onClearTemp: () {
                setState(() => _setTemp = 0.0);
                // _publishMqttCommand('TEMP_CLEAR');
              },
              onDisabledInteraction: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Device is Offline - Check Connection'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            // Plus/Minus Buttons below gauge
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _circleButton(Icons.remove_rounded, isDark, () {
                  setState(() => _actualTemp = math.max(0, _actualTemp - 0.5));
                }, size: 56),
                const SizedBox(width: 40),
                _circleButton(Icons.add_rounded, isDark, () {
                  setState(() => _actualTemp = math.min(40, _actualTemp + 0.5));
                }, size: 56),
              ],
            ),
            const SizedBox(height: 25),

            // Humidity Control
            _buildControlCard(
              title: 'HUMIDITY',
              value: '${_humidity.toInt()}%',
              icon: Icons.water_drop_rounded,
              color: Colors.blueAccent,
              isDark: isDark,
              onIncrement: () =>
                  setState(() => _humidity = math.min(100, _humidity + 5)),
              onDecrement: () =>
                  setState(() => _humidity = math.max(0, _humidity - 5)),
            ),
            const SizedBox(height: 15),

            // Daily Schedule
            _buildTimeCard(
              title: 'DAILY SCHEDULE',
              startTime: _scheduleOn1,
              endTime: _scheduleOff1,
              isEnabled: _isScheduleEnabled,
              color: const Color(0xFFF59E0B),
              isDark: isDark,
              onToggle: (val) => setState(() => _isScheduleEnabled = val),
              onStartTimeTap: () => _showSchedulePicker(isDark),
              onEndTimeTap: () => _showSchedulePicker(isDark),
            ),
            const SizedBox(height: 15),

            // Lunch Break
            _buildTimeCard(
              title: 'LUNCH BREAK',
              startTime: _lunchOn,
              endTime: _lunchOff,
              isEnabled: _isLunchEnabled,
              color: primaryColor,
              isDark: isDark,
              onToggle: (val) => setState(() => _isLunchEnabled = val),
              onStartTimeTap: () => _showSchedulePicker(isDark),
              onEndTimeTap: () => _showSchedulePicker(isDark),
            ),
            const SizedBox(height: 25),

            // SET Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () {
                  // TODO: Save to backend if needed
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'SET',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildControlCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
    required VoidCallback onIncrement,
    required VoidCallback onDecrement,
  }) {
    final cardColor = isDark ? const Color(0xFF2A244D) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color.withOpacity(0.6), size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.poppins(
                  color: textColor.withOpacity(0.4),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                value,
                style: GoogleFonts.poppins(
                  color: textColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Row(
                children: [
                  _circleButton(Icons.remove, isDark, onDecrement),
                  const SizedBox(width: 12),
                  _circleButton(Icons.add, isDark, onIncrement),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeCard({
    required String title,
    required String startTime,
    required String endTime,
    required bool isEnabled,
    required Color color,
    required bool isDark,
    required ValueChanged<bool> onToggle,
    required VoidCallback onStartTimeTap,
    required VoidCallback onEndTimeTap,
  }) {
    final cardColor = isDark ? const Color(0xFF2A244D) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Switch.adaptive(
                value: isEnabled,
                onChanged: onToggle,
                activeColor: color,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _timePickerButton(
                  'START',
                  _formatDisplayTime(startTime),
                  isDark,
                  onStartTimeTap,
                ),
              ),
              Container(
                width: 1,
                height: 30,
                color: textColor.withOpacity(0.1),
                margin: const EdgeInsets.symmetric(horizontal: 20),
              ),
              Expanded(
                child: _timePickerButton(
                  'END',
                  _formatDisplayTime(endTime),
                  isDark,
                  onEndTimeTap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timePickerButton(
    String label,
    String time,
    bool isDark,
    VoidCallback onTap,
  ) {
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              color: textColor.withOpacity(0.4),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            time,
            style: GoogleFonts.poppins(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton(
    IconData icon,
    bool isDark,
    VoidCallback onTap, {
    double size = 40,
  }) {
    const themeGreen = Color(0xFF6CC042);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: themeGreen.withAlpha(30),
          shape: BoxShape.circle,
          border: Border.all(
            color: themeGreen.withAlpha(120),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: themeGreen.withAlpha(70),
              blurRadius: 14,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          icon,
          color: themeGreen,
          size: size * 0.48,
        ),
      ),
    );
  }

  String _formatDisplayTime(String time) {
    if (time == '--:--' || time.isEmpty || !time.contains(':')) return '--:--';
    try {
      final parts = time.split(':');
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      int displayHour = hour % 12;
      if (displayHour == 0) displayHour = 12;
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return '--:--';
    }
  }

  void _showSchedulePicker(bool isDark) {
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: _ScheduleControlDialog(
          isDark: isDark,
          schedules: [
            {'on': _scheduleOn1, 'off': _scheduleOff1},
            {'on': '--:--', 'off': '--:--'},
            {'on': '--:--', 'off': '--:--'},
          ],
          lunch: {'on': _lunchOn, 'off': _lunchOff},
          onCommand: (type, index, time) =>
              _publishMqttSchedule(type, index, time),
        ),
      ),
    );
  }

  Future<void> _publishMqttSchedule(
      String type, int index, String? time) async {
    if (mounted) {
      setState(() {
        if (type == 'SCH_ON') {
          if (index == 1) _scheduleOn1 = time!;
        }
        if (type == 'SCH_OFF') {
          if (index == 1) _scheduleOff1 = time!;
        }
        if (type == 'LUNCH_ON') _lunchOn = time!;
        if (type == 'LUNCH_OFF') _lunchOff = time!;
        if (type == 'SCH_CLEAR') {
          if (index == 1) {
            _scheduleOn1 = '--:--';
            _scheduleOff1 = '--:--';
          }
          if (index == 4) {
            _lunchOn = '--:--';
            _lunchOff = '--:--';
          }
        }
        if (type == 'SCH_CLEAR_ALL') {
          _scheduleOn1 = '--:--';
          _scheduleOff1 = '--:--';
          _lunchOn = '--:--';
          _lunchOff = '--:--';
        }
      });
    }
  }
}

class _CustomTimePickerDialog extends StatefulWidget {
  final TimeOfDay initialTime;
  const _CustomTimePickerDialog({required this.initialTime});

  @override
  State<_CustomTimePickerDialog> createState() =>
      _CustomTimePickerDialogState();
}

class _CustomTimePickerDialogState extends State<_CustomTimePickerDialog> {
  late int _hour;
  late int _minute;
  late String _period;

  @override
  void initState() {
    super.initState();
    _hour = widget.initialTime.hourOfPeriod == 0
        ? 12
        : widget.initialTime.hourOfPeriod;
    _minute = widget.initialTime.minute;
    _period = widget.initialTime.period == DayPeriod.am ? 'AM' : 'PM';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = const Color(0xFF6CC042);
    final bgColor = isDark ? const Color(0xFF1B172E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.menu, color: textColor.withOpacity(0.6)),
                  onPressed: () {},
                ),
                const Spacer(),
                Text(
                  'Set Time',
                  style: GoogleFonts.poppins(
                    color: textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 40),
              ],
            ),
            const SizedBox(height: 30),

            // Analog Clock (Decorative)
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: textColor.withOpacity(0.1), width: 8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Hour Marks
                  for (int i = 1; i <= 12; i++)
                    Transform.rotate(
                      angle: (i * 30) * math.pi / 180,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          width: 2,
                          height: 8,
                          margin: const EdgeInsets.only(top: 4),
                          color: textColor.withOpacity(0.2),
                        ),
                      ),
                    ),
                  // Hands (Approximate based on selected time)
                  Transform.rotate(
                    angle: ((_hour % 12 + _minute / 60) * 30) * math.pi / 180,
                    child: Container(
                      width: 4,
                      height: 50,
                      decoration: BoxDecoration(
                        color: textColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      margin: const EdgeInsets.only(bottom: 50),
                    ),
                  ),
                  Transform.rotate(
                    angle: (_minute * 6) * math.pi / 180,
                    child: Container(
                      width: 2,
                      height: 70,
                      decoration: BoxDecoration(
                        color: textColor.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(1),
                      ),
                      margin: const EdgeInsets.only(bottom: 70),
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // Time Selectors
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _selector(
                  List.generate(12, (i) => (i + 1).toString().padLeft(2, '0')),
                  _hour.toString().padLeft(2, '0'),
                  (val) => setState(() => _hour = int.parse(val!)),
                  isDark,
                ),
                _selector(
                  List.generate(60, (i) => i.toString().padLeft(2, '0')),
                  _minute.toString().padLeft(2, '0'),
                  (val) => setState(() => _minute = int.parse(val!)),
                  isDark,
                ),
                _selector(
                  ['AM', 'PM'],
                  _period,
                  (val) => setState(() => _period = val!),
                  isDark,
                ),
              ],
            ),
            const SizedBox(height: 40),

            // Set Time Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  int finalHour = _hour % 12;
                  if (_period == 'PM') finalHour += 12;
                  Navigator.pop(
                    context,
                    TimeOfDay(hour: finalHour, minute: _minute),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(
                    0xFF2D6A74,
                  ), // Match screenshot's teal-ish color
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Set Time',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: GoogleFonts.poppins(
                  color: textColor.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selector(
    List<String> items,
    String value,
    ValueChanged<String?> onChanged,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButton<String>(
        value: value,
        items: items
            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
            .toList(),
        onChanged: onChanged,
        underline: const SizedBox(),
        style: GoogleFonts.poppins(
          color: isDark ? Colors.white : Colors.black87,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        icon: Icon(
          Icons.arrow_drop_down,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
        dropdownColor: isDark ? const Color(0xFF2A244D) : Colors.white,
      ),
    );
  }
}

class _InteractiveThermostatGauge extends StatelessWidget {
  final double setTemp;
  final double actualTemp;
  final bool isDark;
  final bool isOnline;
  final ColorScheme colorScheme;
  final ValueChanged<double> onTempChanged;
  final VoidCallback? onClearTemp;
  final VoidCallback? onDisabledInteraction;

  const _InteractiveThermostatGauge({
    Key? key,
    required this.setTemp,
    required this.actualTemp,
    required this.isDark,
    required this.isOnline,
    required this.colorScheme,
    required this.onTempChanged,
    this.onClearTemp,
    this.onDisabledInteraction,
  }) : super(key: key);

  Color _getColorForTemp(double temp) {
    if (temp <= 19) return const Color(0xFFEF4444); // Blue
    if (temp <= 22) return const Color(0xFFF59E0B); // Cyan
    if (temp <= 26) return const Color(0xFF10B981); // Green
    if (temp <= 29) return const Color(0xFFF59E0B); // Orange
    return const Color(0xFFEF4444); // Red
  }

  void _handlePan(Offset localPosition, Size size) {
    if (!isOnline) {
      onDisabledInteraction?.call();
      return;
    }
    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;

    double angle = math.atan2(dy, dx);
    if (angle < 0) angle += 2 * math.pi;

    const startAngle = math.pi * 0.75;
    const sweepAngle = math.pi * 1.5;

    double relativeAngle = angle - startAngle;
    if (relativeAngle < 0) relativeAngle += 2 * math.pi;

    if (relativeAngle > sweepAngle) {
      if (relativeAngle > sweepAngle + (2 * math.pi - sweepAngle) / 2) {
        relativeAngle = 0;
      } else {
        relativeAngle = sweepAngle;
      }
    }

    double newTemp = (relativeAngle / sweepAngle) * 40;
    newTemp = newTemp.clamp(16.0, 30.0).roundToDouble();

    onTempChanged(newTemp);
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = _getColorForTemp(setTemp);
    // Calculate gauge size to fill available width
    final screenWidth = MediaQuery.of(context).size.width;
    const buttonSize = 44.0;
    const gap = 8.0;
    final gaugeSize =
        (screenWidth - buttonSize * 2 - gap * 2).clamp(240.0, 310.0);
    final fontSize = gaugeSize * 0.165; // scale font with gauge

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Minus Button
        _buildSideControl(
          icon: Icons.remove,
          onTap: isOnline
              ? () => onTempChanged((setTemp - 1).clamp(16.0, 30.0))
              : onDisabledInteraction,
          color: isOnline ? activeColor : Colors.grey,
          size: buttonSize,
          isDisabled: false, // Keep clickable for feedback
        ),
        SizedBox(width: gap),
        // Gauge — fills available screen width
        GestureDetector(
          onPanUpdate: (details) =>
              _handlePan(details.localPosition, Size(gaugeSize, gaugeSize)),
          onTapDown: (details) =>
              _handlePan(details.localPosition, Size(gaugeSize, gaugeSize)),
          child: Container(
            width: gaugeSize,
            height: gaugeSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                if (isDark && isOnline)
                  BoxShadow(
                    color: activeColor.withOpacity(0.15),
                    blurRadius: 16,
                    spreadRadius: 4,
                  ),
              ],
            ),
            child: CustomPaint(
              size: Size(gaugeSize, gaugeSize),
              painter: _InteractiveThermostatPainter(
                setTemp: setTemp,
                actualTemp: actualTemp,
                isDark: isDark,
                colorScheme: colorScheme,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      isOnline ? 'ACTUAL' : 'OFFLINE',
                      style: GoogleFonts.poppins(
                        color: (isOnline
                                ? (isDark ? Colors.white : colorScheme.primary)
                                : Colors.redAccent)
                            .withOpacity(0.4),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${actualTemp.toStringAsFixed(1)}\u00b0C',
                      style: GoogleFonts.poppins(
                        color: isDark ? Colors.white : const Color(0xFF1B172E),
                        fontSize: fontSize,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: (isOnline ? activeColor : Colors.grey)
                            .withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: (isOnline ? activeColor : Colors.grey)
                              .withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'SET TEMP',
                            style: GoogleFonts.poppins(
                              color: isOnline ? activeColor : Colors.grey,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${setTemp.toInt()}\u00b0C',
                            style: GoogleFonts.poppins(
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1B172E),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (onClearTemp != null && isOnline) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: onClearTemp,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: activeColor.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.close_rounded,
                                  color: activeColor,
                                  size: 10,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: gap),
        // Plus Button
        _buildSideControl(
          icon: Icons.add,
          onTap: isOnline
              ? () => onTempChanged((setTemp + 1).clamp(16.0, 30.0))
              : onDisabledInteraction,
          color: isOnline ? activeColor : Colors.grey,
          size: buttonSize,
          isDisabled: false, // Keep clickable for feedback
        ),
      ],
    );
  }

  Widget _buildSideControl({
    required IconData icon,
    VoidCallback? onTap,
    required Color color,
    double size = 52,
    bool isDisabled = false,
  }) {
    // Auto-color: green for +, red for −
    final isPlus = icon == Icons.add || icon == Icons.add_rounded;
    final accentColor = isDisabled
        ? Colors.white10
        : (isPlus ? const Color(0xFF6CC042) : const Color(0xFFEF4444));

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF1B172E),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.3),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Icon(
            icon,
            color: accentColor,
            size: size * 0.45,
          ),
        ),
      ),
    );
  }
}

class _InteractiveThermostatPainter extends CustomPainter {
  final double setTemp;
  final double actualTemp;
  final bool isDark;
  final ColorScheme colorScheme;

  _InteractiveThermostatPainter({
    required this.setTemp,
    required this.actualTemp,
    required this.isDark,
    required this.colorScheme,
  });

  Color _getColorForTemp(double temp) {
    if (temp <= 19) return const Color(0xFFEF4444); // Blue
    if (temp <= 22) return const Color(0xFFF59E0B); // Cyan
    if (temp <= 26) return const Color(0xFF10B981); // Green
    if (temp <= 29) return const Color(0xFFF59E0B); // Orange
    return const Color(0xFFEF4444); // Red
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    const startAngle = math.pi * 0.75;
    const sweepAngle = math.pi * 1.5;

    double tempToAngle(double temp) => (temp / 40) * sweepAngle + startAngle;

    final trackRect = Rect.fromCircle(center: center, radius: radius - 15);
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    void drawTrackRange(double start, double end, Color color) {
      final sAngle = tempToAngle(start);
      final swAngle = ((end - start) / 40) * sweepAngle;
      trackPaint.color = color.withOpacity(0.15);
      canvas.drawArc(trackRect, sAngle, swAngle, false, trackPaint);
    }

    drawTrackRange(0, 19, const Color(0xFFEF4444));
    drawTrackRange(19, 22, const Color(0xFFF59E0B));
    drawTrackRange(22, 26, const Color(0xFF6CC042));
    drawTrackRange(26, 29, const Color(0xFFFBBF24));
    drawTrackRange(29, 40, const Color(0xFFEF4444));

    final fullTrackPaint = Paint()
      ..color = isDark
          ? Colors.white.withOpacity(0.03)
          : Colors.black.withOpacity(0.03)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12;
    canvas.drawCircle(center, radius - 15, fullTrackPaint);

    // Draw the static gauge lines/arcs...
    final basePaint = Paint()
      ..color = isDark
          ? Colors.white.withOpacity(0.05)
          : colorScheme.primary.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(trackRect, startAngle, sweepAngle, false, basePaint);

    // Active Arc for SET TEMP (Dynamic color based on temp)
    final activeColor = _getColorForTemp(setTemp);
    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = activeColor
          .withOpacity(0.2) // slightly lower opacity to compensate for no blur
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24 // wider to act as a soft edge
      ..strokeCap = StrokeCap.round;

    final setSweep = (setTemp / 40) * sweepAngle;
    canvas.drawArc(trackRect, startAngle, setSweep, false, glowPaint);
    canvas.drawArc(trackRect, startAngle, setSweep, false, activePaint);

    // Handle for SET TEMP (Visual indicator only)
    final handleAngle = setSweep + startAngle;
    final handlePos = Offset(
      center.dx + (radius - 15) * math.cos(handleAngle),
      center.dy + (radius - 15) * math.sin(handleAngle),
    );

    // Simple shadow/border instead of expensive blur
    canvas.drawCircle(
      handlePos,
      12, // Handle dot size
      Paint()
        ..color = Colors.white.withOpacity(0.3)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(handlePos, 10, Paint()..color = Colors.white);
    canvas.drawCircle(handlePos, 6, Paint()..color = activeColor);

    // (Actual Temperature Indicator removed as requested)

    for (int i = 0; i <= 60; i++) {
      final angle = (i / 60) * sweepAngle + startAngle;
      final tickTemp = (i / 60) * 40;
      final isActive = tickTemp <= setTemp;
      final tickPaint = Paint()
        ..color = isActive
            ? activeColor
            : (isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.1))
        ..strokeWidth = 1.5;
      final innerR = radius - 45;
      final outerR = radius - 30;
      canvas.drawLine(
        Offset(
          center.dx + innerR * math.cos(angle),
          center.dy + innerR * math.sin(angle),
        ),
        Offset(
          center.dx + outerR * math.cos(angle),
          center.dy + outerR * math.sin(angle),
        ),
        tickPaint,
      );
    }

    final labelPoints = [0, 19, 22, 26, 29, 40];
    for (final p in labelPoints) {
      final angle = tempToAngle(p.toDouble());
      final labelR = radius + 15;
      final textPos = Offset(
        center.dx + labelR * math.cos(angle),
        center.dy + labelR * math.sin(angle),
      );

      final textSpan = TextSpan(
        text: '$p',
        style: GoogleFonts.poppins(
          color: Colors.white60,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(
          textPos.dx - textPainter.width / 2,
          textPos.dy - textPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _InteractiveThermostatPainter oldDelegate) {
    return oldDelegate.setTemp != setTemp ||
        oldDelegate.actualTemp != actualTemp ||
        oldDelegate.isDark != isDark;
  }
}

class _ScheduleControlDialog extends StatefulWidget {
  final bool isDark;
  final List<Map<String, String>> schedules;
  final Map<String, String> lunch;
  final Function(String type, int index, String time) onCommand;

  const _ScheduleControlDialog({
    required this.isDark,
    required this.schedules,
    required this.lunch,
    required this.onCommand,
  });

  @override
  State<_ScheduleControlDialog> createState() => _ScheduleControlDialogState();
}

class _ScheduleControlDialogState extends State<_ScheduleControlDialog> {
  late List<Map<String, String>> _localSchedules;
  late Map<String, String> _localLunch;
  int _activeTab = 0; // 0: Daily, 1: Lunch
  bool _isPickerOpen = false;

  @override
  void initState() {
    super.initState();
    _localSchedules =
        widget.schedules.map((s) => Map<String, String>.from(s)).toList();
    _localLunch = Map<String, String>.from(widget.lunch);
  }

  void _handleCommand(String type, int index, String time) {
    setState(() {
      if (type == 'SCH_ON' && index >= 1 && index <= 3) {
        _localSchedules[index - 1]['on'] = time;
      } else if (type == 'SCH_OFF' && index >= 1 && index <= 3) {
        _localSchedules[index - 1]['off'] = time;
      } else if (type == 'LUNCH_ON') {
        _localLunch['on'] = time;
      } else if (type == 'LUNCH_OFF') {
        _localLunch['off'] = time;
      } else if (type == 'SCH_CLEAR') {
        if (index >= 1 && index <= 3) {
          _localSchedules[index - 1]['on'] = '--:--';
          _localSchedules[index - 1]['off'] = '--:--';
        } else if (index == 4) {
          _localLunch['on'] = '--:--';
          _localLunch['off'] = '--:--';
        }
      }
    });
    // Optimistic update done locally, now trigger the command
    Future.microtask(() => widget.onCommand(type, index, time));
  }

  void _handleClearAll() {
    setState(() {
      for (var s in _localSchedules) {
        s['on'] = '--:--';
        s['off'] = '--:--';
      }
      _localLunch['on'] = '--:--';
      _localLunch['off'] = '--:--';
    });
    widget.onCommand('SCH_CLEAR_ALL', 0, '');
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: RepaintBoundary(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.88,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF131122),
              borderRadius: BorderRadius.circular(28),
              border:
                  Border.all(color: Colors.white.withOpacity(0.08), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Schedule Manager",
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          "Optimize your device timings",
                          style: GoogleFonts.outfit(
                            color: Colors.white38,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6CC042).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFF6CC042).withOpacity(0.2)),
                      ),
                      child: const Icon(Icons.calendar_month_rounded,
                          color: Color(0xFF6CC042), size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Tab Selector
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      _buildTabButton("Daily Blocks", 0),
                      _buildTabButton("Lunch Breaks", 1),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.45,
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_activeTab == 0) ...[
                          // Daily Schedules
                          for (int i = 0; i < _localSchedules.length; i++)
                            _buildSlot(
                              context,
                              "DAILY SCHEDULE ${i + 1}",
                              _localSchedules[i]['on']!,
                              _localSchedules[i]['off']!,
                              i + 1,
                              false,
                              [
                                const Color(0xFF6CC042),
                                const Color(0xFF3B82F6),
                                const Color(0xFFF59E0B)
                              ][i],
                            ),
                        ] else ...[
                          // Lunch Break
                          _buildSlot(
                            context,
                            "LUNCH BREAK",
                            _localLunch['on']!,
                            _localLunch['off']!,
                            4,
                            true,
                            const Color(0xFFEF4444),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Column(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _handleClearAll,
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text("CLEAR ALL"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            const Color(0xFFEF4444).withOpacity(0.7),
                        side: BorderSide.none,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6CC042),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        minimumSize: const Size(double.infinity, 52),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        "SAVE CHANGES",
                        style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton(String label, int index) {
    final bool isActive = _activeTab == index;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _activeTab = index),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isActive
                  ? Colors.white.withOpacity(0.05)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                label,
                style: GoogleFonts.outfit(
                  color: isActive ? const Color(0xFF6CC042) : Colors.white24,
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlot(
    BuildContext context,
    String label,
    String on,
    String off,
    int index,
    bool isLunch,
    Color color,
  ) {
    final bool isActive = on != '--:--' || off != '--:--';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.015),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive
              ? color.withOpacity(0.1)
              : Colors.white.withOpacity(0.03),
          width: 1.0,
        ),
      ),
      child: Column(
        children: [
          // Card Header
          Row(
            children: [
              Container(
                width: 2.5,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: isActive ? color.withOpacity(0.8) : Colors.white24,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _handleCommand('SCH_CLEAR', index, ''),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.02),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.close_rounded,
                          color: isActive
                              ? const Color(0xFFEF4444).withOpacity(0.5)
                              : Colors.white10,
                          size: 11),
                      const SizedBox(width: 3),
                      Text(
                        "CLEAR",
                        style: GoogleFonts.outfit(
                          color: isActive
                              ? const Color(0xFFEF4444).withOpacity(0.5)
                              : Colors.white10,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Time Pickers Row
          Row(
            children: [
              Expanded(
                child: _timelineItem(
                    "START", on, color, isLunch ? 'LUNCH_ON' : 'SCH_ON', index),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _timelineItem("END", off, color,
                    isLunch ? 'LUNCH_OFF' : 'SCH_OFF', index),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timelineItem(
      String label, String time, Color color, String type, int index) {
    final bool isSet = time != '--:--';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          if (_isPickerOpen) return;
          setState(() => _isPickerOpen = true);
          try {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.now(),
              initialEntryMode: TimePickerEntryMode.dial,
              builder: (context, child) => Theme(
                data: ThemeData.dark().copyWith(
                  colorScheme: ColorScheme.dark(
                    primary: color,
                    onPrimary: Colors.white,
                    surface: const Color(0xFF131122),
                    onSurface: Colors.white,
                  ),
                  dialogBackgroundColor: const Color(0xFF131122),
                ),
                child: child!,
              ),
            );
            if (picked != null) {
              final formatted =
                  "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
              _handleCommand(type, index, formatted);
            }
          } catch (e) {
            debugPrint("Error showing time picker: $e");
          } finally {
            if (mounted) setState(() => _isPickerOpen = false);
          }
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: isSet
                ? color.withOpacity(0.06)
                : Colors.white.withOpacity(0.01),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSet
                  ? color.withOpacity(0.2)
                  : Colors.white.withOpacity(0.03),
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.access_time_rounded,
                      color: isSet ? color : Colors.white12, size: 12),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      color: isSet ? color.withOpacity(0.8) : Colors.white12,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _formatDisplayTime(time),
                style: GoogleFonts.outfit(
                  color: isSet ? Colors.white : Colors.white12,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDisplayTime(String time) {
    if (time == '--:--' || time.isEmpty || !time.contains(':')) return '--:--';
    try {
      final parts = time.split(':');
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);
      final period = hour >= 12 ? 'PM' : 'AM';
      int displayHour = hour % 12;
      if (displayHour == 0) displayHour = 12;
      return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return '--:--';
    }
  }
}
