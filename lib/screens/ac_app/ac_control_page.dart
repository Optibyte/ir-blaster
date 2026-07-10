import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:ui';
import 'package:ir_blaster_ac/core/services/mqtt_service.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/screens/ac_app/settings_page.dart';
import 'package:ir_blaster_ac/screens/ac_app/schedule_overview_page.dart';
import 'package:ir_blaster_ac/core/config/app_config.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ir_blaster_ac/core/services/local_cache_service.dart';
import 'package:ir_blaster_ac/screens/bluetooth_scanner_page.dart';
import 'package:ir_blaster_ac/screens/widgets/wifi_management_dialog.dart';

class ACControlPage extends StatefulWidget {
  final String? deviceName;
  final String? systemId;
  final String? systemShortId;

  const ACControlPage({
    super.key,
    this.deviceName,
    this.systemId,
    this.systemShortId,
  });

  @override
  State<ACControlPage> createState() => _ACControlPageState();
}

class _ACControlPageState extends State<ACControlPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final MqttService _mqtt = MqttService();
  late AnimationController _pulseCtrl;
  late AnimationController _fanRotationCtrl;

  // Local UI state (updated from MQTT snapshots)
  bool _isConnected = false;
  bool get _isControlAvailable => _isActive || _mqtt.isBluetoothConnected;
  bool _isActive = false;
  bool _isPowerOn = false;
  int _setTemp = 24;
  int _currentTemp = 0;
  int _humidity = 0;
  bool _irOnLearned = true;
  bool _irOffLearned = true;

  // Equipment selection state
  List<Map<String, dynamic>> _equipmentsData = [];
  bool _isLoadingEquipments = false;
  Timer? _loadingTimeoutTimer;
  String _selectedEquipmentName = '';
  String _selectedEquipmentId = '';
  String _selectedEquipmentShortId = '';
  String _activeDeviceId = ''; // Target MQTT device ID (IMEI)
  String _activeDeviceImei = ''; // Target physical IMEI

  String _schOn1 = 'DISABLED', _schOff1 = 'DISABLED';
  String _schOn2 = 'DISABLED', _schOff2 = 'DISABLED';
  String _schOn3 = 'DISABLED', _schOff3 = 'DISABLED';
  String _schOn4 = 'DISABLED', _schOff4 = 'DISABLED';
  String _schOn5 = 'DISABLED', _schOff5 = 'DISABLED';
  String _lunchOn = 'DISABLED', _lunchOff = 'DISABLED';
  List<int> _visibleSlots = [1, 2, 3];

  // Optimistic UI overrides for schedule switches (survives all rebuilds)
  final Map<int, bool> _schSwitchOverrides = {};
  final Map<int, Timer> _schOverrideTimers = {};

  Timer? _heartbeatTimer;

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer(const Duration(seconds: 30), () {
      if (mounted) {
        setState(() {
          _isActive = false;
        });
      }
    });
  }

  // Additional state for interactivity mapping to the new UI features
  String _mode = 'Cool';
  String _fanSpeed = 'Auto';
  bool _lightOn = true;
  bool _swingV = false;
  bool _swingH = false;

  // Air Quality mocks (dynamically stable around premium look values)
  final int _tvoc = 0;
  final int _co2 = 0;
  final int _aqi = 0;
  final List<Map<String, dynamic>> _activityLogs = [];

  // Pending command feedback
  bool _pendingPower = false;
  bool _pendingTemp = false;
  bool _userTempOverride = false; // true when user has explicitly changed temp
  bool _hasReceivedInitialState = false;
  DateTime? _lastPowerToggleTime;

  StreamSubscription? _stateSub;
  StreamSubscription? _responseSub;
  StreamSubscription? _connSub;

  bool _showWifiName = false;
  String _wifiSsid = '';

  bool _isReconnectingWifi = false;
  String _reconnectingWifiSsid = '';
  Timer? _reconnectingWifiTimeoutTimer;

  Future<void> _loadWifiSsid() async {
    try {
      final creds = await LocalCacheService.getWifiCredentials();
      if (creds['ssid'] != null && creds['ssid']!.isNotEmpty) {
        setState(() {
          _wifiSsid = creds['ssid']!;
        });
      }
    } catch (_) {}
  }

  void _onMqttChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);

    _fanRotationCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();

    _loadWifiSsid();
    _fetchEquipments();
    _mqtt.addListener(_onMqttChanged);
  }

  Future<void> _connectMqtt() async {
    await _connSub?.cancel();
    await _stateSub?.cancel();
    await _responseSub?.cancel();
    _hasReceivedInitialState = false;
    _userTempOverride = false;
    _isConnected = _mqtt.isConnected;

    // Load initial values from the last known state of this device if available
    final initial = _mqtt.getLastStateFor(_activeDeviceId) ??
        _mqtt.getLastStateFor(_activeDeviceImei) ??
        _mqtt.lastState;
    if (initial != null &&
        (initial.deviceId.toLowerCase() == _activeDeviceId.toLowerCase() ||
         initial.imei.toLowerCase() == _activeDeviceId.toLowerCase() ||
         (_activeDeviceImei.isNotEmpty &&
             initial.imei.toLowerCase() == _activeDeviceImei.toLowerCase()))) {
      _isActive = initial.isActive;
      if (_isActive) {
        _startHeartbeatTimer();
      }
      _isPowerOn = initial.isPowerOn;
      if (_isPowerOn && initial.setTemp >= 16 && initial.setTemp <= 30) {
        _setTemp = initial.setTemp;
      } else {
        _setTemp = 24;
      }
      _currentTemp = initial.currentTemp;
      _humidity = initial.humidity;
      _irOnLearned = initial.irOnLearned;
      _irOffLearned = initial.irOffLearned;
      if (initial.wifiSsid.isNotEmpty) {
        _wifiSsid = initial.wifiSsid;
      }
      _schOn1 = initial.schOn1;
      _schOff1 = initial.schOff1;
      _schOn2 = initial.schOn2;
      _schOff2 = initial.schOff2;
      _schOn3 = initial.schOn3;
      _schOff3 = initial.schOff3;
      _schOn4 = initial.schOn4;
      _schOff4 = initial.schOff4;
      _schOn5 = initial.schOn5;
      _schOff5 = initial.schOff5;
      _lunchOn = initial.lunchOn;
      _lunchOff = initial.lunchOff;
      _hasReceivedInitialState = true;
    }

    _connSub = _mqtt.connectionStream.listen((connected) {
      if (mounted) {
        setState(() {
          _isConnected = connected;
        });
      }
    });

    _stateSub = _mqtt.stateStream.listen((state) {
      if (!mounted) return;
      _startHeartbeatTimer();
      setState(() {
        if (_isLoadingEquipments) {
          _isLoadingEquipments = false;
          _loadingTimeoutTimer?.cancel();
        }
        _isActive = state.isActive;

        // If we are waiting for the device to connect to the new WiFi:
        if (_isReconnectingWifi && state.isActive && _isConnected) {
          if (state.wifiSsid == _reconnectingWifiSsid || state.wifiSsid.isNotEmpty) {
            _isReconnectingWifi = false;
            _reconnectingWifiTimeoutTimer?.cancel();
            _showSnack('Device successfully connected to $_reconnectingWifiSsid!', AppColors.online);
          }
        }

        // Dynamically bind to the physical device ID if they differ.
        // Avoid overwriting a specific device ID with the generic AppConfig.mqttDeviceId fallback.
        final fallbackId = AppConfig.mqttDeviceId.toLowerCase();
        if (state.deviceId.isNotEmpty &&
            _activeDeviceId != state.deviceId &&
            !(state.deviceId.toLowerCase() == fallbackId &&
                _activeDeviceId.toLowerCase() != fallbackId)) {
          debugPrint('🔄 [UI] Updating active device ID from $_activeDeviceId to ${state.deviceId} to match hardware');
          _activeDeviceId = state.deviceId;
        }

        // Power sync lock: ignore incoming telemetry power state
        // if we are waiting for an ACK (_pendingPower) or if we just toggled
        // the power in the last 6 seconds (to avoid UI reversion lag).
        final secondsSinceToggle = _lastPowerToggleTime == null
            ? 100
            : DateTime.now().difference(_lastPowerToggleTime!).inSeconds;

        if (!_pendingPower && secondsSinceToggle >= 6) {
          _isPowerOn = state.isPowerOn;
          _pendingPower = false;
        } else if (secondsSinceToggle >= 6) {
          _pendingPower = false;
        }

        // Temperature sync logic:
        if (!_isPowerOn) {
          _setTemp = 24;
          _userTempOverride = false;
        } else {
          if (_userTempOverride) {
            // Release the override when the physical device confirms receipt of the new target temperature
            if (state.setTemp == _setTemp) {
              _userTempOverride = false;
            }
          } else {
            // Sync UI temperature to the actual set temperature reported by the physical device
            if (state.setTemp >= 16 && state.setTemp <= 30) {
              _setTemp = state.setTemp;
            }
          }
        }
        if (!_hasReceivedInitialState) {
          _hasReceivedInitialState = true;
        }
        debugPrint(
            '🌡️ [STATE] UI temp=$_setTemp | device set_temp=${state.setTemp} | override=$_userTempOverride | power=$_isPowerOn');
        _currentTemp = state.currentTemp;
        _humidity = state.humidity;
        _irOnLearned = state.irOnLearned;
        _irOffLearned = state.irOffLearned;

        if (_currentTemp > 0) {
          final logMsg =
              'Telemetry: Temp ${_currentTemp.toStringAsFixed(1)}°C, Hum ${_humidity.toStringAsFixed(1)}%';
          if (_activityLogs.isEmpty ||
              _activityLogs.first['message'] != logMsg) {
            _addLog(logMsg, AppColors.primary);
          }
        }

        if (state.wifiSsid.isNotEmpty) {
          _wifiSsid = state.wifiSsid;
        }

        // Sync schedules from state
        _schOn1 = state.schOn1;
        _schOff1 = state.schOff1;
        _schOn2 = state.schOn2;
        _schOff2 = state.schOff2;
        _schOn3 = state.schOn3;
        _schOff3 = state.schOff3;
        _schOn4 = state.schOn4;
        _schOff4 = state.schOff4;
        _schOn5 = state.schOn5;
        _schOff5 = state.schOff5;
        _lunchOn = state.lunchOn;
        _lunchOff = state.lunchOff;

        // Sync local animations/modes with MQTT state if online
        if (_isPowerOn) {
          if (_fanRotationCtrl.isAnimating == false) {
            _fanRotationCtrl.repeat();
          }
        } else {
          _fanRotationCtrl.stop();
        }
      });
    });

    _responseSub = _mqtt.responseStream.listen((resp) {
      if (!mounted) return;
      if (resp.type == SirisResponseType.acOnDone) {
        setState(() {
          _isPowerOn = true;
          _pendingPower = false;
          _fanRotationCtrl.repeat();
        });
        _showSnack('AC turned ON', AppColors.online);
      } else if (resp.type == SirisResponseType.acOffDone) {
        setState(() {
          _isPowerOn = false;
          _pendingPower = false;
          _fanRotationCtrl.stop();
        });
        _showSnack('AC turned OFF', AppColors.offline);
      } else if (resp.type == SirisResponseType.tempSet) {
        setState(() => _pendingTemp = false);
        _showSnack('Temperature set to ${resp.detail ?? _setTemp}°C',
            AppColors.coolBlue);
      } else if (resp.type == SirisResponseType.tempError) {
        setState(() => _pendingTemp = false);
        _showSnack('Temperature error: ${resp.detail}', AppColors.offline);
      } else if (resp.type == SirisResponseType.scheduleSet) {
        _showSnack('Schedule updated', AppColors.warning);
      } else if (resp.type == SirisResponseType.scheduleCleared) {
        _showSnack('Schedule cleared', AppColors.heatOrange);
      } else if (resp.type == SirisResponseType.scheduleError) {
        _showSnack('Schedule error: ${resp.detail}', AppColors.offline);
      } else if (resp.type == SirisResponseType.cmdRejected) {
        _showSnack('Command rejected: device not active', AppColors.offline);
      } else if (resp.type == SirisResponseType.cmdError) {
        _showSnack('Command error: ${resp.detail}', AppColors.offline);
      } else if (resp.type == SirisResponseType.wifiPrimarySet) {
        _showSnack('Primary WiFi saved: ${resp.detail}', AppColors.online);
      } else if (resp.type == SirisResponseType.wifiSecondarySet) {
        _showSnack('Secondary WiFi saved: ${resp.detail}', AppColors.online);
      } else if (resp.type == SirisResponseType.wifiResetBtOpen) {
        _showSnack('WiFi reset complete!', AppColors.warning);
        final bool isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
        if (isCurrent && mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: Theme.of(context).cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                'WiFi Reset Complete',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
              ),
              content: Text(
                'The device WiFi has been reset and the 60-second Bluetooth provisioning window has reopened.\n\nWould you like to open the Bluetooth scanner to provision it again?',
                style: GoogleFonts.inter(fontSize: 14),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx); // Close alert
                    Navigator.of(context).pop(); // Close WiFi dialog if open
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BluetoothScannerPage()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Open Scanner', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          );
        }
      } else if (resp.type == SirisResponseType.wifiError) {
        _showSnack('WiFi Error: ${resp.detail}', AppColors.offline);
      }
    });

    final connected = await _mqtt.connect(
      deviceId: _activeDeviceId,
      imei: _activeDeviceImei,
    );
    if (mounted) setState(() => _isConnected = connected);
  }

  Future<void> _fetchEquipments() async {
    if (widget.systemId == null) {
      // Standalone mode - use default device ID
      setState(() {
        _activeDeviceId = widget.systemShortId ?? AppConfig.mqttDeviceId;
        _activeDeviceImei = '';
        _selectedEquipmentName = widget.deviceName ?? 'AC Remote';
      });
      _connectMqtt();
      return;
    }

    setState(() => _isLoadingEquipments = true);

    List<Map<String, dynamic>> allEquips = [];
    bool fetchSuccess = false;

    // 1. Try fetching from remote database
    try {
      final companyId = await AuthService.getCompanyId() ?? '';
      final siteId = await AuthService.getSiteId() ?? '';
      final token = await AuthService.getCookieHeader() ?? '';

      final queryParams = <String>[];
      if (companyId.isNotEmpty &&
          companyId != 'null' &&
          companyId != 'undefined') {
        queryParams.add('companyId=$companyId');
      }
      if (siteId.isNotEmpty && siteId != 'null' && siteId != 'undefined') {
        queryParams.add('siteId=$siteId');
      }
      final queryString =
          queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
      final url =
          '${AppConfig.provisionBaseUrl}/equipments$queryString';

       final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Cookie': 'auth_token=$token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final dynamic listData = data['data'];
        if (listData != null && listData is List) {
          allEquips =
              listData.map((e) => Map<String, dynamic>.from(e)).toList();
          fetchSuccess = true;
        }
      } else {
        debugPrint('Equipment API returned HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error fetching equipments from server: $e');
    }

    if (!fetchSuccess && widget.systemId != null) {
      debugPrint('🔄 Falling back to systems/equipment endpoint for system: ${widget.systemId}');
      try {
        final companyId = await AuthService.getCompanyId() ?? '';
        final siteId = await AuthService.getSiteId() ?? '';
        final token = await AuthService.getCookieHeader() ?? '';
        
        final fallbackUrl = '${AppConfig.provisionBaseUrl}/systems/equipment/${widget.systemId}'
            '?companyId=$companyId&siteId=$siteId';
            
        final response = await http.get(
          Uri.parse(fallbackUrl),
          headers: {
            'Authorization': 'Bearer $token',
            'Cookie': 'auth_token=$token',
            'Content-Type': 'application/json',
          },
        ).timeout(const Duration(seconds: 4));
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final dynamic listData = data['data'];
          if (listData != null && listData is List) {
            allEquips =
                listData.map((e) => Map<String, dynamic>.from(e)).toList();
            fetchSuccess = true;
            debugPrint('✅ Fallback successfully retrieved ${allEquips.length} equipments');
          }
        } else {
          debugPrint('Fallback equipments API returned HTTP ${response.statusCode}: ${response.body}');
        }
      } catch (e) {
        debugPrint('Error in fallback equipments fetch: $e');
      }
    }

    // 2. Always load and merge locally provisioned devices
    try {
      final prefs = await SharedPreferences.getInstance();
      final localDevicesJson =
          prefs.getString('local_provisioned_devices') ?? '[]';
      final List<dynamic> localList = jsonDecode(localDevicesJson);
      for (var localDev in localList) {
        final localMap = Map<String, dynamic>.from(localDev);
        final String localId = (localMap['id'] ?? '').toString();
        final exists = allEquips.any((e) {
          final eId =
              (e['id'] ?? e['Id'] ?? e['equipmentId'] ?? e['EquipmentId'] ?? '')
                  .toString();
          final eShortId = (e['shortId'] ?? e['ShortId'] ?? '').toString();
          return eId == localId || eShortId == localMap['shortId'];
        });
        if (!exists) {
          allEquips.add(localMap);
        }
      }
    } catch (e) {
      debugPrint('Error loading local devices in ACControlPage: $e');
    }

    // 3. Filter equipments by systemId
    final List<Map<String, dynamic>> filteredList = allEquips.where((e) {
      final sysId = (e['systemId'] ?? e['SystemId'] ?? '').toString();
      return sysId.toLowerCase() == widget.systemId!.toLowerCase();
    }).toList();

    if (mounted && filteredList.isNotEmpty) {
      setState(() {
        _equipmentsData = List<Map<String, dynamic>>.from(filteredList);
        _isLoadingEquipments = false;
      });
      // Find matching equipment based on passed name or short ID, or fallback to first
      Map<String, dynamic> selected = filteredList.first;
      if (widget.deviceName != null || widget.systemShortId != null) {
        for (var eq in filteredList) {
          final eqName = (eq['name'] ?? eq['Name'] ?? '').toString();
          final eqShortId =
              (eq['shortId'] ?? eq['ShortId'] ?? eq['equipmentShortId'] ?? '')
                  .toString();
          final eqId = (eq['id'] ??
                  eq['Id'] ??
                  eq['equipmentId'] ??
                  eq['EquipmentId'] ??
                  '')
              .toString();
          final eqImei = (eq['imei'] ?? eq['Imei'] ?? '').toString();

          if ((widget.deviceName != null &&
                  eqName.toLowerCase() == widget.deviceName!.toLowerCase()) ||
              (widget.systemShortId != null &&
                  eqShortId.toLowerCase() ==
                      widget.systemShortId!.toLowerCase()) ||
              (widget.systemShortId != null &&
                  eqImei.toLowerCase() ==
                      widget.systemShortId!.toLowerCase()) ||
              (widget.systemShortId != null &&
                  eqId.toLowerCase() == widget.systemShortId!.toLowerCase())) {
            selected = eq;
            break;
          }
        }
      }
      await _onEquipmentSelected(
        (selected['id'] ??
                selected['Id'] ??
                selected['equipmentId'] ??
                selected['EquipmentId'] ??
                '')
            .toString(),
        selected['name']?.toString() ?? 'AC Unit',
        (selected['imei'] ??
                selected['Imei'] ??
                selected['shortId'] ??
                selected['ShortId'] ??
                '')
            .toString(),
      );
      return;
    }

    // Fallback if anything fails and list is empty
    if (mounted) {
      setState(() {
        _activeDeviceId = widget.systemShortId ?? AppConfig.mqttDeviceId;
        _activeDeviceImei = '';
        _selectedEquipmentName = widget.deviceName ?? 'AC Remote';
        _isLoadingEquipments = false;
      });
      _connectMqtt();
    }
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
          'Cookie': 'auth_token=$token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final equipData = data['data'];
        if (equipData is List && equipData.isNotEmpty) {
          final first = equipData[0];
          return (first['imei'] ??
                  first['Imei'] ??
                  first['shortId'] ??
                  first['ShortId'] ??
                  '')
              .toString();
        } else if (equipData is Map) {
          return (equipData['imei'] ??
                  equipData['Imei'] ??
                  equipData['shortId'] ??
                  equipData['ShortId'] ??
                  '')
              .toString();
        }
      }
    } catch (e) {
      debugPrint('Error fetching equipment IMEI: $e');
    }
    return '';
  }

  Future<void> _onEquipmentSelected(
    String equipmentId,
    String name,
    String shortId,
  ) async {
    if (_selectedEquipmentId == equipmentId && _activeDeviceId.isNotEmpty)
      return;

    String? foundSsid;
    String? foundImei;
    try {
      final match = _equipmentsData.firstWhere(
        (e) =>
            (e['id'] ?? e['Id'] ?? e['equipmentId'] ?? e['EquipmentId'] ?? '')
                .toString() ==
            equipmentId,
      );
      foundSsid = match['ssid']?.toString();
      foundImei = (match['imei'] ?? match['Imei'])?.toString();
    } catch (_) {}

    setState(() {
      _selectedEquipmentId = equipmentId;
      _selectedEquipmentName = name;
      _selectedEquipmentShortId = shortId;
      _isLoadingEquipments = true;
      _isConnected = false;
      if (foundSsid != null && foundSsid.isNotEmpty) {
        _wifiSsid = foundSsid;
      }
    });

    final String resolvedDeviceId = foundImei != null && foundImei.isNotEmpty
        ? foundImei
        : await _fetchEquipmentImei(equipmentId);
    String deviceId = resolvedDeviceId.isNotEmpty ? resolvedDeviceId : shortId;

    if (mounted) {
      _loadingTimeoutTimer?.cancel();
      _loadingTimeoutTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted && _isLoadingEquipments) {
          setState(() {
            _isLoadingEquipments = false;
          });
        }
      });

      setState(() {
        _activeDeviceId = deviceId;
        _activeDeviceImei = resolvedDeviceId;
      });
      _connectMqtt();
    }
  }

  String _timeOfDayTo24h(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatTo12Hour(String time24) {
    if (time24 == 'DISABLED' || time24.isEmpty) return '08:00 AM';
    try {
      final parts = time24.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final ampm = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour % 12 == 0 ? 12 : hour % 12;
      final displayMinute = minute.toString().padLeft(2, '0');
      return '${displayHour.toString().padLeft(2, '0')}:$displayMinute $ampm';
    } catch (_) {
      return time24;
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: GoogleFonts.inter(
              color: Colors.white, fontWeight: FontWeight.w500)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 2),
    ));
  }

  void _addLog(String message, Color color) {
    final now = DateTime.now();
    final String hourPart = now.hour > 12
        ? (now.hour - 12).toString()
        : (now.hour == 0 ? "12" : now.hour.toString());
    final String amPm = now.hour >= 12 ? "PM" : "AM";
    final String timeStr =
        "$hourPart:${now.minute.toString().padLeft(2, '0')} $amPm";
    setState(() {
      _activityLogs.insert(0, {
        'message': message,
        'time': timeStr,
        'color': color,
      });
      if (_activityLogs.length > 20) _activityLogs.removeLast();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loadingTimeoutTimer?.cancel();
    _reconnectingWifiTimeoutTimer?.cancel();
    _heartbeatTimer?.cancel();
    _stateSub?.cancel();
    _responseSub?.cancel();
    _connSub?.cancel();
    _pulseCtrl.dispose();
    _fanRotationCtrl.dispose();
    _mqtt.removeListener(_onMqttChanged);
    _mqtt.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 [Lifecycle] App resumed. Reconnecting MQTT and SSE...');
      _connectMqtt();
    }
  }

  // ── MQTT Actions ──────────────────────────────────────────────────────

  void _togglePower() {
    if (!_isControlAvailable) {
      _showSnack('Control is unavailable. Please check your WiFi connection.', AppColors.offline);
      return;
    }

    if (!_isActive && !_mqtt.isBluetoothConnected) {
      _showSnack('Device is offline. Sending command...', AppColors.warning);
    } else if (!_irOnLearned || !_irOffLearned) {
      _showSnack('IR signals not learned on device. Sending command...', AppColors.warning);
    }

    final wasPowerOn = _isPowerOn;
    _addLog('Power turned ${wasPowerOn ? "OFF" : "ON"}', AppColors.online);
    setState(() {
      _isPowerOn = !wasPowerOn;
      _pendingPower = true;
      _lastPowerToggleTime = DateTime.now();
      _setTemp = 24;
      // When turning ON: protect 24°C default from firmware's static set_temp:20
      // When turning OFF: allow reset since we force 24 anyway
      _userTempOverride =
          !wasPowerOn; // true when turning ON, false when turning OFF
      _pendingTemp = false;
      if (_isPowerOn) {
        _fanRotationCtrl.repeat();
      } else {
        _fanRotationCtrl.stop();
      }
    });

    if (wasPowerOn) {
      _mqtt.turnAcOff();
    } else {
      _mqtt.turnAcOn();
      Future.delayed(const Duration(milliseconds: 300), () {
        _mqtt.setTemperature(24);
      });
    }
  }

  void _incrementTemp() {
    if (!_isControlAvailable) {
      _showSnack('Control is unavailable', AppColors.offline);
      return;
    }
    if (!_isPowerOn) return;
    if (_setTemp >= 30) return;
    setState(() {
      _setTemp++;
      _userTempOverride = true;
      _pendingTemp = true;
    });
    _addLog('Temperature set to $_setTemp°C', AppColors.coolBlue);
    _mqtt.setTemperature(_setTemp);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _pendingTemp) {
        setState(() => _pendingTemp = false);
      }
    });
  }

  void _decrementTemp() {
    if (!_isControlAvailable) {
      _showSnack('Control is unavailable', AppColors.offline);
      return;
    }
    if (!_isPowerOn) return;
    if (_setTemp <= 16) return;
    setState(() {
      _setTemp--;
      _userTempOverride = true;
      _pendingTemp = true;
    });
    _addLog('Temperature set to $_setTemp°C', AppColors.coolBlue);
    _mqtt.setTemperature(_setTemp);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && _pendingTemp) {
        setState(() => _pendingTemp = false);
      }
    });
  }

  void _cycleMode() {
    if (!_isControlAvailable) {
      _showSnack('Control is unavailable', AppColors.offline);
      return;
    }
    if (!_isPowerOn) return;
    final modes = ['Cool', 'Heat', 'Dry', 'Auto'];
    int idx = modes.indexOf(_mode);
    setState(() {
      _mode = modes[(idx + 1) % modes.length];
    });
    _addLog('Mode set to $_mode', AppColors.coolBlue);
    _mqtt.sendControlCommand('SEND:MODE');
    _showSnack('Mode changed to $_mode', AppColors.primary);
  }

  void _cycleFanSpeed() {
    if (!_isControlAvailable) {
      _showSnack('Control is unavailable', AppColors.offline);
      return;
    }
    if (!_isPowerOn) return;
    setState(() {
      if (_fanSpeed == 'Auto') {
        _fanSpeed = 'Low';
        _fanRotationCtrl.duration = const Duration(seconds: 4);
        if (_isPowerOn) _fanRotationCtrl.repeat();
      } else if (_fanSpeed == 'Low') {
        _fanSpeed = 'Medium';
        _fanRotationCtrl.duration = const Duration(seconds: 2);
        if (_isPowerOn) _fanRotationCtrl.repeat();
      } else if (_fanSpeed == 'Medium') {
        _fanSpeed = 'High';
        _fanRotationCtrl.duration = const Duration(milliseconds: 800);
        if (_isPowerOn) _fanRotationCtrl.repeat();
      } else {
        _fanSpeed = 'Auto';
        _fanRotationCtrl.duration = const Duration(seconds: 2);
        if (_isPowerOn) _fanRotationCtrl.repeat();
      }
    });
    _addLog('Fan speed set to $_fanSpeed', AppColors.primary);
    _mqtt.sendControlCommand(
        'SEND:MODE'); // fallback to Mode if Fan key isn't separate
    _showSnack('Fan speed set to $_fanSpeed', AppColors.primary);
  }

  void _toggleSwingV() {
    if (!_isControlAvailable) {
      _showSnack('Control is unavailable', AppColors.offline);
      return;
    }
    if (!_isPowerOn) return;
    setState(() => _swingV = !_swingV);
    _addLog('Vertical Swing ${_swingV ? 'ON' : 'OFF'}', AppColors.primary);
    _mqtt.sendControlCommand('SEND:SWING');
    _showSnack('Vertical Swing ${_swingV ? 'On' : 'Off'}', AppColors.primary);
  }

  void _toggleSwingH() {
    if (!_isControlAvailable) {
      _showSnack('Control is unavailable', AppColors.offline);
      return;
    }
    if (!_isPowerOn) return;
    setState(() => _swingH = !_swingH);
    _addLog('Horizontal Swing ${_swingH ? 'ON' : 'OFF'}', AppColors.primary);
    _mqtt.sendControlCommand('SEND:SWING');
    _showSnack('Horizontal Swing ${_swingH ? 'On' : 'Off'}', AppColors.primary);
  }

  void _toggleLight() {
    if (!_isControlAvailable) {
      _showSnack('Control is unavailable', AppColors.offline);
      return;
    }
    if (!_isPowerOn) return;
    setState(() => _lightOn = !_lightOn);
    _addLog('Light ${_lightOn ? 'ON' : 'OFF'}', AppColors.primary);
    _mqtt.sendControlCommand('SEND:LIGHT');
    _showSnack('Light ${_lightOn ? 'On' : 'Off'}', AppColors.primary);
  }

  void _showTimerDialog(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Set Auto-Off Timer',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose when to automatically turn off the AC.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: isDark ? Colors.white38 : Colors.black45,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _timerOption(context, '30 min'),
                  const SizedBox(width: 12),
                  _timerOption(context, '1 hour'),
                  const SizedBox(width: 12),
                  _timerOption(context, '2 hours'),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  bool _validateLunchSchedule({String? pendingLunchOn, String? pendingLunchOff}) {
    final bool isSlot1Active = _schOn1 != 'DISABLED' || _schOff1 != 'DISABLED';
    final bool isSlot2Active = _schOn2 != 'DISABLED' || _schOff2 != 'DISABLED';
    final bool isSlot3Active = _schOn3 != 'DISABLED' || _schOff3 != 'DISABLED';
    
    if (!isSlot1Active && !isSlot2Active && !isSlot3Active) {
      _showSnack("Lunch schedule can only be set when at least one daily schedule is active.", AppColors.offline);
      return false;
    }
    
    String? earliestDailyOn;
    
    int timeToMinutes(String time24) {
      try {
        final parts = time24.split(':');
        return int.parse(parts[0]) * 60 + int.parse(parts[1]);
      } catch (_) {
        return 0;
      }
    }
    
    void checkEarliest(String schOn) {
      if (schOn != 'DISABLED' && schOn.isNotEmpty) {
        if (earliestDailyOn == null || timeToMinutes(schOn) < timeToMinutes(earliestDailyOn!)) {
          earliestDailyOn = schOn;
        }
      }
    }
    
    checkEarliest(_schOn1);
    checkEarliest(_schOn2);
    checkEarliest(_schOn3);
    
    if (earliestDailyOn == null) {
      return true;
    }
    
    final targetLunchOn = pendingLunchOn ?? (_lunchOn != 'DISABLED' ? _lunchOn : '12:00');
    final targetLunchOff = pendingLunchOff ?? (_lunchOff != 'DISABLED' ? _lunchOff : '13:00');
    
    final int earliestMin = timeToMinutes(earliestDailyOn!);
    final int lunchOnMin = timeToMinutes(targetLunchOn);
    final int lunchOffMin = timeToMinutes(targetLunchOff);
    
    if (lunchOnMin <= earliestMin) {
      _showSnack("Lunch ON time must be after the active daily schedule starts (${_formatTo12Hour(earliestDailyOn!)}).", AppColors.offline);
      return false;
    }
    
    if (lunchOffMin <= earliestMin) {
      _showSnack("Lunch OFF time must be after the active daily schedule starts (${_formatTo12Hour(earliestDailyOn!)}).", AppColors.offline);
      return false;
    }
    
    return true;
  }

  void _showEditScheduleDialog(BuildContext context, int slot, String type,
      String currentTime, bool isDark) {
    String default24h = '08:00';
    if (currentTime.contains('AM') || currentTime.contains('PM')) {
      try {
        final parts = currentTime.split(' ');
        final timePart = parts[0];
        final amPm = parts[1];
        final timeParts = timePart.split(':');
        int hour = int.parse(timeParts[0]);
        final int minute = int.parse(timeParts[1]);
        if (amPm == 'PM' && hour < 12) hour += 12;
        if (amPm == 'AM' && hour == 12) hour = 0;
        default24h =
            '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    } else {
      default24h = currentTime;
    }

    final timeController = TextEditingController(text: default24h);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        final textCol = isDark ? Colors.white : AppColors.textPrimary;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2D2D44) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            slot == 0 ? "Configure Lunch ($type)" : "Configure Slot $slot ($type)",
            style:
                GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Time (HH:MM in 24h)",
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: timeController,
                      keyboardType: TextInputType.datetime,
                      style: TextStyle(color: textCol),
                      decoration: InputDecoration(
                        hintText: "e.g. 08:30 or 17:45",
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.access_time_rounded,
                        color: AppColors.primary),
                    onPressed: () async {
                      final TimeOfDay? picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (picked != null) {
                        final String formatted = _timeOfDayTo24h(picked);
                        timeController.text = formatted;
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                final rawTime = timeController.text.trim();
                final regExp = RegExp(r'^([01]?[0-9]|2[0-3]):[0-5][0-9]$');
                if (!regExp.hasMatch(rawTime)) {
                  _showSnack(
                      "Invalid time format. Use HH:MM", AppColors.offline);
                  return;
                }

                // Zero-pad to ensure HH:MM format (e.g. '8:00' → '08:00')
                final parts = rawTime.split(':');
                final time = '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';

                // Check MQTT connection before sending
                if (!_mqtt.isConnected && !_mqtt.isBluetoothConnected) {
                  _showSnack(
                      'Cannot set schedule — device not connected',
                      AppColors.offline);
                  return;
                }

                if (slot == 0) {
                  if (type == 'ON') {
                    if (!_validateLunchSchedule(pendingLunchOn: time)) {
                      return;
                    }
                    _mqtt.setLunchOn(time);
                    _mqtt.updateLunchOptimistic(lunchOn: time);
                  } else {
                    if (!_validateLunchSchedule(pendingLunchOff: time)) {
                      return;
                    }
                    _mqtt.setLunchOff(time);
                    _mqtt.updateLunchOptimistic(lunchOff: time);
                  }
                  Navigator.pop(context);
                  _showSnack(
                      'Lunch $type set to ${_formatTo12Hour(time)}',
                      AppColors.primary);
                } else {
                  if (type == 'ON') {
                    final bool isLunchActive = _lunchOn != 'DISABLED' || _lunchOff != 'DISABLED';
                    if (isLunchActive) {
                      final lunchOnTime = _lunchOn != 'DISABLED' ? _lunchOn : '12:00';
                      int timeToMinutes(String t) {
                        try {
                          final parts = t.split(':');
                          return int.parse(parts[0]) * 60 + int.parse(parts[1]);
                        } catch (_) {
                          return 0;
                        }
                      }
                      if (timeToMinutes(time) >= timeToMinutes(lunchOnTime)) {
                        _showSnack(
                            "Daily schedule must start before the active Lunch schedule starts (${_formatTo12Hour(lunchOnTime)}).",
                            AppColors.offline);
                        return;
                      }
                    }
                    _mqtt.setScheduleOn(slot, time);
                    _mqtt.updateScheduleOptimistic(slot: slot, onTime: time);
                  } else {
                    _mqtt.setScheduleOff(slot, time);
                    _mqtt.updateScheduleOptimistic(slot: slot, offTime: time);
                  }
                  Navigator.pop(context);
                  _showSnack(
                      'Schedule $type set to ${_formatTo12Hour(time)} for Slot $slot',
                      AppColors.primary);
                }

                // Query status after a delay to confirm device received the command
                Future.delayed(const Duration(milliseconds: 800), () {
                  _mqtt.getScheduleStatus();
                });
                // Second query for slower hardware
                Future.delayed(const Duration(milliseconds: 2500), () {
                  _mqtt.getScheduleStatus();
                });
              },
              child: const Text("Save",
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.green)),
            ),
          ],
        );
      },
    );
  }

  String _formatLastSeen(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 5) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _showSseInfoDialog(BuildContext context, bool isDark) {
    final textCol = isDark ? Colors.white : AppColors.textPrimary;
    final subtextCol = isDark ? Colors.white54 : Colors.black54;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2D2D44) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(
                _mqtt.isSseConnected ? Icons.sensors_rounded : Icons.sensors_off_rounded,
                color: _mqtt.isSseConnected ? Colors.green : Colors.red,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                'Stream Status',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: textCol,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sseInfoRow('Connection', _mqtt.isSseConnected ? 'Connected' : 'Disconnected',
                  _mqtt.isSseConnected ? Colors.green : Colors.red, isDark),
              const SizedBox(height: 12),
              _sseInfoRow('Endpoint', '/mqtt/stream', AppColors.primary, isDark),
              const SizedBox(height: 12),
              _sseInfoRow(
                'Last Data',
                _mqtt.sseLastDataTime != null
                    ? _formatLastSeen(_mqtt.sseLastDataTime!)
                    : 'No data received',
                subtextCol,
                isDark,
              ),
              const SizedBox(height: 12),
              _sseInfoRow('Device ID', _activeDeviceId.isNotEmpty ? _activeDeviceId : '--', subtextCol, isDark),
              const SizedBox(height: 12),
              _sseInfoRow('IMEI', _activeDeviceImei.isNotEmpty ? _activeDeviceImei : '--', subtextCol, isDark),
              if (_mqtt.sseLastPayload != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Last Payload',
                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: subtextCol),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: SingleChildScrollView(
                    child: Text(
                      _mqtt.sseLastPayload!,
                      style: GoogleFonts.robotoMono(
                        fontSize: 9,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        );
      },
    );
  }

  Widget _sseInfoRow(String label, String value, Color valueColor, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }

  void _showSchedulesSheet(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        int activeTab = 0;
        final cardBg =
            isDark ? AppColors.backgroundDark : const Color(0xFFF1F5F9);
        final textCol = isDark ? Colors.white : AppColors.textPrimary;
        final subtextCol = isDark ? Colors.white38 : Colors.black45;

        return StreamBuilder<SirisDeviceState>(
          stream: _mqtt.stateStream,
          initialData: _mqtt.lastState,
          builder: (context, snapshot) {
            final state = snapshot.data;
            final String schOn1 = state?.schOn1 ?? _schOn1;
            final String schOff1 = state?.schOff1 ?? _schOff1;
            final String schOn2 = state?.schOn2 ?? _schOn2;
            final String schOff2 = state?.schOff2 ?? _schOff2;
            final String schOn3 = state?.schOn3 ?? _schOn3;
            final String schOff3 = state?.schOff3 ?? _schOff3;
            final String schOn4 = state?.schOn4 ?? _schOn4;
            final String schOff4 = state?.schOff4 ?? _schOff4;
            final String schOn5 = state?.schOn5 ?? _schOn5;
            final String schOff5 = state?.schOff5 ?? _schOff5;
            final String schOnLunch = state?.lunchOn ?? _lunchOn;
            final String schOffLunch = state?.lunchOff ?? _lunchOff;

            // Sync overrides with telemetry — clear override only when hardware confirms
            final Map<int, String> slotOnMap = {
              1: schOn1,
              2: schOn2,
              3: schOn3,
              4: schOn4,
              5: schOn5
            };
            final Map<int, String> slotOffMap = {
              1: schOff1,
              2: schOff2,
              3: schOff3,
              4: schOff4,
              5: schOff5
            };
            for (int slot in List.from(_schSwitchOverrides.keys)) {
              if (slot == 0) {
                final bool telemetryActive = (schOnLunch != 'DISABLED' ||
                    schOffLunch != 'DISABLED');
                if (_schSwitchOverrides[0] == telemetryActive) {
                  _schSwitchOverrides.remove(0);
                  _schOverrideTimers[0]?.cancel();
                  _schOverrideTimers.remove(0);
                }
              } else {
                final bool telemetryActive = (slotOnMap[slot] != 'DISABLED' ||
                    slotOffMap[slot] != 'DISABLED');
                if (_schSwitchOverrides[slot] == telemetryActive) {
                  _schSwitchOverrides.remove(slot);
                  _schOverrideTimers[slot]?.cancel();
                  _schOverrideTimers.remove(slot);
                }
              }
            }

            return StatefulBuilder(
              builder: (BuildContext context, StateSetter setModalState) {
                return Container(
                  height: MediaQuery.of(context).size.height * 0.7,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceDark : Colors.white,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white12 : Colors.black12,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Schedules',
                            style: GoogleFonts.outfit(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: textCol,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              _showSseInfoDialog(context, isDark);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: _mqtt.isSseConnected
                                    ? Colors.green.withOpacity(0.1)
                                    : Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _mqtt.isSseConnected
                                      ? Colors.green.withOpacity(0.3)
                                      : Colors.red.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: _mqtt.isSseConnected
                                          ? Colors.green
                                          : Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _mqtt.isSseConnected ? 'Live' : 'Offline',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: _mqtt.isSseConnected
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      // SSE Stream Status Banner
                      if (_mqtt.sseLastDataTime != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.04)
                                : const Color(0xFFF0F4FF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withOpacity(0.08)
                                  : const Color(0xFFD0DBFF),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.sensors_rounded,
                                size: 16,
                                color: _mqtt.isSseConnected
                                    ? AppColors.primary
                                    : (isDark ? Colors.white30 : Colors.black26),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Last sync: ${_formatLastSeen(_mqtt.sseLastDataTime!)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: isDark ? Colors.white54 : Colors.black45,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  _mqtt.getScheduleStatus();
                                  _showSnack('Refreshing schedules...', AppColors.primary);
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.refresh_rounded,
                                    size: 16,
                                    color: isDark ? Colors.white38 : Colors.black38,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // Custom Tab Selector
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    activeTab = 0;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: activeTab == 0
                                        ? (isDark ? AppColors.surfaceDark : Colors.white)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: activeTab == 0
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.05),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            )
                                          ]
                                        : [],
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Daily Schedule',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: activeTab == 0
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: activeTab == 0
                                            ? textCol
                                            : subtextCol,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    activeTab = 1;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    color: activeTab == 1
                                        ? (isDark ? AppColors.surfaceDark : Colors.white)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: activeTab == 1
                                        ? [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.05),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            )
                                          ]
                                        : [],
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Lunch Period',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: activeTab == 1
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: activeTab == 1
                                            ? textCol
                                            : subtextCol,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: activeTab == 0
                            ? ListView.builder(
                                physics: const BouncingScrollPhysics(),
                                itemCount: 3,
                                itemBuilder: (context, idx) {
                                  final int slot = idx + 1;
                                  String schOn;
                                  String schOff;
                                  if (slot == 1) {
                                    schOn = schOn1;
                                    schOff = schOff1;
                                  } else if (slot == 2) {
                                    schOn = schOn2;
                                    schOff = schOff2;
                                  } else {
                                    schOn = schOn3;
                                    schOff = schOff3;
                                  }

                                  final bool isOnActive = schOn != 'DISABLED';
                                  final bool isOffActive = schOff != 'DISABLED';

                                  String defOnDisplay = '08:00 AM';
                                  String defOffDisplay = '01:00 PM';
                                  String defRawOn = '08:00';
                                  String defRawOff = '13:00';

                                  if (slot == 2) {
                                    defOnDisplay = '06:00 PM';
                                    defOffDisplay = '11:00 PM';
                                    defRawOn = '18:00';
                                    defRawOff = '23:00';
                                  } else if (slot == 3) {
                                    defOnDisplay = '09:00 AM';
                                    defOffDisplay = '05:00 PM';
                                    defRawOn = '09:00';
                                    defRawOff = '17:00';
                                  }

                                  final String onTimeDisplay = isOnActive
                                      ? _formatTo12Hour(schOn)
                                      : defOnDisplay;
                                  final String offTimeDisplay = isOffActive
                                      ? _formatTo12Hour(schOff)
                                      : defOffDisplay;

                                  final String rawOnTime =
                                      isOnActive ? schOn : defRawOn;
                                  final String rawOffTime =
                                      isOffActive ? schOff : defRawOff;

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 18, vertical: 16),
                                    decoration: BoxDecoration(
                                      color: cardBg,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isDark
                                            ? AppColors.dividerDark
                                            : Colors.transparent,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Slot Title and Master Switch
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Schedule Slot $slot',
                                              style: GoogleFonts.outfit(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: textCol,
                                              ),
                                            ),
                                            Switch(
                                              value: _schSwitchOverrides[slot] ??
                                                  (isOnActive || isOffActive),
                                              activeColor: AppColors.primary,
                                              onChanged: (val) {
                                                if (!_mqtt.isConnected && !_mqtt.isBluetoothConnected) {
                                                  _showSnack(
                                                      'Cannot change schedule — device not connected',
                                                      AppColors.offline);
                                                  return;
                                                }
                                                setModalState(() {
                                                  _schSwitchOverrides[slot] = val;
                                                });
                                                if (val) {
                                                  _mqtt.setScheduleOn(
                                                      slot, rawOnTime);
                                                  _mqtt.updateScheduleOptimistic(
                                                      slot: slot, onTime: rawOnTime);
                                                  Future.delayed(
                                                      const Duration(
                                                          milliseconds: 600), () {
                                                    _mqtt.setScheduleOff(
                                                        slot, rawOffTime);
                                                    _mqtt.updateScheduleOptimistic(
                                                        slot: slot, offTime: rawOffTime);
                                                  });
                                                } else {
                                                  _mqtt.clearScheduleSlot(slot);
                                                  _mqtt.updateScheduleOptimistic(
                                                      slot: slot, clear: true);
                                                }
                                                Future.delayed(
                                                    const Duration(
                                                        milliseconds: 1500), () {
                                                  _mqtt.getScheduleStatus();
                                                });
                                                Future.delayed(
                                                    const Duration(
                                                        milliseconds: 4000), () {
                                                  _mqtt.getScheduleStatus();
                                                });

                                                _schOverrideTimers[slot]?.cancel();
                                                _schOverrideTimers[slot] = Timer(
                                                    const Duration(seconds: 8), () {
                                                  if (mounted) {
                                                    setState(() {
                                                      _schSwitchOverrides
                                                          .remove(slot);
                                                      _schOverrideTimers.remove(slot);
                                                    });
                                                  }
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),

                                        Row(
                                          children: [
                                            // ON Time block
                                            Expanded(
                                              child: GestureDetector(
                                                behavior: HitTestBehavior.opaque,
                                                onTap: () {
                                                  _showEditScheduleDialog(
                                                    context,
                                                    slot,
                                                    'ON',
                                                    onTimeDisplay,
                                                    isDark,
                                                  );
                                                },
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'ON Time',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 11,
                                                        color: subtextCol,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      onTimeDisplay,
                                                      style: GoogleFonts.outfit(
                                                        fontSize: 18,
                                                        fontWeight: FontWeight.w800,
                                                        color: isOnActive
                                                            ? textCol
                                                            : textCol
                                                                .withOpacity(0.4),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            // Middle Divider
                                            Container(
                                              height: 32,
                                              width: 1,
                                              color: isDark
                                                  ? Colors.white10
                                                  : Colors.black12,
                                              margin: const EdgeInsets.symmetric(
                                                  horizontal: 16),
                                            ),
                                            // OFF Time block
                                            Expanded(
                                              child: GestureDetector(
                                                behavior: HitTestBehavior.opaque,
                                                onTap: () {
                                                  _showEditScheduleDialog(
                                                    context,
                                                    slot,
                                                    'OFF',
                                                    offTimeDisplay,
                                                    isDark,
                                                  );
                                                },
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'OFF Time',
                                                      style: GoogleFonts.inter(
                                                        fontSize: 11,
                                                        color: subtextCol,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      offTimeDisplay,
                                                      style: GoogleFonts.outfit(
                                                        fontSize: 18,
                                                        fontWeight: FontWeight.w800,
                                                        color: isOffActive
                                                            ? textCol
                                                            : textCol
                                                                .withOpacity(0.4),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              )
                            : SingleChildScrollView(
                                physics: const BouncingScrollPhysics(),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 18, vertical: 16),
                                  decoration: BoxDecoration(
                                    color: cardBg,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isDark
                                          ? AppColors.dividerDark
                                          : Colors.transparent,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Lunch Title and Switch
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'Lunch Period Schedule',
                                            style: GoogleFonts.outfit(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: textCol,
                                            ),
                                          ),
                                          Switch(
                                            value: _schSwitchOverrides[0] ??
                                                (schOnLunch != 'DISABLED' || schOffLunch != 'DISABLED'),
                                            activeColor: AppColors.primary,
                                            onChanged: (val) {
                                              if (!_mqtt.isConnected && !_mqtt.isBluetoothConnected) {
                                                _showSnack(
                                                    'Cannot change schedule — device not connected',
                                                    AppColors.offline);
                                                return;
                                              }
                                              final String defLunchOn = '12:00';
                                              final String defLunchOff = '13:00';
                                              final String rawLunchOn = schOnLunch != 'DISABLED' ? schOnLunch : defLunchOn;
                                              final String rawLunchOff = schOffLunch != 'DISABLED' ? schOffLunch : defLunchOff;

                                              if (val) {
                                                if (!_validateLunchSchedule(pendingLunchOn: rawLunchOn, pendingLunchOff: rawLunchOff)) {
                                                  return;
                                                }
                                                setModalState(() {
                                                  _schSwitchOverrides[0] = val;
                                                });
                                                _mqtt.setLunchOn(rawLunchOn);
                                                _mqtt.updateLunchOptimistic(lunchOn: rawLunchOn);
                                                Future.delayed(
                                                    const Duration(
                                                        milliseconds: 600), () {
                                                  _mqtt.setLunchOff(rawLunchOff);
                                                  _mqtt.updateLunchOptimistic(lunchOff: rawLunchOff);
                                                });
                                              } else {
                                                setModalState(() {
                                                  _schSwitchOverrides[0] = val;
                                                });
                                                _mqtt.clearLunchSlot();
                                                _mqtt.updateLunchOptimistic(clear: true);
                                              }
                                              Future.delayed(
                                                  const Duration(
                                                      milliseconds: 1500), () {
                                                _mqtt.getScheduleStatus();
                                              });
                                              Future.delayed(
                                                  const Duration(
                                                      milliseconds: 4000), () {
                                                _mqtt.getScheduleStatus();
                                              });

                                              _schOverrideTimers[0]?.cancel();
                                              _schOverrideTimers[0] = Timer(
                                                  const Duration(seconds: 8), () {
                                                if (mounted) {
                                                  setState(() {
                                                    _schSwitchOverrides.remove(0);
                                                    _schOverrideTimers.remove(0);
                                                  });
                                                }
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),

                                      // ON and OFF Times Side-by-Side
                                      Row(
                                        children: [
                                          // ON Time block
                                          Expanded(
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () {
                                                final String displayTime = schOnLunch != 'DISABLED' ? _formatTo12Hour(schOnLunch) : '12:00 PM';
                                                _showEditScheduleDialog(
                                                  context,
                                                  0,
                                                  'ON',
                                                  displayTime,
                                                  isDark,
                                                );
                                              },
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'ON Time',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 11,
                                                      color: subtextCol,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    schOnLunch != 'DISABLED' ? _formatTo12Hour(schOnLunch) : '12:00 PM',
                                                    style: GoogleFonts.outfit(
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.w800,
                                                      color: schOnLunch != 'DISABLED'
                                                          ? textCol
                                                          : textCol
                                                              .withOpacity(0.4),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          // Divider
                                          Container(
                                            height: 30,
                                            width: 1,
                                            color: isDark
                                                ? Colors.white10
                                                : Colors.black12,
                                            margin: const EdgeInsets.symmetric(
                                                horizontal: 16),
                                          ),
                                          // OFF Time block
                                          Expanded(
                                            child: GestureDetector(
                                              behavior: HitTestBehavior.opaque,
                                              onTap: () {
                                                final String displayTime = schOffLunch != 'DISABLED' ? _formatTo12Hour(schOffLunch) : '01:00 PM';
                                                _showEditScheduleDialog(
                                                  context,
                                                  0,
                                                  'OFF',
                                                  displayTime,
                                                  isDark,
                                                );
                                              },
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'OFF Time',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 11,
                                                      color: subtextCol,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    schOffLunch != 'DISABLED' ? _formatTo12Hour(schOffLunch) : '01:00 PM',
                                                    style: GoogleFonts.outfit(
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.w800,
                                                      color: schOffLunch != 'DISABLED'
                                                          ? textCol
                                                          : textCol
                                                              .withOpacity(0.4),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _timerOption(BuildContext context, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          Navigator.pop(context);
          _showSnack('Auto-off timer set for $label', AppColors.primary);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.backgroundDark : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppColors.dividerDark : Colors.transparent,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: isDark ? Colors.white70 : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showGraphsLogsDialog(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.45,
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Device Log & Activity',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.close_rounded,
                        color: isDark ? Colors.white30 : Colors.black26),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _activityLogs.isEmpty
                    ? Center(
                        child: Text(
                          'No activities recorded yet',
                          style: GoogleFonts.inter(
                            color: isDark ? Colors.white30 : Colors.black26,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: _activityLogs.length,
                        itemBuilder: (context, index) {
                          final log = _activityLogs[index];
                          return _buildLogItem(
                            log['message'].toString(),
                            log['time'].toString(),
                            log['color'] as Color,
                            isDark,
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLogItem(String title, String time, Color color, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? AppColors.dividerDark : Colors.grey[200]!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? Colors.white.withOpacity(0.9)
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          Text(
            time,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.backgroundDark : const Color(0xFFF8FAFC);
    final cardColor = isDark ? AppColors.surfaceDark : Colors.white;
    final textColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final subtitleColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    // Build unique non-empty dropdown items safely to prevent duplicate value assertion errors
    final List<DropdownMenuItem<String>> dropdownItems = [];
    final Set<String> seenIds = {};
    for (final equip in _equipmentsData) {
      final String id = (equip['id'] ??
              equip['Id'] ??
              equip['equipmentId'] ??
              equip['EquipmentId'] ??
              '')
          .toString();
      if (id.isNotEmpty && !seenIds.contains(id)) {
        seenIds.add(id);
        dropdownItems.add(
          DropdownMenuItem<String>(
            value: id,
            child: Text(
              '${equip['name']?.toString() ?? 'AC Unit'} (${equip['imei'] ?? equip['Imei'] ?? equip['shortId'] ?? equip['ShortId'] ?? ''})',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    }

    final String? selectedId = seenIds.contains(_selectedEquipmentId)
        ? _selectedEquipmentId
        : (seenIds.isNotEmpty ? seenIds.first : null);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: _equipmentsData.length <= 1
            ? Text(
                _selectedEquipmentName.isNotEmpty
                    ? '$_selectedEquipmentName${_selectedEquipmentShortId.isNotEmpty ? " ($_selectedEquipmentShortId)" : ""}'
                    : 'Smart IR Blaster',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              )
            : Theme(
                data: Theme.of(context).copyWith(
                  canvasColor: AppColors.primary,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedId,
                    dropdownColor: AppColors.primary,
                    icon: const Icon(Icons.arrow_drop_down_rounded,
                        color: Colors.white),
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                    items: dropdownItems,
                    onChanged: (val) {
                      if (val != null) {
                        final selected = _equipmentsData.firstWhere((e) =>
                            (e['id'] ??
                                    e['Id'] ??
                                    e['equipmentId'] ??
                                    e['EquipmentId'] ??
                                    '')
                                .toString() ==
                            val);
                        _onEquipmentSelected(
                          val,
                          selected['name']?.toString() ?? 'AC Unit',
                          (selected['imei'] ??
                                  selected['Imei'] ??
                                  selected['shortId'] ??
                                  selected['ShortId'] ??
                                  '')
                              .toString(),
                        );
                      }
                    },
                  ),
                ),
              ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: (_isLoadingEquipments || _isReconnectingWifi)
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _isReconnectingWifi
                          ? 'Applying WiFi & reconnecting to $_reconnectingWifiSsid...'
                          : 'Connecting to ${_selectedEquipmentName.isNotEmpty ? _selectedEquipmentName : "device"}...',
                      style: GoogleFonts.outfit(
                        color: isDark ? Colors.white70 : AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isReconnectingWifi
                          ? 'Please wait, this may take up to 45 seconds'
                          : 'Please wait a moment',
                      style: GoogleFonts.inter(
                        color:
                            isDark ? Colors.white38 : AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final screenHeight = constraints.maxHeight;
                  // Determine vertical spacing based on available height to ensure it fits perfectly
                  final double cardSpacing = screenHeight > 750 ? 16.0 : 10.0;
                  final double innerPadding = screenHeight > 750 ? 20.0 : 14.0;

                  final isBluetooth = _mqtt.isBluetoothConnected;
                  final isDeviceOnline = _isActive || isBluetooth;

                  Widget content = Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: innerPadding, vertical: cardSpacing),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 1. Device Info Card
                        _buildDeviceInfoCard(
                            cardColor, textColor, subtitleColor, isDark),

                        // 2. Air Quality metrics
                        _buildAirQualityMetrics(
                            cardColor, textColor, subtitleColor, isDark),

                        // 3. Current Mode indicator (Cool & Auto)
                        _buildCurrentModeBanner(textColor),

                        // 4. Circular Temperature Controller (dial + increment/decrement)
                        _buildTemperatureDialRow(textColor, isDark),

                        // 5. Modes / Action Grid (5 horizontal items)
                        _buildActionGrid(cardColor, textColor, isDark),

                        // 6. Bottom Quick Actions (Timer, Schedule, Graphs & Logs)
                        _buildBottomQuickActions(textColor, isDark),
                      ],
                    ),
                  );

                  if (!isDeviceOnline) {
                    return Stack(
                      children: [
                        ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 5.5, sigmaY: 5.5),
                          child: Container(
                            color: Colors.transparent,
                            child: IgnorePointer(child: content),
                          ),
                        ),
                        _buildBlurOverlay(isDark),
                      ],
                    );
                  }

                  return content;
                },
              ),
      ),
    );
  }

  Widget _buildBlurOverlay(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: (isDark ? Colors.black : Colors.white).withOpacity(0.35),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.signal_wifi_off_rounded,
                  color: Colors.redAccent,
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Device is Offline',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'The IR Blaster is disconnected from WiFi.\nPlease check your connection.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : Colors.black54,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widgets ──

  Widget _buildDeviceInfoCard(
      Color cardColor, Color textColor, Color subtitleColor, bool isDark) {
    final statusColor = _isPowerOn ? AppColors.online : AppColors.offline;
    final statusText = _isPowerOn ? 'On' : 'Off';
    final tempText =
        _currentTemp == 0 ? '--.-°' : '${_currentTemp.toStringAsFixed(1)}°';
    final humText = _humidity == 0 ? '--%' : '${_humidity.toStringAsFixed(1)}%';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: isDark ? AppColors.dividerDark : AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Status: $statusText',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    tempText,
                    style: GoogleFonts.outfit(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.water_drop_rounded,
                        color: AppColors.coolBlue,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        humText,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: subtitleColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(
              color: isDark ? AppColors.dividerDark : AppColors.divider,
              height: 1),
          const SizedBox(height: 12),
          _buildConnectivityRow(isDark),
        ],
      ),
    );
  }

  void _showWifiNamePopup() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return WifiManagementDialog(
          mqtt: _mqtt,
          initialSsid: _wifiSsid,
          onWifiConfigured: (ssid, password) {
            setState(() {
              _isReconnectingWifi = true;
              _reconnectingWifiSsid = ssid;
            });
            _reconnectingWifiTimeoutTimer?.cancel();
            _reconnectingWifiTimeoutTimer = Timer(const Duration(seconds: 45), () {
              if (mounted && _isReconnectingWifi) {
                setState(() {
                  _isReconnectingWifi = false;
                });
                _showSnack(
                  'WiFi connection timed out. Please check device connection.',
                  AppColors.offline,
                );
              }
            });
          },
        );
      },
    );
  }

  Widget _buildConnectivityRow(bool isDark) {
    final isBluetooth = _mqtt.isBluetoothConnected;
    final isDeviceOnline = _isActive || isBluetooth;
    final dotColor = isDeviceOnline ? AppColors.online : AppColors.offline;
    final connText = isBluetooth
        ? 'Bluetooth Connected'
        : (isDeviceOnline ? 'Connected' : 'OFFLINE');
    final iconData = isBluetooth ? Icons.bluetooth : Icons.wifi;
    final iconColor = isBluetooth
        ? Colors.blue
        : (isDeviceOnline ? AppColors.online : AppColors.offline);

    return GestureDetector(
      onTap: () {
        if (!isDeviceOnline) {
          // Navigate to BluetoothScannerPage to connect
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const BluetoothScannerPage(returnConnection: true),
            ),
          ).then((value) {
            if (value == true && mounted) {
              setState(() {});
            }
          });
        } else {
          _showWifiNamePopup();
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, color: iconColor, size: 22),
          const SizedBox(width: 8),
          Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            connText,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          if (!isDeviceOnline) ...[
            const SizedBox(width: 8),
            Text(
              '(Tap to connect BT)',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.blueAccent,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAirQualityMetrics(
      Color cardColor, Color textColor, Color subtitleColor, bool isDark) {
    return Row(
      children: [
        _buildAirMetricCard(
          icon: Icons.air_rounded,
          title: 'TVOC',
          value: '$_tvoc ppb',
          accentColor: const Color(0xFFE11D48),
          bgLight: const Color(0xFFFFF1F2),
          bgDark: const Color(0xFF881337),
          borderLight: const Color(0xFFFECDD3),
          borderDark: const Color(0xFF9F1239),
          activeSegments: 3,
          isDark: isDark,
        ),
        const SizedBox(width: 12),
        _buildAirMetricCard(
          icon: Icons.co2_rounded,
          title: 'CO₂',
          value: '$_co2 ppm',
          accentColor: const Color(0xFFD97706),
          bgLight: const Color(0xFFFFFBEB),
          bgDark: const Color(0xFF78350F),
          borderLight: const Color(0xFFFEF3C7),
          borderDark: const Color(0xFFB45309),
          activeSegments: 4,
          isDark: isDark,
        ),
        const SizedBox(width: 12),
        _buildAirMetricCard(
          icon: Icons.eco_rounded,
          title: 'AQI',
          value: '$_aqi',
          accentColor: const Color(0xFF65A30D),
          bgLight: const Color(0xFFF7FEE7),
          bgDark: const Color(0xFF3F6212),
          borderLight: const Color(0xFFECFCCB),
          borderDark: const Color(0xFF4D7C0F),
          activeSegments: 3,
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildAirMetricCard({
    required IconData icon,
    required String title,
    required String value,
    required Color accentColor,
    required Color bgLight,
    required Color bgDark,
    required Color borderLight,
    required Color borderDark,
    required int activeSegments,
    required bool isDark,
  }) {
    final bg = isDark ? bgDark.withOpacity(0.15) : bgLight;
    final borderCol = isDark ? borderDark.withOpacity(0.4) : borderLight;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderCol, width: 1),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: accentColor, size: 16),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white38 : Colors.black45,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                  5,
                  (index) => Container(
                        width: 12,
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          color: index < activeSegments
                              ? accentColor
                              : accentColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentModeBanner(Color textColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.ac_unit_rounded, color: AppColors.coolBlue, size: 16),
        const SizedBox(width: 6),
        Text(
          _mode,
          style: GoogleFonts.inter(
            color: textColor.withOpacity(0.7),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 20),
        RotationTransition(
          turns: _fanRotationCtrl,
          child: Image.asset(
            'assets/images/fan.png',
            width: 16,
            height: 16,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _fanSpeed,
          style: GoogleFonts.inter(
            color: textColor.withOpacity(0.7),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildTemperatureDialRow(Color textColor, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildDialButton(Icons.remove, _decrementTemp, textColor, isDark),
        const SizedBox(width: 20),
        _buildTempDial(textColor, isDark),
        const SizedBox(width: 20),
        _buildDialButton(Icons.add, _incrementTemp, textColor, isDark),
      ],
    );
  }

  Widget _buildTempDial(Color textColor, bool isDark) {
    final color = _isPowerOn ? AppColors.coolBlue : AppColors.textHint;
    return GestureDetector(
      onTap: _togglePower,
      child: Container(
        width: 170,
        height: 170,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? AppColors.surfaceDark : Colors.white,
          border: Border.all(
            color: color.withOpacity(0.12),
            width: 6,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.10),
              blurRadius: 24,
              spreadRadius: 4,
            ),
            BoxShadow(
              color: isDark ? Colors.black38 : Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$_setTemp°',
              style: GoogleFonts.outfit(
                fontSize: 56,
                fontWeight: FontWeight.w800,
                color: textColor,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _isPowerOn ? 'TURN OFF' : 'TURN ON',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _isPowerOn ? AppColors.primary : AppColors.offline,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialButton(
      IconData icon, VoidCallback onTap, Color textColor, bool isDark) {
    final bool isEnabled = _isControlAvailable && _isPowerOn;
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? AppColors.surfaceDark : Colors.white,
          border: Border.all(
              color: isDark ? AppColors.dividerDark : AppColors.divider,
              width: 1),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black26 : Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: isEnabled ? AppColors.primary : AppColors.textHint,
          size: 22,
        ),
      ),
    );
  }

  Widget _buildActionGrid(Color cardColor, Color textColor, bool isDark) {
    return Row(
      children: [
        _buildActionItem(
          icon: Icons.ac_unit_rounded,
          label: 'Mode',
          value: _mode,
          activeColor: AppColors.coolBlue,
          activeBg: const Color(0xFFEFF6FF),
          isActive: _isPowerOn,
          onTap: _cycleMode,
          cardColor: cardColor,
          textColor: textColor,
          isDark: isDark,
        ),
        const SizedBox(width: 8),
        _buildActionItem(
          icon: Icons.mode_fan_off_rounded,
          label: 'Fan',
          value: _fanSpeed,
          activeColor: AppColors.primary,
          activeBg: const Color(0xFFECFDF5),
          isActive: _isPowerOn,
          onTap: _cycleFanSpeed,
          cardColor: cardColor,
          textColor: textColor,
          isDark: isDark,
          customIcon: RotationTransition(
            turns: _fanRotationCtrl,
            child: Image.asset(
              'assets/images/fan.png',
              width: 22,
              height: 22,
              color: (_isPowerOn && _isControlAvailable)
                  ? AppColors.primary
                  : AppColors.textHint,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _buildActionItem(
          icon: Icons.lightbulb_rounded,
          label: 'Light',
          value: _lightOn ? 'On' : 'Off',
          activeColor: AppColors.warning,
          activeBg: const Color(0xFFFEFCE8),
          isActive: _isPowerOn && _lightOn,
          onTap: _toggleLight,
          cardColor: cardColor,
          textColor: textColor,
          isDark: isDark,
        ),
        const SizedBox(width: 8),
        _buildActionItem(
          icon: Icons.swap_vert_rounded,
          label: 'Swing',
          value: _swingV ? 'On' : 'Off',
          activeColor: AppColors.fanPurple,
          activeBg: const Color(0xFFF5F3FF),
          isActive: _isPowerOn && _swingV,
          onTap: _toggleSwingV,
          cardColor: cardColor,
          textColor: textColor,
          isDark: isDark,
        ),
        const SizedBox(width: 8),
        _buildActionItem(
          icon: Icons.swap_horiz_rounded,
          label: 'Swing',
          value: _swingH ? 'On' : 'Off',
          activeColor: AppColors.fanPurple,
          activeBg: const Color(0xFFF5F3FF),
          isActive: _isPowerOn && _swingH,
          onTap: _toggleSwingH,
          cardColor: cardColor,
          textColor: textColor,
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required String label,
    required String value,
    required Color activeColor,
    required Color activeBg,
    required bool isActive,
    required VoidCallback onTap,
    required Color cardColor,
    required Color textColor,
    required bool isDark,
    Widget? customIcon,
  }) {
    final bool isInteractable = _isControlAvailable && _isPowerOn;
    final bg = (isActive && isInteractable)
        ? (isDark ? activeColor.withOpacity(0.12) : activeBg)
        : cardColor;
    final borderCol = (isActive && isInteractable)
        ? activeColor.withOpacity(0.3)
        : (isDark ? AppColors.dividerDark : AppColors.divider);

    return Expanded(
      child: GestureDetector(
        onTap: isInteractable ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderCol, width: 1.2),
            boxShadow: [
              if (isActive && isInteractable)
                BoxShadow(
                  color: activeColor.withOpacity(isDark ? 0.1 : 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              customIcon ??
                  Icon(icon,
                      color: (isActive && isInteractable)
                          ? activeColor
                          : AppColors.textHint,
                      size: 22),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: (isActive && isInteractable)
                      ? activeColor
                      : AppColors.textHint,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomQuickActions(Color textColor, bool isDark) {
    return Row(
      children: [
        _buildBottomActionItem(
          icon: Icons.timer_outlined,
          label: 'Timer',
          color: AppColors.coolBlue,
          bg: isDark
              ? AppColors.coolBlue.withOpacity(0.12)
              : const Color(0xFFEFF6FF),
          onTap: () => _showTimerDialog(context, isDark),
          isDark: isDark,
        ),
        const SizedBox(width: 12),
        _buildBottomActionItem(
          icon: Icons.calendar_month_outlined,
          label: 'Schedule',
          color: AppColors.primary,
          bg: isDark
              ? AppColors.primary.withOpacity(0.12)
              : const Color(0xFFECFDF5),
          onTap: () => _showSchedulesSheet(context, isDark),
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildBottomActionItem({
    required IconData icon,
    required String label,
    required Color color,
    required Color bg,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.2), width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
