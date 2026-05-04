import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

import 'configuration_page.dart';

class BluetoothScannerPage extends StatefulWidget {
  const BluetoothScannerPage({super.key});

  @override
  State<BluetoothScannerPage> createState() => _BluetoothScannerPageState();
}

class _BluetoothScannerPageState extends State<BluetoothScannerPage> {
  bool _isScanning = false;
  final List<BluetoothDiscoveryResult> _devices = [];
  bool _showIRBlasterOnly = true;
  StreamSubscription<BluetoothDiscoveryResult>? _streamSubscription;
  Timer? _uiUpdateTimer;
  bool _needsUpdate = false;

  static const Color _themeGreen = Color.fromARGB(255, 123, 159, 71);
  static const Color _background = Color(0xFF1A1A2E);
  static const Color _cardBackground = Color(0xFF2D2D44);

  @override
  void initState() {
    super.initState();
    _requestPermissionsAndEnableBluetooth();
  }

  Future<bool> _requestBluetoothPermissions() async {
    // Request all required Bluetooth permissions for Android 12+
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.locationWhenInUse,
    ].request();

    // Check if all permissions are granted
    bool allGranted = statuses[Permission.bluetoothConnect]!.isGranted &&
                      statuses[Permission.bluetoothScan]!.isGranted;
    
    // Location is often required for Bluetooth discovery on older Android versions
    bool locationGranted = statuses[Permission.locationWhenInUse]!.isGranted;

    if (!allGranted && mounted) {
      _showPermissionError("Bluetooth permissions are required to scan.");
      return false;
    }
    
    if (!locationGranted && mounted) {
      _showPermissionError("Location permission is required for Bluetooth discovery.");
      return false;
    }

    return allGranted;
  }

  Future<void> _requestPermissionsAndEnableBluetooth() async {
    // First request permissions
    final permissionsGranted = await _requestBluetoothPermissions();
    if (!permissionsGranted) return;

    // Then enable Bluetooth
    await _checkAndEnableBluetooth();
  }

  Future<void> _checkAndEnableBluetooth() async {
    try {
      final isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
      if (!(isEnabled ?? false)) {
        final result = await FlutterBluetoothSerial.instance.requestEnable();
        if (result ?? false) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Bluetooth enabled")),
          );
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("❌ Bluetooth is required to scan devices."),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      _showPermissionError("Error enabling Bluetooth: $e");
    }
  }

  void _showPermissionError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("❌ $message"),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: "Settings",
          textColor: Colors.white,
          onPressed: () => openAppSettings(),
        ),
      ),
    );
  }

  void _startScan() async {
    // Check permissions first
    final permissionsGranted = await _requestBluetoothPermissions();
    if (!permissionsGranted) return;

    final isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
    if (!(isEnabled ?? false)) {
      await _checkAndEnableBluetooth();
      return;
    }

    // cancel previous scan if any
    _streamSubscription?.cancel();

    setState(() {
      _isScanning = true;
      _devices.clear();
    });

    _streamSubscription =
        FlutterBluetoothSerial.instance.startDiscovery().listen((result) {
      final index = _devices
          .indexWhere((d) => d.device.address == result.device.address);
      if (index >= 0) {
        _devices[index] = result;
      } else {
        _devices.add(result);
      }
      _needsUpdate = true;
    });

    // Start a timer to update the UI periodically instead of on every device discovery
    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_needsUpdate && mounted) {
        setState(() {
          _needsUpdate = false;
        });
      }
    });

    _streamSubscription?.onDone(() {
      _uiUpdateTimer?.cancel();
      if (mounted) {
        setState(() {
          _isScanning = false;
          _needsUpdate = false;
        });
      }
    });
  }

  void _showLoadingDialog() {
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
                color: Colors.black.withOpacity(0.4),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
              BoxShadow(
                color: _themeGreen.withOpacity(0.15),
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

  void _showInvalidDeviceDialog(BluetoothDevice device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Colors.orange.shade700, size: 28),
            const SizedBox(width: 12),
            const Text(
              "Invalid Device",
              style: TextStyle(
                fontSize: 20,
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
              "\"${device.name ?? device.address}\" is not an Optibyte IR device.",
              style: const TextStyle(fontSize: 15, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade900.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade700),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Only Optibyte devices are supported.",
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
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange.shade400,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              "OK",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    // Check if device is an Optibyte IR device
    if (!_isIRBlaster(device.name ?? '')) {
      _showInvalidDeviceDialog(device);
      return;
    }

    _showLoadingDialog();

    try {
      final connection = await BluetoothConnection.toAddress(device.address);
      if (connection.isConnected && mounted) {
        _hideLoadingDialog();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Connected to ${device.name ?? device.address}"),
            backgroundColor: _themeGreen,
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ConfigurationPage(
              connection: connection,
              device: device,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _hideLoadingDialog();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Failed to connect to ${device.name ?? device.address}\n"
              "Tip: Pair this device once in Bluetooth settings.",
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _uiUpdateTimer?.cancel();
    super.dispose();
  }

  bool _isIRBlaster(String deviceName) {
    final lowerName = deviceName.toLowerCase();
    return lowerName.contains('sustainabyte') ||
        lowerName.contains('ir blaster') ||
        lowerName.contains('ir-blaster') ||
        lowerName.contains('irblaster');
  }

  List<BluetoothDiscoveryResult> get _filteredDevices {
    if (!_showIRBlasterOnly) return _devices;
    return _devices
        .where((result) =>
            _isIRBlaster(result.device.name ?? '') ||
            _isIRBlaster(result.device.address))
        .toList();
  }

  Widget _buildDeviceTile(BluetoothDiscoveryResult result) {
    final device = result.device;
    final rssi = result.rssi;
    final name = device.name ?? "Unknown Device";

    return Card(
      color: _cardBackground,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: ListTile(
        leading: Container(
          decoration: BoxDecoration(
            color: _themeGreen,
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.all(8),
          child: const Icon(
            Icons.bluetooth,
            color: Colors.white,
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        subtitle: Text(
          "${device.address}\nRSSI: $rssi dBm",
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
        isThreeLine: true,
        trailing: ElevatedButton(
          onPressed: () => _connectToDevice(device),
          style: ElevatedButton.styleFrom(
            backgroundColor: _themeGreen,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text(
            "Connect",
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _themeGreen,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          "Bluetooth Scanner",
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          // Header section with same green theme
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: _themeGreen,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                const Icon(
                  Icons.settings_remote,
                  size: 36,
                  color: Colors.white,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Scan for Optibyte IR",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Turn ON the IR device.",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Scan button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ElevatedButton.icon(
              onPressed: _isScanning ? null : _startScan,
              icon: const Icon(Icons.search),
              label: Text(
                _isScanning ? "Scanning..." : "Scan Devices",
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _themeGreen,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Filter toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: InkWell(
              onTap: () {
                setState(() {
                  _showIRBlasterOnly = !_showIRBlasterOnly;
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _showIRBlasterOnly
                            ? const Color(0xFF5E35B1)
                            : _cardBackground,
                        border: Border.all(
                          color: _showIRBlasterOnly
                              ? const Color(0xFF5E35B1)
                              : Colors.white54,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: _showIRBlasterOnly
                          ? const Icon(
                              Icons.check,
                              size: 18,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      "Sustainabyte Devices Only",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (_isScanning) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: LinearProgressIndicator(
                backgroundColor: _cardBackground,
                valueColor: AlwaysStoppedAnimation<Color>(_themeGreen),
              ),
            ),
          ],

          const SizedBox(height: 8),

          // Devices list
          Expanded(
            child: RepaintBoundary(
              child: _filteredDevices.isNotEmpty
                  ? ListView.builder(
                      itemCount: _filteredDevices.length,
                      padding: const EdgeInsets.only(bottom: 20),
                      physics: const BouncingScrollPhysics(),
                      itemBuilder: (context, index) =>
                          _buildDeviceTile(_filteredDevices[index]),
                    )
                  : Center(
                      child: Text(
                        _isScanning
                            ? "Scanning for Bluetooth devices..."
                            : _showIRBlasterOnly
                                ? "No Sustainabyte devices found.\nUncheck the filter to see all devices."
                                : "No devices found.\nTap 'Scan Devices' to search again.",
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
