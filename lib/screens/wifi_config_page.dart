import 'package:flutter/material.dart';
import '../service/bluetooth_service.dart';
import '../core/services/local_cache_service.dart';

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

  static const Color _background = Color(0xFF1A1A2E);
  static const Color _cardBackground = Color(0xFF2D2D44);
  static const Color _themeGreen = Color.fromARGB(255, 123, 159, 71);

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
      // Save to local storage
      await LocalCacheService.saveWifiCredentials(ssid, password);
      
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
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text('Configure WiFi', style: TextStyle(color: Colors.black)),
        backgroundColor: _themeGreen,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(
              controller: _ssidController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'WiFi SSID',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'WiFi Password',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: isSending ? null : _submitWifiDetails,
              style: ElevatedButton.styleFrom(
                backgroundColor: _themeGreen,
                foregroundColor: Colors.black,
              ),
              child: Text(isSending ? 'Sending...' : 'Submit'),
            ),
          ],
        ),
      ),
    );
  }
}
