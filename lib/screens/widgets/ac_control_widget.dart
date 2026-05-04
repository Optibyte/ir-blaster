import 'package:flutter/material.dart';

import 'fan_speed_widget.dart';
import 'mode_selector_widget.dart';

class ACControlWidget extends StatelessWidget {
  final Color themeGreen;
  final List<String> brandItems;
  final bool showDefaultRemoteDropdown;
  final VoidCallback onToggleDefaultRemoteDropdown;
  final String defaultRemoteBrand;
  final ValueChanged<String> onDefaultBrandChanged;
  final VoidCallback onPowerOn;
  final VoidCallback onPowerOff;
  final VoidCallback onTempUp;
  final VoidCallback onTempDown;
  final VoidCallback onSwing;
  final VoidCallback onMode;
  final TextEditingController onTimeController;
  final TextEditingController offTimeController;
  final VoidCallback onPickOnTime;
  final VoidCallback onPickOffTime;
  final bool showRemoteConfigDropdown;
  final VoidCallback onToggleRemoteConfigDropdown;
  final String configBrand;
  final ValueChanged<String> onConfigBrandChanged;
  final bool configMode;
  final bool waitingForIr;
  final int cfgStepIndex;
  final int cfgStepsCount;
  final int learningProgress;
  final String cfgStatus;
  final String currentCfgKey;
  final VoidCallback onStartConfigMode;
  final VoidCallback onTriggerCurrentKeyConfig;
  final VoidCallback onShowSaveRemoteDialog;
  final bool canSaveRemote;

  static const Color _cardBackground = Color(0xFF2D2D44);

  const ACControlWidget({
    super.key,
    required this.themeGreen,
    required this.brandItems,
    required this.showDefaultRemoteDropdown,
    required this.onToggleDefaultRemoteDropdown,
    required this.defaultRemoteBrand,
    required this.onDefaultBrandChanged,
    required this.onPowerOn,
    required this.onPowerOff,
    required this.onTempUp,
    required this.onTempDown,
    required this.onSwing,
    required this.onMode,
    required this.onTimeController,
    required this.offTimeController,
    required this.onPickOnTime,
    required this.onPickOffTime,
    required this.showRemoteConfigDropdown,
    required this.onToggleRemoteConfigDropdown,
    required this.configBrand,
    required this.onConfigBrandChanged,
    required this.configMode,
    required this.waitingForIr,
    required this.cfgStepIndex,
    required this.cfgStepsCount,
    required this.learningProgress,
    required this.cfgStatus,
    required this.currentCfgKey,
    required this.onStartConfigMode,
    required this.onTriggerCurrentKeyConfig,
    required this.onShowSaveRemoteDialog,
    required this.canSaveRemote,
  });

  @override
  Widget build(BuildContext context) {
    final defaultBrandValue = _fallbackBrand(defaultRemoteBrand, fallback: 'Samsung');
    final configBrandValue = _fallbackBrand(configBrand, fallback: 'LG');

    return Column(
      children: [
        // _buildRemoteConfigDropdown(configBrandValue),
        _buildDefaultRemoteDropdown(defaultBrandValue),
      ],
    );
  }

  String _fallbackBrand(String current, {required String fallback}) {
    if (brandItems.isEmpty) return current;
    if (brandItems.contains(current)) return current;
    if (brandItems.contains(fallback)) return fallback;
    return brandItems.first;
  }

  Widget _buildDefaultRemoteDropdown(String defaultBrandValue) {
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
                const Expanded(
                  child: Text(
                    'Default AC Remote',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white),
                  ),
                ),
                IconButton(
                  onPressed: onToggleDefaultRemoteDropdown,
                  icon: Icon(showDefaultRemoteDropdown ? Icons.expand_less : Icons.expand_more, color: Colors.white70),
                ),
              ],
            ),
            if (showDefaultRemoteDropdown) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: defaultBrandValue,
                dropdownColor: _cardBackground,
                style: const TextStyle(color: Colors.white),
                items: brandItems
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  onDefaultBrandChanged(v);
                },
                decoration: const InputDecoration(
                  labelText: 'Brand',
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              /*
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RemoteControlButton(
                    label: 'POWER ON',
                    icon: Icons.power_settings_new,
                    onTap: onPowerOn,
                    themeGreen: themeGreen,
                  ),
                  FanSpeedWidget(themeGreen: themeGreen, onSwing: onSwing),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ModeSelectorWidget(themeGreen: themeGreen, onMode: onMode),
                  _RemoteControlButton(
                    label: 'POWER OFF',
                    icon: Icons.power_off,
                    onTap: onPowerOff,
                    themeGreen: themeGreen,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: onTimeController,
                      readOnly: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'ON Time (HH:MM)',
                        labelStyle: TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                        isDense: true,
                      ),
                      onTap: onPickOnTime,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: offTimeController,
                      readOnly: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'OFF Time (HH:MM)',
                        labelStyle: TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                        isDense: true,
                      ),
                      onTap: onPickOffTime,
                    ),
                  ),
                ],
              ),
              */
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteConfigDropdown(String configBrandValue) {
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
                const Expanded(
                  child: Text(
                    'Remote Configuration',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white),
                  ),
                ),
                IconButton(
                  onPressed: onToggleRemoteConfigDropdown,
                  icon: Icon(showRemoteConfigDropdown ? Icons.expand_less : Icons.expand_more, color: Colors.white70),
                ),
              ],
            ),
            if (showRemoteConfigDropdown) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: configBrandValue,
                dropdownColor: _cardBackground,
                style: const TextStyle(color: Colors.white),
                items: brandItems
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  onConfigBrandChanged(v);
                },
                decoration: const InputDecoration(
                  labelText: 'Brand to Learn',
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: configMode ? null : onStartConfigMode,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Config'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (!configMode || waitingForIr) ? null : onTriggerCurrentKeyConfig,
                      icon: Icon(Icons.wifi_tethering, color: configMode && !waitingForIr ? Colors.white70 : Colors.grey),
                      label: Text('Config $currentCfgKey', style: TextStyle(color: configMode && !waitingForIr ? Colors.white70 : Colors.grey)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white54)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Step ${cfgStepIndex + 1}/$cfgStepsCount  ->  $currentCfgKey',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: (learningProgress / 100.0).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation<Color>(themeGreen),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  cfgStatus,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: waitingForIr ? Colors.orange : Colors.white70,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: canSaveRemote ? onShowSaveRemoteDialog : null,
                icon: const Icon(Icons.save),
                label: const Text('Save Remote'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: themeGreen,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RemoteControlButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color themeGreen;

  const _RemoteControlButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.themeGreen,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 110,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: themeGreen, borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
