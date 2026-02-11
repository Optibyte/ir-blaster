import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bluetooth_scanner_page.dart';

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
  static const Color _themeGreen = Color(0xFFC8E6C9);
  static const Color _green = Colors.green;
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

  // ====== WiFi Info ======
  String _wifiIP = "";
  String _wifiStatus = "WiFi not connected";
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _wifiPasswordController = TextEditingController();

  // ====== Temp / RTC ======
  String _temperatureText = "--";
  String _deviceTimeText = "--";

  // ====== Terminal ======
  bool _showTerminal = true;
  final TextEditingController _terminalController = TextEditingController();
  String _incomingBuffer = "";

  // ===================== MQTT =====================
  bool _showMqttDropdown = false;
  bool _isMqttConnected = false;
  String _mqttStatus = "MQTT not connected";

  final TextEditingController _mqttHostController = TextEditingController(text: "13.66.130.236");
  final TextEditingController _mqttPortController = TextEditingController(text: "1883");
  final TextEditingController _mqttUserController = TextEditingController(text: "mahavirir");
  final TextEditingController _mqttPassController = TextEditingController(text: "mahavir@123");
  final TextEditingController _mqttTopicController = TextEditingController(text: "mahavirir");

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
  }

  @override
  void dispose() {
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
        _isWifiConnected = prefs.getBool('wifi_connected') ?? false;
        _wifiIP = prefs.getString('wifi_ip') ?? "";
        _wifiStatus = _isWifiConnected ? "WiFi connected: $_wifiIP" : "WiFi not connected";

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

  Future<void> _saveWifiStatus(bool connected, {required String ip}) async {
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
    }).onDone(() {
      setState(() {
        _isConnected = false;
        _isYellowLedOn = false;
      });
      _showSnack("Bluetooth disconnected", _red);
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
        _wifiIP = ip;
        _wifiStatus = "WiFi connected: $ip";
        _isGreenLedOn = true;
        _showMqttDropdown = true;
      });
      _saveWifiStatus(true, ip: ip);
      // auto connect mqtt if values exist
      _sendMqttSettingsToDevice(connect: true);
      return;
    }
    if (line.startsWith("WIFI_FAILED")) {
      setState(() {
        _isWifiConnected = false;
        _wifiIP = "";
        _wifiStatus = "WiFi connection failed";
        _isGreenLedOn = false;

        _isMqttConnected = false;
        _mqttStatus = "MQTT not connected";
      });
      _saveWifiStatus(false, ip: "");
      return;
    }

    // MQTT
    if (line.startsWith("MQTT_CONNECTED")) {
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
      _connection.output.add(Uint8List.fromList(utf8.encode("$cmd\n")));
      await _connection.output.allSent;
    } catch (e) {
      _showSnack("Send failed: $e", _red);
    }
  }

  // ===================== WiFi =====================
  void _showWifiSetupDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("WiFi Setup"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ssidController,
              decoration: const InputDecoration(labelText: "SSID", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _wifiPasswordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _connectWifi();
            },
            child: const Text("Send"),
          ),
        ],
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
    setState(() => _wifiStatus = "Connecting to WiFi...");
    await _sendCommand("WIFI:$ssid,$pass");
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
      elevation: 2,
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(_isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled, color: _isConnected ? _blue : _red),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(children: [
                  Icon(Icons.circle, size: 12, color: _isYellowLedOn ? Colors.yellow : Colors.grey),
                  const SizedBox(width: 4),
                  const Text("BT"),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.circle, size: 12, color: _isGreenLedOn ? Colors.green : Colors.grey),
                  const SizedBox(width: 4),
                  const Text("WiFi"),
                ]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWifiCard() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.wifi, color: _themeGreen),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _wifiStatus,
                    style: TextStyle(fontWeight: FontWeight.w800, color: _isWifiConnected ? _green : _red),
                  ),
                  if (_wifiIP.isNotEmpty) Text(_wifiIP, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _showWifiSetupDialog,
                        icon: const Icon(Icons.settings, size: 16),
                        label: const Text("WiFi Setup"),
                        style: ElevatedButton.styleFrom(backgroundColor: _themeGreen, foregroundColor: Colors.black),
                      ),
                      if (_isWifiConnected)
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _showMqttDropdown = !_showMqttDropdown),
                          icon: Icon(_showMqttDropdown ? Icons.expand_less : Icons.expand_more, size: 16),
                          label: Text(_showMqttDropdown ? "Hide MQTT" : "Show MQTT"),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMqttDropdownCard() {
    if (!_isWifiConnected) return const SizedBox.shrink();
    if (!_showMqttDropdown) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text("MQTT Settings", style: TextStyle(fontWeight: FontWeight.w900))),
                Chip(
                  label: Text(_mqttStatus, style: const TextStyle(fontSize: 12)),
                  backgroundColor: _isMqttConnected ? Colors.green.shade100 : Colors.red.shade100,
                ),
              ],
            ),
            const SizedBox(height: 10),
            _field("Host / IP", _mqttHostController),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field("Port", _mqttPortController, keyboard: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(child: _field("Topic", _mqttTopicController)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field("Username", _mqttUserController)),
                const SizedBox(width: 10),
                Expanded(child: _field("Password", _mqttPassController, obscure: true)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _sendMqttSettingsToDevice(connect: false),
                  icon: const Icon(Icons.save, size: 16),
                  label: const Text("Save & Send"),
                  style: ElevatedButton.styleFrom(backgroundColor: _themeGreen, foregroundColor: Colors.black),
                ),
                ElevatedButton.icon(
                  onPressed: () => _sendMqttSettingsToDevice(connect: true),
                  icon: const Icon(Icons.cloud_done, size: 16),
                  label: const Text("Connect MQTT"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                ),
              ],
            ),
            const Divider(height: 22),
            Row(
              children: [
                const Expanded(child: Text("Auto Control", style: TextStyle(fontWeight: FontWeight.w900))),
                Switch(
                  value: _autoControlEnabled,
                  onChanged: (v) async {
                    setState(() => _autoControlEnabled = v);
                    await _saveAutoPrefs();
                    await _sendAutoSetpointsToDevice();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field("Auto ON Temp (°C)", _autoOnController, keyboard: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(child: _field("Auto OFF Temp (°C)", _autoOffController, keyboard: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _sendAutoSetpointsToDevice,
              icon: const Icon(Icons.tune, size: 16),
              label: const Text("Apply Auto Config"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController c, {
    TextInputType keyboard = TextInputType.text,
    bool obscure = false,
  }) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      obscureText: obscure,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
      ).copyWith(labelText: label),
    );
  }

  Widget _buildTempRtcCard() {
    final sub = TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w700);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.thermostat, color: Colors.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Room Temp", style: sub),
                      const SizedBox(height: 2),
                      Text(_temperatureText, style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.refresh), onPressed: () => _sendCommand("GET_TEMP")),
              ],
            ),
            const Divider(height: 18),
            Row(
              children: [
                Icon(Icons.access_time, color: _blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Device RTC", style: sub),
                      const SizedBox(height: 2),
                      Text(_deviceTimeText, style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.schedule), onPressed: () => _sendCommand("GET_TIME")),
                IconButton(
                  icon: const Icon(Icons.sync),
                  onPressed: () {
                    final now = DateTime.now();
                    final formatted = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
                    setState(() => _deviceTimeText = formatted);
                    _sendCommand("SET_TIME:$formatted");
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (mounted) _sendCommand("GET_TIME");
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===================== DEFAULT REMOTE DROPDOWN =====================
  Widget _buildDefaultRemoteDropdown() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Default AC Remote",
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _showDefaultRemoteDropdown = !_showDefaultRemoteDropdown),
                  icon: Icon(_showDefaultRemoteDropdown ? Icons.expand_less : Icons.expand_more),
                ),
              ],
            ),
            if (_showDefaultRemoteDropdown) ...[
              const SizedBox(height: 10),

              // brand selector for default sending
              DropdownButtonFormField<String>(
                value: _brandDropdownItems().contains(_defaultRemoteBrand) ? _defaultRemoteBrand : "Samsung",
                items: _brandDropdownItems().map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  _setDefaultBrandOnDevice(v);
                },
                decoration: const InputDecoration(
                  labelText: "Brand",
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),

              const SizedBox(height: 12),

              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _remoteBtn("POWER ON", Icons.power_settings_new, () => _sendDefaultRemoteKey("POWER_ON")),
                  _remoteBtn("TEMP +", Icons.arrow_upward, () => _sendDefaultRemoteKey("TEMPUP")),
                  _remoteBtn("TEMP -", Icons.arrow_downward, () => _sendDefaultRemoteKey("TEMPDOWN")),
                  _remoteBtn("SWING", Icons.swap_horiz, () => _sendDefaultRemoteKey("SWING")),
                  _remoteBtn("MODE", Icons.tune, () => _sendDefaultRemoteKey("MODE")),
                  _remoteBtn("POWER OFF", Icons.power_off, () => _sendDefaultRemoteKey("POWER_OFF")),
                ],
              ),

              const SizedBox(height: 14),

              // schedules (optional)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _onTimeController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: "ON Time (HH:MM)",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onTap: () => _pickTime(_onTimeController, "SCHEDULE_ON"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _offTimeController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: "OFF Time (HH:MM)",
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onTap: () => _pickTime(_offTimeController, "SCHEDULE_OFF"),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ===================== REMOTE CONFIG DROPDOWN =====================
  Widget _buildRemoteConfigDropdown() {
    final currentKey = _cfgKeys[_cfgStepIndex];

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    "Remote Configuration",
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _showRemoteConfigDropdown = !_showRemoteConfigDropdown),
                  icon: Icon(_showRemoteConfigDropdown ? Icons.expand_less : Icons.expand_more),
                ),
              ],
            ),
            if (_showRemoteConfigDropdown) ...[
              const SizedBox(height: 10),

              DropdownButtonFormField<String>(
                value: _brandDropdownItems().contains(_configBrand) ? _configBrand : "LG",
                items: _brandDropdownItems().map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  _setConfigBrandOnDevice(v);
                },
                decoration: const InputDecoration(
                  labelText: "Brand to Learn",
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _configMode ? null : _startConfigMode,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text("Start Config"),
                      style: ElevatedButton.styleFrom(backgroundColor: _themeGreen, foregroundColor: Colors.black),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (!_configMode || _waitingForIr) ? null : _triggerCurrentKeyConfig,
                      icon: const Icon(Icons.wifi_tethering),
                      label: Text("Config $currentKey"),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Step indicator
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Step ${_cfgStepIndex + 1}/${_cfgKeys.length}  →  $currentKey",
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 6),

              // progress
              LinearProgressIndicator(
                value: (_learningProgress / 100.0).clamp(0.0, 1.0),
                minHeight: 8,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _cfgStatus,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _waitingForIr ? Colors.orange : Colors.black,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Save button (enabled only after last step done message sets status)
              ElevatedButton.icon(
                onPressed: (_configMode == false && _cfgStatus.contains("All keys captured"))
                    ? _showSaveRemoteDialog
                    : (_cfgStatus.contains("All keys captured") ? _showSaveRemoteDialog : null),
                icon: const Icon(Icons.save),
                label: const Text("Save Remote"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _remoteBtn(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 110,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: _themeGreen, borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            Icon(icon, color: Colors.black),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
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
          icon: const Icon(Icons.developer_mode),
          label: const Text("Show Logs"),
        ),
      );
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Expanded(child: Text("Terminal / Logs", style: TextStyle(fontWeight: FontWeight.w900))),
                IconButton(onPressed: () => setState(() => _showTerminal = false), icon: const Icon(Icons.close)),
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
                  style: const TextStyle(fontFamily: 'monospace', color: Colors.greenAccent, fontSize: 11),
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
    setState(() {});
  }

  void _showSnack(String msg, Color c) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: c));
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
      appBar: AppBar(
        title: const Text("Configuration", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900)),
        backgroundColor: _themeGreen,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(icon: const Icon(Icons.bluetooth_disabled), onPressed: _disconnectBluetooth),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildStatusCard(),
            _buildWifiCard(),
            _buildMqttDropdownCard(),
            _buildTempRtcCard(),

            // ✅ both required dropdowns
            _buildRemoteConfigDropdown(), // remote learning
            _buildDefaultRemoteDropdown(), // default remote control

            _buildTerminal(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
