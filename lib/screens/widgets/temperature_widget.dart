import 'package:flutter/material.dart';

class TemperatureWidget extends StatelessWidget {
  final String temperatureText;
  final String deviceTimeText;
  final VoidCallback onRefreshTemp;
  final VoidCallback onRefreshTime;
  final VoidCallback onSyncTime;

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
                      Text('Room Temp', style: sub),
                      const SizedBox(height: 2),
                      Text(temperatureText, style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.refresh), onPressed: onRefreshTemp),
              ],
            ),
            const Divider(height: 18),
            Row(
              children: [
                const Icon(Icons.access_time, color: Colors.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Device RTC', style: sub),
                      const SizedBox(height: 2),
                      Text(deviceTimeText, style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.schedule), onPressed: onRefreshTime),
                IconButton(icon: const Icon(Icons.sync), onPressed: onSyncTime),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
