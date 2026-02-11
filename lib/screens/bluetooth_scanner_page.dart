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
          content: Text("❌ Bluetooth permissions are required to scan devices."),
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

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      final connection = await BluetoothConnection.toAddress(device.address);
      if (connection.isConnected && mounted) {
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
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isScanning ? null : _startScan,
                    icon: const Icon(Icons.search),
                    label: Text(
                      _isScanning ? "Scanning..." : "Scan Devices",
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _themeGreen,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
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
              ],
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
            child: _devices.isNotEmpty
                ? ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) =>
                        _buildDeviceTile(_devices[index]),
                  )
                : Center(
                    child: Text(
                      _isScanning
                          ? "Scanning for Bluetooth devices..."
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
