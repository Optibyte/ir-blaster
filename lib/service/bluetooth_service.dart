// Bluetooth Service - Send RAW IR Data from Flutter

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class BluetoothService {
  final BluetoothConnection connection;

  BluetoothService({required this.connection});

  Future<void> sendRawIR(String key, List<int> rawData) async {
    final int len = rawData.length;
    final String command = 'RAW_SEND:$key,$len,${rawData.join(',')}' "\n";
    try {
      connection.output.add(Uint8List.fromList(utf8.encode(command)));
      await connection.output.allSent;
      print('✅ RAW IR Sent for $key');
    } catch (e) {
      print("❌ Failed to send RAW IR: $e");
    }
  }

  Future<void> sendSimpleCommand(String cmd) async {
    try {
      connection.output.add(Uint8List.fromList(utf8.encode("$cmd\n")));
      await connection.output.allSent;
      print('✅ Command Sent: $cmd');
    } catch (e) {
      print("❌ Failed to send command: $e");
    }
  }

  void listenToResponses(void Function(String message) onMessage) {
    connection.input?.listen((Uint8List data) {
      final message = utf8.decode(data).trim();
      onMessage(message);
    });
  }

  sendWifiCredentials(String ssid, String password) {}
}
