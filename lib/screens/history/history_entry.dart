class HistoryEntry {
  final String action;
  final String value;
  final DateTime timestamp;
  final String deviceName;

  HistoryEntry({
    required this.action,
    required this.value,
    required this.timestamp,
    required this.deviceName,
  });

  Map<String, dynamic> toJson() => {
    'action': action,
    'value': value,
    'timestamp': timestamp.toIso8601String(),
    'deviceName': deviceName,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
    action: json['action'],
    value: json['value'],
    timestamp: DateTime.parse(json['timestamp']),
    deviceName: json['deviceName'],
  );
}