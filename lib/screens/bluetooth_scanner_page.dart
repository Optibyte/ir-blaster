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
  StreamSubscription<BluetoothDiscoveryResult>? _streamSubscription;
  bool _showIRBlasterOnly = true;

  Color get _themeGreen => const Color(0xFFC8E6C9);

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
    bool allGranted = statuses.values.every(
      (status) => status.isGranted || status.isLimited,
    );

    if (!allGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text("❌ Bluetooth permissions are required to scan devices."),
          backgroundColor: Colors.red,
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Error enabling Bluetooth: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
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
      setState(() {
        final index = _devices
            .indexWhere((d) => d.device.address == result.device.address);
        if (index >= 0) {
          _devices[index] = result;
        } else {
          _devices.add(result);
        }
      });
    });

    _streamSubscription?.onDone(() {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    });
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  _themeGreen.withOpacity(0.8),
                ),
                strokeWidth: 3,
              ),
              const SizedBox(height: 20),
              const Text(
                "Connecting...",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
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
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "\"${device.name ?? device.address}\" is not a Sustainabyte IR Blaster device.",
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Only Sustainabyte devices are supported.",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
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
              foregroundColor: Colors.orange.shade700,
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
    // Check if device is a Sustainabyte IR Blaster
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
            backgroundColor: Colors.green,
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
            color: Colors.black87,
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          "${device.address}\nRSSI: $rssi dBm",
          style: const TextStyle(fontSize: 12),
        ),
        isThreeLine: true,
        trailing: ElevatedButton(
          onPressed: () => _connectToDevice(device),
          style: ElevatedButton.styleFrom(
            backgroundColor: _themeGreen,
            foregroundColor: Colors.black,
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
      appBar: AppBar(
        backgroundColor: _themeGreen,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          "Bluetooth Scanner",
          style: TextStyle(color: Colors.black),
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
                  color: Colors.black87,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Scan for IR Blaster",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Turn ON the IR device.",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
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
                foregroundColor: Colors.black,
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
                            : Colors.white,
                        border: Border.all(
                          color: _showIRBlasterOnly
                              ? const Color(0xFF5E35B1)
                              : Colors.grey.shade400,
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
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (_isScanning) ...[
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: LinearProgressIndicator(),
            ),
          ],

          const SizedBox(height: 8),

          // Devices list
          Expanded(
            child: _filteredDevices.isNotEmpty
                ? ListView.builder(
                    itemCount: _filteredDevices.length,
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
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
