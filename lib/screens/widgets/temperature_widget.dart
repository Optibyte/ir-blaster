import 'package:flutter/material.dart';

class TemperatureWidget extends StatelessWidget {
  final String temperatureText;
  final String deviceTimeText;
  final VoidCallback onRefreshTemp;
  final VoidCallback onRefreshTime;
  final VoidCallback onSyncTime;

  static const Color _cardBackground = Color(0xFF2D2D44);

  const TemperatureWidget({
    super.key,
    required this.temperatureText,
    required this.deviceTimeText,
    required this.onRefreshTemp,
    required this.onRefreshTime,
    required this.onSyncTime,
  });

  @override
  Widget build(BuildContext context) {
    const sub = TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w700);

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
                const Icon(Icons.thermostat, color: Colors.orange),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Room Temp', style: sub),
                      const SizedBox(height: 2),
                      Text(temperatureText, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.refresh, color: Colors.white70), onPressed: onRefreshTemp),
              ],
            ),
            const Divider(height: 18, color: Colors.white24),
            Row(
              children: [
                const Icon(Icons.access_time, color: Colors.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Device RTC', style: sub),
                      const SizedBox(height: 2),
                      Text(deviceTimeText, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.schedule, color: Colors.white70), onPressed: onRefreshTime),
                IconButton(icon: const Icon(Icons.sync, color: Colors.white70), onPressed: onSyncTime),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
