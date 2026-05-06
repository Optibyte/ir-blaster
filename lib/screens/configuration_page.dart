import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bluetooth_scanner_page.dart';
import 'widgets/ac_control_widget.dart';
import 'widgets/temperature_widget.dart';
import 'widgets/wifi_section_widget.dart';

class ConfigurationPage extends StatefulWidget {
  final BluetoothConnection connection;
  final BluetoothDevice device;

  const ConfigurationPage({
    super.key,
    required this.connection,
    required this.device,
  });

  @override
  State<ConfigurationPage> createState() => _ConfigurationPageState();
}

class _ConfigurationPageState extends State<ConfigurationPage> {
  late BluetoothConnection _connection;
  late BluetoothDevice _device;

  // ====== Theme ======
  static const Color _themeGreen = Color.fromARGB(255, 123, 159, 71);
  static const Color _background = Color(0xFF1A1A2E);
  static const Color _cardBackground = Color(0xFF2D2D44);
  static const Color _green = Color.fromARGB(255, 123, 159, 71);
  static const Color _red = Colors.red;
  static const Color _orange = Colors.orange;
  static const Color _blue = Colors.blue;

  // ====== India AC brands list (dropdown master list) ======
  // (You can add/remove brands any time. This is only for UI dropdown choices.)
  static const List<String> kIndianAcBrands = [
    // Top / common
    "Samsung",
    "LG",
    "Voltas",
    "Daikin",
    "Blue Star",
    "Hitachi",
    "Panasonic",
    "Carrier",
    "Lloyd",
    "Godrej",
    "Whirlpool",
    "Haier",

    // Mid / also common
    "Toshiba",
    "Mitsubishi Electric",
    "Mitsubishi Heavy Industries",
    "O General",
    "General",
    "Fujitsu",
    "Trane",
    "York",
    "Hisense",
    "Sharp",
    "AUX",
    "Gree",
    "TCL",

    // India-focused / budget
    "Onida",
    "Sansui",
    "IFB",
    "Electrolux",
    "Kelvinator",
    "Videocon",
    "BPL",
    "Intex",
    "Micromax",
    "Karbonn",

    // Retail / private labels
    "Croma",
    "MarQ (Flipkart)",
    "Thomson",
    "Sanyo",
    "Midea",
  ];

  // ====== Connection Flags ======
  bool _isConnected = false;
  bool _isWifiConnected = false;
  bool _isGreenLedOn = false;
  bool _isYellowLedOn = false;
  bool _isBluetoothOn = false;
  String _lastDisconnectReason = "N/A";
  String _lastDisconnectTime = "N/A";
  Timer? _bluetoothStateTimer;

  // ====== WiFi Info ======
  String _wifiIP = "";
  String _wifiStatus = "WiFi not connected";
  bool _isConnectingWifi = false;
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _wifiPasswordController = TextEditingController();

  // ====== Temp / RTC ======
  String _temperatureText = "--";
  String _deviceTimeText = "--";

  // ====== Terminal ======
  bool _showTerminal = true;
  final TextEditingController _terminalController = TextEditingController();
  String _incomingBuffer = "";
  bool _needsUpdate = false;

  // ===================== MQTT =====================
  bool _showMqttDropdown = false;
  bool _isMqttConnected = false;
  String _mqttStatus = "MQTT not connected";

  final TextEditingController _mqttHostController = TextEditingController(text: "13.66.130.236");
  final TextEditingController _mqttPortController = TextEditingController(text: "1883");
  final TextEditingController _mqttUserController = TextEditingController(text: "testir");
  final TextEditingController _mqttPassController = TextEditingController(text: "ir@123");
  final TextEditingController _mqttTopicController = TextEditingController(text: "sustainabyte/testir/control");

  // ===================== Auto control =====================
  bool _autoControlEnabled = false;
  final TextEditingController _autoOnController = TextEditingController(text: "28");
  final TextEditingController _autoOffController = TextEditingController(text: "25");

  // ===================== AC Remote dropdowns =====================

  // 1) DEFAULT REMOTE dropdown (hardcoded / default send)
  bool _showDefaultRemoteDropdown = true;
  String _defaultRemoteBrand = "Samsung"; // default remote brand selector (still no brand in title)

  // 2) REMOTE CONFIG dropdown (learning + save)
  bool _showRemoteConfigDropdown = true;
  String _configBrand = "LG"; // brand chosen for learning
  bool _configMode = false;

  // Config step tracking
  static const List<String> _cfgKeys = [
    "POWER_ON",
    "TEMPUP",
    "TEMPDOWN",
    "SWING",
    "MODE",
    "POWER_OFF",
  ];
  int _cfgStepIndex = 0;
  bool _waitingForIr = false;
  int _learningProgress = 0;
  String _cfgStatus = "Idle";

  // Save remote dialog
  final TextEditingController _saveBrandController = TextEditingController();

  // Schedules (optional)
  final TextEditingController _onTimeController = TextEditingController();
  final TextEditingController _offTimeController = TextEditingController();

  // ===================== Lifecycle =====================
  @override
  void initState() {
    super.initState();
    _connection = widget.connection;
    _device = widget.device;

    _isConnected = _connection.isConnected;
    _isYellowLedOn = _isConnected;

    _loadSavedState();
    _listenBluetooth();
    _startBluetoothStateMonitor();
    
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _connection.isConnected) {
        _sendCommand("GET_TEMP");
        _sendCommand("GET_TIME");
        _sendCommand("GET_WIFI"); // Ask device for actual WiFi status
        
        // Timeout for initial sync
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted && _wifiStatus.contains("Syncing")) {
            setState(() {
              _wifiStatus = "WiFi not connected"; // Fallback if no response
            });
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _bluetoothStateTimer?.cancel();
    _ssidController.dispose();
    _wifiPasswordController.dispose();

    _terminalController.dispose();
    _onTimeController.dispose();
    _offTimeController.dispose();

    _mqttHostController.dispose();
    _mqttPortController.dispose();
    _mqttUserController.dispose();
    _mqttPassController.dispose();
    _mqttTopicController.dispose();

    _autoOnController.dispose();
    _autoOffController.dispose();

    _saveBrandController.dispose();

    super.dispose();
  }

  // ===================== Storage =====================
  Future<void> _loadSavedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      setState(() {
        final wasConnected = prefs.getBool('wifi_connected') ?? false;
        _wifiIP = prefs.getString('wifi_ip') ?? "";
        
        // We start as 'not connected' until the device confirms status
        _isWifiConnected = false; 
        if (wasConnected) {
          _wifiStatus = "Syncing WiFi status... ⏳";
        } else {
          _wifiStatus = "WiFi not connected";
        }

        _defaultRemoteBrand = prefs.getString('default_remote_brand') ?? "Samsung";
        _configBrand = prefs.getString('config_remote_brand') ?? "LG";
      });

      _autoControlEnabled = prefs.getBool('auto_enabled') ?? false;

      final aon = prefs.getDouble('auto_on');
      final aoff = prefs.getDouble('auto_off');
      if (aon != null) _autoOnController.text = aon.toString();
      if (aoff != null) _autoOffController.text = aoff.toString();

      // MQTT saved
      final h = prefs.getString('mqtt_host');
      final p = prefs.getInt('mqtt_port');
      final u = prefs.getString('mqtt_user');
      final pw = prefs.getString('mqtt_pass');
      final t = prefs.getString('mqtt_topic');

      if (h != null && h.isNotEmpty) _mqttHostController.text = h;
      if (p != null && p > 0) _mqttPortController.text = p.toString();
      if (u != null) _mqttUserController.text = u;
      if (pw != null) _mqttPassController.text = pw;
      if (t != null && t.isNotEmpty) _mqttTopicController.text = t;
    } catch (_) {}
  }

  Future<void> _saveWifiStatus(bool connected, {String ip = ""}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('wifi_connected', connected);
      await prefs.setString('wifi_ip', ip);
    } catch (_) {}
  }

  Future<void> _saveMqttPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mqtt_host', _mqttHostController.text.trim());
      await prefs.setInt('mqtt_port', int.tryParse(_mqttPortController.text.trim()) ?? 1883);
      await prefs.setString('mqtt_user', _mqttUserController.text.trim());
      await prefs.setString('mqtt_pass', _mqttPassController.text);
      await prefs.setString('mqtt_topic', _mqttTopicController.text.trim());
    } catch (_) {}
  }

  Future<void> _saveAutoPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_enabled', _autoControlEnabled);
      await prefs.setDouble('auto_on', double.tryParse(_autoOnController.text.trim()) ?? 28.0);
      await prefs.setDouble('auto_off', double.tryParse(_autoOffController.text.trim()) ?? 25.0);
    } catch (_) {}
  }

  Future<void> _saveDefaultBrand() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('default_remote_brand', _defaultRemoteBrand);
    } catch (_) {}
  }

  Future<void> _saveConfigBrand() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('config_remote_brand', _configBrand);
    } catch (_) {}
  }

  void _startBluetoothStateMonitor() {
    _updateBluetoothState();
    _bluetoothStateTimer?.cancel();
    _bluetoothStateTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _updateBluetoothState(),
    );
  }

  Future<void> _updateBluetoothState() async {
    try {
      final isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
      if (!mounted) return;
      setState(() => _isBluetoothOn = isEnabled ?? false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isBluetoothOn = false);
    }
  }

  void _recordDisconnect(String reason) {
    final time = DateFormat("yyyy-MM-dd HH:mm:ss").format(DateTime.now());
    setState(() {
      _isConnected = false;
      _isYellowLedOn = false;
      _lastDisconnectReason = reason;
      _lastDisconnectTime = time;
    });
    _log("BT disconnected: $reason @ $time");
    _showReconnectDialog();
  }

  String _disconnectHint(String reason) {
    final r = reason.toLowerCase();
    if (r.contains("remote")) {
      return "Device closed the link (idle timeout or reboot)";
    }
    if (r.contains("error")) {
      return "Bluetooth stack error (signal or OS)";
    }
    return "Unknown cause";
  }

  String _disconnectDisplayReason(String reason) {
    if (reason.toLowerCase().contains("remote")) {
      return "Device closed the connection";
    }
    return reason;
  }

  // ===================== BT Rx =====================
  void _listenBluetooth() {
    _connection.input?.listen((Uint8List data) {
      final chunk = String.fromCharCodes(data);
      _log("RX: $chunk");
      _incomingBuffer += chunk;

      String line;
      while ((line = _extractLine()) != "") {
        _handleLine(line.trim());
      }
    }, onError: (error) {
      if (!mounted) return;
      _recordDisconnect("Error: $error");
    }).onDone(() {
      if (!mounted) return;
      _recordDisconnect("Disconnected by remote");
    });
  }

  String _extractLine() {
    if (_incomingBuffer.isEmpty) return "";
    final nIdx = _incomingBuffer.indexOf('\n');
    final rIdx = _incomingBuffer.indexOf('\r');

    if (nIdx == -1 && rIdx == -1) return "";
    int idx;
    if (nIdx == -1) {
      idx = rIdx;
    } else if (rIdx == -1) {
      idx = nIdx;
    } else {
      idx = (nIdx < rIdx) ? nIdx : rIdx;
    }

    final line = _incomingBuffer.substring(0, idx);
    int cut = idx + 1;
    if (idx + 1 < _incomingBuffer.length) {
      final a = _incomingBuffer[idx];
      final b = _incomingBuffer[idx + 1];
      if (a == '\r' && b == '\n') cut = idx + 2;
    }
    _incomingBuffer = _incomingBuffer.substring(cut);
    return line;
  }

  void _handleLine(String line) {
    if (line.isEmpty) return;

    // WiFi
    if (line.startsWith("WIFI_CONNECTED:")) {
      final ip = line.replaceFirst("WIFI_CONNECTED:", "").trim();
      setState(() {
        _isWifiConnected = true;
        _isConnectingWifi = false;
        _wifiIP = ip;
        _wifiStatus = "WiFi connected: $ip";
        _isGreenLedOn = true;
        _showMqttDropdown = true;
      });
      _saveWifiStatus(true, ip: ip);
      _hideWifiLoadingDialog();
      _showSnack("WiFi connected ✅", _green);
      // auto connect mqtt if values exist
      _sendMqttSettingsToDevice(connect: true);
      return;
    }
    if (line.toLowerCase().contains("wifi_failed") || line.toLowerCase().contains("wifi failed")) {
      _hideWifiLoadingDialog();
      setState(() {
        _isWifiConnected = false;
        _isConnectingWifi = false;
        _wifiIP = "";
        _wifiStatus = "WiFi connection failed ❌";
        _isGreenLedOn = false;

        _isMqttConnected = false;
        _mqttStatus = "MQTT not connected";
      });
      _saveWifiStatus(false, ip: "");
      _showSnack("WiFi connection failed ❌", _red);
      return;
    }

    // Status check response (custom handling for initial sync)
    if (line.contains("WIFI_STATUS:") || line.contains("WIFI_STATE:")) {
      final status = line.split(":").last.trim();
      final parts = status.split(",");
      final isConn = parts[0] == "1" || parts[0].toLowerCase() == "true" || parts[0].toLowerCase() == "connected";
      final ip = parts.length > 1 ? parts[1] : "";
      
      if (isConn) _hideWifiLoadingDialog();
      setState(() {
        _isWifiConnected = isConn;
        _wifiIP = ip;
        _wifiStatus = isConn ? "WiFi connected: $ip" : "WiFi not connected";
        _isGreenLedOn = isConn;
        if (isConn) _isConnectingWifi = false;
      });
      _saveWifiStatus(isConn, ip: ip);
      return;
    }

    // Generic "connected" check if device uses non-standard format or prefixes
    if (line.toLowerCase().contains("wifi connected") || 
        line.toLowerCase().contains("connected to wifi") ||
        line.toLowerCase().contains("status_online") ||
        line.toLowerCase().contains("wifi_connected")) {
      
      _hideWifiLoadingDialog();
      setState(() {
        _isWifiConnected = true;
        _isConnectingWifi = false;
        _wifiStatus = "WiFi Connected ✅";
        _isGreenLedOn = true;
        _showMqttDropdown = true;
        
        // If the line contains an IP (e.g. "WIFI_CONNECTED:192.168.1.5")
        if (line.contains(":")) {
          final parts = line.split(":");
          for (var part in parts) {
            final trimmed = part.trim();
            if (RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(trimmed)) {
              _wifiIP = trimmed;
              _wifiStatus = "WiFi Connected: $trimmed";
              break;
            }
          }
        }
      });
      _saveWifiStatus(true, ip: _wifiIP);
      return;
    }

    // MQTT
    if (line.startsWith("MQTT_CONNECTED") || line.contains("STATUS_ONLINE")) {
      setState(() {
        _isMqttConnected = true;
        _mqttStatus = "MQTT connected ✅";
      });
      return;
    }
    if (line.startsWith("MQTT_FAILED")) {
      setState(() {
        _isMqttConnected = false;
        _mqttStatus = "MQTT failed ❌";
      });
      return;
    }
    if (line.startsWith("MQTT_PUB_OK")) {
      setState(() => _mqttStatus = "MQTT published ✅");
      return;
    }

    // Temp/Time
    if (line.startsWith("TEMP:")) {
      setState(() => _temperatureText = line.replaceFirst("TEMP:", "").trim());
      return;
    }
    if (line.startsWith("TIME:")) {
      final v = line.replaceFirst("TIME:", "").trim();
      if (v.isNotEmpty) setState(() => _deviceTimeText = v);
      return;
    }

    // ====== Remote config progress from ESP32 ======
    if (line.startsWith("APP_CFG:WAIT:")) {
      // example: APP_CFG:WAIT:POWER_ON
      final k = line.replaceFirst("APP_CFG:WAIT:", "").trim();
      setState(() {
        _waitingForIr = true;
        _cfgStatus = "Waiting IR for $k ...";
        _learningProgress = 0;
      });
      return;
    }
    if (line.startsWith("IR_LEARNING_PROGRESS:")) {
      final p = int.tryParse(line.replaceFirst("IR_LEARNING_PROGRESS:", "").trim()) ?? 0;
      setState(() {
        _learningProgress = p.clamp(0, 100);
      });
      return;
    }
    if (line.startsWith("APP_CFG:DONE:")) {
      // example: APP_CFG:DONE:POWER_ON
      final k = line.replaceFirst("APP_CFG:DONE:", "").trim();
      setState(() {
        _waitingForIr = false;
        _cfgStatus = "Captured: $k ✅";
        _learningProgress = 100;
      });

      // move to next step (auto)
      _nextConfigStep();
      return;
    }

    // Remote saved
    if (line.startsWith("REMOTE_SAVED:")) {
      final b = line.replaceFirst("REMOTE_SAVED:", "").trim();
      setState(() {
        _cfgStatus = "Remote Saved: $b ✅";
        _configMode = false;
        _waitingForIr = false;
        _cfgStepIndex = 0;
      });
      _showSnack("Remote saved: $b", _green);
      return;
    }

    // IR_SENT confirmation (default remote)
    if (line.startsWith("IR_SENT")) {
      _showSnack("IR sent ✅", _green);
      return;
    }

    if (line.startsWith("ERR:")) {
      // if timeout during learning, stop waiting
      if (line.contains("TIMEOUT")) {
        setState(() {
          _waitingForIr = false;
          _cfgStatus = "Timeout ❌ Try again";
          _learningProgress = 0;
        });
      }
      _log("DEVICE ERROR: $line");
      return;
    }
  }

  // ===================== Commands =====================
  Future<void> _sendCommand(String cmd) async {
    if (!_connection.isConnected) {
      _showSnack("Bluetooth not connected", _red);
      return;
    }
    try {
      _log("TX: $cmd");
      _connection.output.add(Uint8List.fromList(utf8.encode("$cmd\r\n"))); // Using \r\n for better compatibility
      await _connection.output.allSent;
    } catch (e) {
      _showSnack("Send failed: $e", _red);
    }
  }

  // ===================== WiFi =====================
  void _showWifiSetupDialog() {
    // Check if Bluetooth is connected
    if (!_isConnected) {
      _showSnack("Bluetooth not connected. Please connect first.", _red);
      return;
    }
    
    bool passwordVisible = false;
    
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _cardBackground,
          title: const Text("WiFi Setup", style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _ssidController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: "SSID",
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _wifiPasswordController,
                obscureText: !passwordVisible,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Password",
                  labelStyle: const TextStyle(color: Colors.white70),
                  border: const OutlineInputBorder(),
                  enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                  suffixIcon: IconButton(
                    icon: Icon(
                      passwordVisible ? Icons.visibility : Icons.visibility_off,
                      color: Colors.white70,
                    ),
                    onPressed: () {
                      setDialogState(() {
                        passwordVisible = !passwordVisible;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white70))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _themeGreen, foregroundColor: Colors.black),
              onPressed: () {
                Navigator.pop(context);
                _connectWifi();
              },
              child: const Text("Send"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connectWifi() async {
    final ssid = _ssidController.text.trim();
    final pass = _wifiPasswordController.text.trim();
    if (ssid.isEmpty || pass.isEmpty) {
      _showSnack("Enter SSID and password", _red);
      return;
    }
    setState(() {
      _isWifiConnected = false; 
      _wifiStatus = "Connecting to WiFi...";
      _isConnectingWifi = true;
    });

    // Send multiple variants to ensure compatibility with different firmware versions
    await _sendCommand("WIFI:$ssid,$pass");
    await Future.delayed(const Duration(milliseconds: 300));
    await _sendCommand("WIFI_CONNECT"); 
    await Future.delayed(const Duration(milliseconds: 300));
    await _sendCommand("WIFI_START");
    
    _showWifiLoadingDialog();
    
    // Auto-dismiss loading dialog after 30 seconds if no response from device
    // Extended timeout for slow ESP32 WiFi connections
    Future.delayed(const Duration(seconds: 60), () {
      if (_isConnectingWifi && mounted) {
        _hideWifiLoadingDialog();
        setState(() {
          _isConnectingWifi = false;
          _wifiStatus = "WiFi connection timeout ⏳";
        });
        _showSnack("WiFi connection timeout. Check device.", _orange);
      }
    });
  }

  // ===================== MQTT =====================
  Future<void> _sendMqttSettingsToDevice({bool connect = false}) async {
    if (!_isWifiConnected) return;

    final host = _mqttHostController.text.trim();
    final port = int.tryParse(_mqttPortController.text.trim()) ?? 1883;
    final user = _mqttUserController.text.trim();
    final pass = _mqttPassController.text;
    final topic = _mqttTopicController.text.trim();

    if (host.isEmpty || topic.isEmpty) return;

    await _saveMqttPrefs();

    await _sendCommand("MQTT_HOST:$host");
    await _sendCommand("MQTT_PORT:$port");
    await _sendCommand("MQTT_USER:$user");
    await _sendCommand("MQTT_PASS:$pass");
    await _sendCommand("MQTT_TOPIC:$topic");

    if (connect) {
      await _sendCommand("MQTT_CONNECT");
    }
  }

  // ===================== Auto control =====================
  Future<void> _sendAutoSetpointsToDevice() async {
    final onV = double.tryParse(_autoOnController.text.trim());
    final offV = double.tryParse(_autoOffController.text.trim());
    if (onV == null || offV == null) {
      _showSnack("Enter valid setpoints", _red);
      return;
    }
    await _saveAutoPrefs();

    if (_autoControlEnabled) {
      await _sendCommand("AUTO_CFG:${onV.toStringAsFixed(1)},${offV.toStringAsFixed(1)},1");
      _showSnack("Auto enabled ✅", _green);
    } else {
      await _sendCommand("AUTO_DISABLE");
      _showSnack("Auto disabled", _orange);
    }
  }

  // ===================== Brand Dropdown Helpers =====================
  List<String> _brandDropdownItems() {
    final combined = <String>[...kIndianAcBrands];
    final seen = <String>{};
    final out = <String>[];

    for (final b in combined) {
      final name = b.trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      if (seen.add(key)) out.add(name);
    }

    // keep Samsung always present
    if (!out.any((x) => x.toLowerCase() == "samsung")) out.insert(0, "Samsung");
    return out;
  }

  // ===================== DEFAULT REMOTE dropdown actions =====================
  Future<void> _setDefaultBrandOnDevice(String brand) async {
    final clean = brand.trim();
    if (clean.isEmpty) return;

    setState(() => _defaultRemoteBrand = clean);
    await _saveDefaultBrand();

    // set brand for sending
    await _sendCommand("BRAND:$clean");
  }

  Future<void> _sendDefaultRemoteKey(String key) async {
    // will use:
    // 1) spiffs learned raw for current brand
    // 2) hardcoded raw fallback
    // 3) protocol fallback
    await _sendCommand("SEND:$key");
  }

  // ===================== REMOTE CONFIG dropdown actions =====================
  Future<void> _setConfigBrandOnDevice(String brand) async {
    final clean = brand.trim();
    if (clean.isEmpty) return;

    setState(() => _configBrand = clean);
    await _saveConfigBrand();

    // only set brand; config starts when user clicks START CONFIG
    await _sendCommand("BRAND:$clean");
  }

  Future<void> _startConfigMode() async {
    // IMPORTANT: Your firmware needs START_CONFIG first, then BRAND, then CONFIG:key
    await _sendCommand("START_CONFIG");
    await _sendCommand("BRAND:$_configBrand");

    setState(() {
      _configMode = true;
      _cfgStepIndex = 0;
      _waitingForIr = false;
      _learningProgress = 0;
      _cfgStatus = "Config mode started ✅";
    });

    // start first step automatically
    await _triggerCurrentKeyConfig();
  }

  Future<void> _triggerCurrentKeyConfig() async {
    if (!_configMode) return;
    if (_cfgStepIndex < 0 || _cfgStepIndex >= _cfgKeys.length) return;

    final key = _cfgKeys[_cfgStepIndex];
    setState(() {
      _waitingForIr = true;
      _learningProgress = 0;
      _cfgStatus = "Requesting IR for $key ...";
    });

    await _sendCommand("CONFIG:$key");
  }

  void _nextConfigStep() {
    if (!_configMode) return;

    if (_cfgStepIndex < _cfgKeys.length - 1) {
      setState(() {
        _cfgStepIndex++;
        _waitingForIr = false;
        _learningProgress = 0;
      });
      // ask next key
      _triggerCurrentKeyConfig();
    } else {
      // all done -> show save dialog
      setState(() {
        _waitingForIr = false;
        _cfgStatus = "All keys captured ✅. Save Remote now.";
      });
      _showSaveRemoteDialog();
    }
  }

  void _showSaveRemoteDialog() {
    _saveBrandController.text = _configBrand;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Save Remote"),
        content: TextField(
          controller: _saveBrandController,
          decoration: const InputDecoration(
            labelText: "Brand name to save",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _saveRemoteToDevice();
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  Future<void> _saveRemoteToDevice() async {
    final name = _saveBrandController.text.trim();
    if (name.isEmpty) {
      _showSnack("Enter brand name", _red);
      return;
    }
    await _sendCommand("SAVE_REMOTE:$name");
  }

  // ===================== Scheduling =====================
  Future<void> _pickTime(TextEditingController controller, String cmdPrefix) async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: now);
    if (picked == null) return;

    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    final timeStr = "$hh:$mm";
    setState(() => controller.text = timeStr);
    await _sendCommand("$cmdPrefix:$timeStr");
  }

  // ===================== UI =====================
  Widget _buildStatusCard() {
    final title = _isConnected ? "Connected: ${_device.name ?? 'Device'}" : "Bluetooth not connected";
    return Card(
      color: _cardBackground,
      elevation: 2,
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(_isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled, color: _isConnected ? _blue : _red),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(
                    "Mobile Bluetooth: ${_isBluetoothOn ? 'ON' : 'OFF'}",
                    style: TextStyle(fontSize: 12, color: _isBluetoothOn ? _green : _red),
                  ),
                  const Text(
                    "Status: Active",
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(children: [
                  Icon(Icons.circle, size: 12, color: _isYellowLedOn ? Colors.yellow : Colors.grey),
                  const SizedBox(width: 4),
                  const Text("BT", style: TextStyle(color: Colors.white)),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.circle, size: 12, color: _isGreenLedOn ? _themeGreen : Colors.grey),
                  const SizedBox(width: 4),
                  const Text("WiFi", style: TextStyle(color: Colors.white)),
                ]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTerminal() {
    if (!_showTerminal) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => setState(() => _showTerminal = true),
          icon: const Icon(Icons.developer_mode, color: Colors.white70),
          label: const Text("Show Logs", style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    return Card(
      color: _cardBackground,
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(child: Text("Terminal / Logs", style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white))),
                IconButton(onPressed: () => setState(() => _showTerminal = false), icon: const Icon(Icons.close, color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 160,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
              child: SingleChildScrollView(
                reverse: true,
                child: Text(
                  _terminalController.text,
                  style: const TextStyle(fontFamily: 'monospace', color: _themeGreen, fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== Helpers =====================
  void _log(String msg) {
    final t = DateFormat("HH:mm:ss").format(DateTime.now());
    _terminalController.text += "[$t] $msg\n";
    
    // Throttle UI updates for logs if they come in too fast
    if (!_needsUpdate) {
      _needsUpdate = true;
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _needsUpdate) {
          setState(() {
            _needsUpdate = false;
          });
        }
      });
    }
  }

  void _showSnack(String msg, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: c));
  }

  void _showWifiLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: _cardBackground,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
              BoxShadow(
                color: _themeGreen.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 0),
              ),
            ],
          ),
          child: Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(_themeGreen),
              strokeWidth: 4.5,
              strokeCap: StrokeCap.round,
            ),
          ),
        ),
      ),
    );
  }

  void _hideWifiLoadingDialog() {
    if (_isConnectingWifi && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      setState(() => _isConnectingWifi = false);
    }
  }

  void _showReconnectDialog() {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(Icons.bluetooth_disabled, color: _red, size: 28),
            const SizedBox(width: 12),
            const Text(
              "Bluetooth Disconnected",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Connection to ${_device.name ?? 'device'} lost.\nReason: ${_disconnectDisplayReason(_lastDisconnectReason)}\nTime: $_lastDisconnectTime",
              style: const TextStyle(fontSize: 15, color: Colors.white70),
            ),
            const SizedBox(height: 4),
            Text(
              "Hint: ${_disconnectHint(_lastDisconnectReason)}",
              style: const TextStyle(fontSize: 12, color: Colors.white54, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _themeGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _themeGreen.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white70, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Device is still on. Ready to reconnect.",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _disconnectBluetooth();
            },
            child: const Text(
              "Go Back",
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _themeGreen,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onPressed: () {
              Navigator.pop(context);
              _attemptReconnect();
            },
            icon: const Icon(Icons.bluetooth_connected, size: 20),
            label: const Text(
              "Reconnect",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _attemptReconnect() async {
    _showLoadingDialog("Reconnecting...");
    
    try {
      final connection = await BluetoothConnection.toAddress(_device.address);
      if (connection.isConnected && mounted) {
        _hideLoadingDialog();
        setState(() {
          _connection = connection;
          _isConnected = true;
          _isYellowLedOn = true;
        });
        _listenBluetooth();
        _showSnack("Reconnected successfully ✅", _green);
      }
    } catch (e) {
      if (mounted) {
        _hideLoadingDialog();
        _showSnack("Failed to reconnect. Try again.", _red);
      }
    }
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: _cardBackground,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
              BoxShadow(
                color: _themeGreen.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 0),
              ),
            ],
          ),
          child: Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(_themeGreen),
              strokeWidth: 4.5,
              strokeCap: StrokeCap.round,
            ),
          ),
        ),
      ),
    );
  }

  void _hideLoadingDialog() {
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _disconnectBluetooth() {
    if (_connection.isConnected) _connection.close();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const BluetoothScannerPage()),
      (_) => false,
    );
  }

  // ===================== Build =====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text("Configuration", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        backgroundColor: _themeGreen,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.bluetooth_disabled), onPressed: _disconnectBluetooth),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            RepaintBoundary(child: _buildStatusCard()),
            RepaintBoundary(
              child: WifiSectionWidget(
              themeGreen: _themeGreen,
              isWifiConnected: _isWifiConnected,
              wifiStatus: _wifiStatus,
              wifiIP: _wifiIP,
              onShowWifiSetup: _showWifiSetupDialog,
              showMqttDropdown: _showMqttDropdown,
              onToggleMqttDropdown: () => setState(() => _showMqttDropdown = !_showMqttDropdown),
              mqttStatus: _mqttStatus,
              isMqttConnected: _isMqttConnected,
              mqttHostController: _mqttHostController,
              mqttPortController: _mqttPortController,
              mqttTopicController: _mqttTopicController,
              mqttUserController: _mqttUserController,
              mqttPassController: _mqttPassController,
              onSendMqttSettings: () => _sendMqttSettingsToDevice(connect: false),
              onConnectMqtt: () => _sendMqttSettingsToDevice(connect: true),
              autoControlEnabled: _autoControlEnabled,
              onAutoControlChanged: (v) async {
                setState(() => _autoControlEnabled = v);
                await _saveAutoPrefs();
                await _sendAutoSetpointsToDevice();
              },
              autoOnController: _autoOnController,
              autoOffController: _autoOffController,
              onApplyAutoConfig: _sendAutoSetpointsToDevice,
            )),
            RepaintBoundary(
              child: TemperatureWidget(
              temperatureText: _temperatureText,
              deviceTimeText: _deviceTimeText,
              onRefreshTemp: () => _sendCommand("GET_TEMP"),
              onRefreshTime: () => _sendCommand("GET_TIME"),
              onSyncTime: () {
                final now = DateTime.now();
                final formatted = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
                setState(() => _deviceTimeText = formatted);
                _sendCommand("SET_TIME:$formatted");
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (mounted) _sendCommand("GET_TIME");
                });
              },
            )),
            RepaintBoundary(
              child: ACControlWidget(
              themeGreen: _themeGreen,
              brandItems: _brandDropdownItems(),
              showDefaultRemoteDropdown: _showDefaultRemoteDropdown,
              onToggleDefaultRemoteDropdown: () =>
                  setState(() => _showDefaultRemoteDropdown = !_showDefaultRemoteDropdown),
              defaultRemoteBrand: _defaultRemoteBrand,
              onDefaultBrandChanged: _setDefaultBrandOnDevice,
              onPowerOn: () => _sendDefaultRemoteKey("POWER_ON"),
              onPowerOff: () => _sendDefaultRemoteKey("POWER_OFF"),
              onTempUp: () => _sendDefaultRemoteKey("TEMPUP"),
              onTempDown: () => _sendDefaultRemoteKey("TEMPDOWN"),
              onSwing: () => _sendDefaultRemoteKey("SWING"),
              onMode: () => _sendDefaultRemoteKey("MODE"),
              onTimeController: _onTimeController,
              offTimeController: _offTimeController,
              onPickOnTime: () => _pickTime(_onTimeController, "SCHEDULE_ON"),
              onPickOffTime: () => _pickTime(_offTimeController, "SCHEDULE_OFF"),
              showRemoteConfigDropdown: _showRemoteConfigDropdown,
              onToggleRemoteConfigDropdown: () =>
                  setState(() => _showRemoteConfigDropdown = !_showRemoteConfigDropdown),
              configBrand: _configBrand,
              onConfigBrandChanged: _setConfigBrandOnDevice,
              configMode: _configMode,
              waitingForIr: _waitingForIr,
              cfgStepIndex: _cfgStepIndex,
              cfgStepsCount: _cfgKeys.length,
              learningProgress: _learningProgress,
              cfgStatus: _cfgStatus,
              currentCfgKey: _cfgKeys[_cfgStepIndex],
              onStartConfigMode: _startConfigMode,
              onTriggerCurrentKeyConfig: _triggerCurrentKeyConfig,
              onShowSaveRemoteDialog: _showSaveRemoteDialog,
              canSaveRemote: _cfgStatus.contains("All keys captured"),
            )),
            // RepaintBoundary(child: _buildTerminal()), // Hidden as requested
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
