import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'history_entry.dart';
import 'history_service.dart';

class HistoryPage extends StatelessWidget {
  final String? deviceName;
  final bool showDeviceOnly;

  const HistoryPage({
    super.key,
    this.deviceName,
    this.showDeviceOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Color(0xFF252039),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: Text(
          showDeviceOnly ? 'History ($deviceName)' : 'Overall History',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear History'),
                  content: const Text('Are you sure you want to clear all history?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                await HistoryService().clearHistory();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('History cleared')),
                  );
                }
              }
            },
          ),
        ],
      ),

      body: FutureBuilder<List<HistoryEntry>>(
        future: showDeviceOnly
            ? HistoryService().getDeviceHistory(deviceName!)
            : HistoryService().getHistory(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                'No history available',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }

          final history = snapshot.data!;

          return ListView.builder(
            itemCount: history.length,
            itemBuilder: (context, index) {
              final entry = history[index];
              final formattedDate = DateFormat('MMM dd, yyyy HH:mm:ss').format(entry.timestamp);

              IconData iconData;
              Color iconColor;

              switch (entry.action.toLowerCase()) {
                case 'voltage':
                  iconData = Icons.bolt;
                  iconColor = Colors.orange;
                  break;
                case 'current':
                  iconData = Icons.electric_meter;
                  iconColor = Colors.blue;
                  break;
                case 'reset':
                  iconData = Icons.refresh;
                  iconColor = Colors.red;
                  break;
                case 'disconnected':
                  iconData = Icons.bluetooth_disabled;
                  iconColor = Colors.grey;
                  break;
                default:
                  iconData = Icons.info;
                  iconColor = Colors.grey;
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: Icon(iconData, color: iconColor),
                  title: Text('${entry.action}: ${entry.value}'),
                  subtitle: Text(
                      showDeviceOnly
                          ? formattedDate
                          : 'Device: ${entry.deviceName}\n$formattedDate'
                  ),
                  isThreeLine: !showDeviceOnly,
                ),
              );
            },
          );
        },
      ),
    );
  }
}