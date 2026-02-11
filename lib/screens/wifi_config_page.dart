import 'package:flutter/material.dart';
import '../service/bluetooth_service.dart';

class WifiConfigPage extends StatefulWidget {
  final BluetoothService bluetoothService;
  const WifiConfigPage({super.key, required this.bluetoothService});

  @override
  State<WifiConfigPage> createState() => _WifiConfigPageState();
}

class _WifiConfigPageState extends State<WifiConfigPage> {
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  bool isSending = false;

  Future<void> _submitWifiDetails() async {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text.trim();

    if (ssid.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both SSID and Password')),
      );
      return;
    }

    setState(() => isSending = true);

    try {
      await widget.bluetoothService.sendWifiCredentials(ssid, password);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WiFi credentials sent to ESP32')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configure WiFi')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(
              controller: _ssidController,
              decoration: const InputDecoration(labelText: 'WiFi SSID'),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'WiFi Password'),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: isSending ? null : _submitWifiDetails,
              child: Text(isSending ? 'Sending...' : 'Submit'),
            ),
          ],
        ),
      ),
    );
  }
}
