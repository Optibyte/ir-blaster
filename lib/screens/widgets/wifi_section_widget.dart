import 'package:flutter/material.dart';

class WifiSectionWidget extends StatelessWidget {
  final Color themeGreen;
  final bool isWifiConnected;
  final String wifiStatus;
  final String wifiIP;
  final VoidCallback onShowWifiSetup;
  final bool showMqttDropdown;
  final VoidCallback onToggleMqttDropdown;
  final String mqttStatus;
  final bool isMqttConnected;
  final TextEditingController mqttHostController;
  final TextEditingController mqttPortController;
  final TextEditingController mqttTopicController;
  final TextEditingController mqttUserController;
  final TextEditingController mqttPassController;
  final VoidCallback onSendMqttSettings;
  final VoidCallback onConnectMqtt;
  final bool autoControlEnabled;
  final ValueChanged<bool> onAutoControlChanged;
  final TextEditingController autoOnController;
  final TextEditingController autoOffController;
  final VoidCallback onApplyAutoConfig;

  const WifiSectionWidget({
    super.key,
    required this.themeGreen,
    required this.isWifiConnected,
    required this.wifiStatus,
    required this.wifiIP,
    required this.onShowWifiSetup,
    required this.showMqttDropdown,
    required this.onToggleMqttDropdown,
    required this.mqttStatus,
    required this.isMqttConnected,
    required this.mqttHostController,
    required this.mqttPortController,
    required this.mqttTopicController,
    required this.mqttUserController,
    required this.mqttPassController,
    required this.onSendMqttSettings,
    required this.onConnectMqtt,
    required this.autoControlEnabled,
    required this.onAutoControlChanged,
    required this.autoOnController,
    required this.autoOffController,
    required this.onApplyAutoConfig,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildWifiCard(),
        _buildMqttDropdownCard(),
      ],
    );
  }

  Widget _buildWifiCard() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.wifi, color: themeGreen),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    wifiStatus,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: isWifiConnected ? Colors.green : Colors.red,
                    ),
                  ),
                  if (wifiIP.isNotEmpty) Text(wifiIP, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: onShowWifiSetup,
                        icon: const Icon(Icons.settings, size: 16),
                        label: const Text('WiFi Setup'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeGreen,
                          foregroundColor: Colors.black,
                        ),
                      ),
                      if (isWifiConnected)
                        OutlinedButton.icon(
                          onPressed: onToggleMqttDropdown,
                          icon: Icon(showMqttDropdown ? Icons.expand_less : Icons.expand_more, size: 16),
                          label: Text(showMqttDropdown ? 'Hide MQTT' : 'Show MQTT'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMqttDropdownCard() {
    if (!isWifiConnected) return const SizedBox.shrink();
    if (!showMqttDropdown) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('MQTT Settings', style: TextStyle(fontWeight: FontWeight.w900))),
                Chip(
                  label: Text(mqttStatus, style: const TextStyle(fontSize: 12)),
                  backgroundColor: isMqttConnected ? Colors.green.shade100 : Colors.red.shade100,
                ),
              ],
            ),
            const SizedBox(height: 10),
            _field('Host / IP', mqttHostController),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field('Port', mqttPortController, keyboard: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(child: _field('Topic', mqttTopicController)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field('Username', mqttUserController)),
                const SizedBox(width: 10),
                Expanded(child: _field('Password', mqttPassController, obscure: true)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: onSendMqttSettings,
                  icon: const Icon(Icons.save, size: 16),
                  label: const Text('Save & Send'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeGreen,
                    foregroundColor: Colors.black,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: onConnectMqtt,
                  icon: const Icon(Icons.cloud_done, size: 16),
                  label: const Text('Connect MQTT'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const Divider(height: 22),
            Row(
              children: [
                const Expanded(child: Text('Auto Control', style: TextStyle(fontWeight: FontWeight.w900))),
                Switch(value: autoControlEnabled, onChanged: onAutoControlChanged),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field('Auto ON Temp (°C)', autoOnController, keyboard: TextInputType.number)),
                const SizedBox(width: 10),
                Expanded(child: _field('Auto OFF Temp (°C)', autoOffController, keyboard: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: onApplyAutoConfig,
              icon: const Icon(Icons.tune, size: 16),
              label: const Text('Apply Auto Config'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    TextInputType keyboard = TextInputType.text,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      obscureText: obscure,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        isDense: true,
      ).copyWith(labelText: label),
    );
  }
}
