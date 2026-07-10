import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import 'package:ir_blaster_ac/core/services/mqtt_service.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/services/local_cache_service.dart';
import 'package:ir_blaster_ac/screens/bluetooth_scanner_page.dart';

class WifiManagementDialog extends StatefulWidget {
  final MqttService mqtt;
  final String initialSsid;
  final Function(String ssid, String password)? onWifiConfigured;

  const WifiManagementDialog({
    super.key,
    required this.mqtt,
    required this.initialSsid,
    this.onWifiConfigured,
  });

  @override
  State<WifiManagementDialog> createState() => _WifiManagementDialogState();
}

class _WifiManagementDialogState extends State<WifiManagementDialog> {
  final _newSsidCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  bool _showNewPassword = false;
  bool _isResetting = false;

  String _cachedPrimarySsid = '';
  String _cachedPrimaryPass = '';

  bool _showPrimaryPassword = false;

  StreamSubscription? _responseSub;

  Future<void> _loadCachedCredentials() async {
    final primary = await LocalCacheService.getWifiCredentials();
    
    final pSsid = primary['ssid'] ?? '';
    final pPass = primary['password'] ?? '';

    if (mounted) {
      setState(() {
        _cachedPrimarySsid = pSsid;
        _cachedPrimaryPass = pPass;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCachedCredentials();
    // Request current WiFi status immediately
    widget.mqtt.requestWifiStatus();

    // Subscribe to response stream for feedback inside the dialog
    _responseSub = widget.mqtt.responseStream.listen((resp) {
      if (!mounted) return;

      if (resp.type == SirisResponseType.wifiPrimarySet) {
        _showSnack('Primary WiFi saved: ${resp.detail}', AppColors.online);
        _loadCachedCredentials();
      } else if (resp.type == SirisResponseType.wifiSecondarySet) {
        _showSnack('Secondary WiFi saved: ${resp.detail}', AppColors.online);
        _loadCachedCredentials();
      } else if (resp.type == SirisResponseType.wifiResetBtOpen) {
        _showSnack('WiFi reset complete on device!', AppColors.warning);
      } else if (resp.type == SirisResponseType.wifiError) {
        _showSnack('WiFi Error: ${resp.detail}', AppColors.offline);
      } else if (resp.type == SirisResponseType.wifiRollback) {
        _showSnack('WiFi failed! Rolled back to: ${resp.detail}', AppColors.warning);
        _loadCachedCredentials();
      }
    });
  }

  void _showSnack(String message, Color bgColor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void dispose() {
    _responseSub?.cancel();
    _newSsidCtrl.dispose();
    _newPassCtrl.dispose();
    super.dispose();
  }

  String _getRssiLabel(int rssi) {
    if (rssi == 0) return 'N/A';
    if (rssi >= -50) return 'Excellent ($rssi dBm)';
    if (rssi >= -70) return 'Good ($rssi dBm)';
    if (rssi >= -85) return 'Fair ($rssi dBm)';
    return 'Poor ($rssi dBm)';
  }

  Color _getRssiColor(int rssi) {
    if (rssi == 0) return Colors.grey;
    if (rssi >= -50) return Colors.green;
    if (rssi >= -70) return Colors.lightGreen;
    if (rssi >= -85) return Colors.orange;
    return Colors.red;
  }

  IconData _getRssiIcon(int rssi) {
    if (rssi == 0) return Icons.signal_wifi_bad_rounded;
    if (rssi >= -50) return Icons.signal_wifi_4_bar_rounded;
    if (rssi >= -70) return Icons.signal_wifi_4_bar_rounded;
    if (rssi >= -85) return Icons.signal_wifi_statusbar_4_bar_rounded;
    return Icons.signal_wifi_0_bar_rounded;
  }

  void _handleReset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Reset WiFi Credentials',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Are you sure you want to reset the device WiFi?\n\nThis will disconnect the device from your WiFi and open a 60-second Bluetooth provisioning window.',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.offline,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Reset', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => _isResetting = true);

      final newSsid = _newSsidCtrl.text.trim();
      final newPass = _newPassCtrl.text.trim();

      if (newSsid.isNotEmpty) {
        // Save to cache immediately
        await LocalCacheService.saveWifiCredentials(newSsid, newPass);
        await _loadCachedCredentials();

        final bool mqttConnected = widget.mqtt.isConnected;
        if (mqttConnected) {
          widget.mqtt.setPrimaryWifiMqtt(newSsid, newPass);
          await Future.delayed(const Duration(milliseconds: 300));
          widget.mqtt.sendWifiConnect();
          _showSnack(
            'WiFi credentials sent. Triggering network switch...',
            AppColors.online,
          );
          // Wait briefly for publish transmission
          await Future.delayed(const Duration(milliseconds: 500));
        } else {
          _showSnack(
            'MQTT not connected. Saved credentials to cache. Please provision via Bluetooth.',
            AppColors.warning,
          );
          widget.mqtt.disconnect();
          setState(() => _isResetting = false);
          if (mounted) {
            Navigator.of(context).pop();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BluetoothScannerPage()),
            );
          }
          return;
        }

        setState(() => _isResetting = false);

        if (mounted) {
          Navigator.of(context).pop(); // Close WiFi dialog
          widget.onWifiConfigured?.call(newSsid, newPass);
        }
      } else {
        // Clear cache immediately so the app transitions to a clean state
        await LocalCacheService.clearWifiCredentials();
        await LocalCacheService.clearSecondaryWifiCredentials();
        await _loadCachedCredentials();

        final bool mqttConnected = widget.mqtt.isConnected;
        if (mqttConnected) {
          widget.mqtt.sendWifiReset();
          _showSnack(
            'WiFi Reset command sent. Disconnecting and opening Bluetooth scanner...',
            AppColors.warning,
          );
          // Ensure the publish packet is transmitted before closing socket
          await Future.delayed(const Duration(milliseconds: 500));
        } else {
          _showSnack(
            'MQTT not connected. Local cache cleared. Redirecting to Bluetooth scanner...',
            AppColors.warning,
          );
        }

        // Disconnect MQTT client connection
        widget.mqtt.disconnect();

        setState(() => _isResetting = false);

        if (mounted) {
          Navigator.of(context).pop(); // Close WiFi dialog
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BluetoothScannerPage()),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1E2F) : Colors.grey[50]!;
    final textColor = isDark ? Colors.white : AppColors.textPrimary;
    final subtitleColor = isDark ? Colors.white54 : AppColors.textSecondary;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF2D2D44) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: StreamBuilder<SirisDeviceState>(
            stream: widget.mqtt.stateStream,
            initialData: widget.mqtt.lastState,
            builder: (context, snapshot) {
              final state = snapshot.data;
              final isOnline = widget.mqtt.isConnected && (state?.isActive ?? false);
              final ssid = state?.wifiSsid ?? widget.initialSsid;
              final ip = state?.wifiIp ?? 'N/A';
              final rssi = state?.wifiRssi ?? 0;

              final devicePrimarySsid = state?.primarySsid ?? '';
              final displayPrimarySsid = devicePrimarySsid.isNotEmpty ? devicePrimarySsid : _cachedPrimarySsid;
              final primaryPassDisplay = (displayPrimarySsid == _cachedPrimarySsid && _cachedPrimaryPass.isNotEmpty)
                  ? _cachedPrimaryPass
                  : (displayPrimarySsid.isNotEmpty ? 'Saved on Device' : '');

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.wifi, color: Colors.green, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'WiFi Management',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: textColor,
                              ),
                            ),
                            Text(
                              'Configure or reset credentials',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: subtitleColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Current Connection Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.black12,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Connection',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildDetailRow('SSID', ssid.isNotEmpty ? ssid : 'Disconnected', isDark),
                        _buildDetailRow('IP Address', isOnline ? ip : 'N/A', isDark),
                        _buildDetailRow(
                          'Signal',
                          isOnline ? _getRssiLabel(rssi) : 'Offline',
                          isDark,
                          valueColor: isOnline ? _getRssiColor(rssi) : subtitleColor,
                          icon: isOnline ? Icon(_getRssiIcon(rssi), color: _getRssiColor(rssi), size: 14) : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Saved WiFi Credentials Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.black12,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Saved WiFi Credentials',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (displayPrimarySsid.isNotEmpty) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Primary: $displayPrimarySsid',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: textColor,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _showPrimaryPassword ? 'Pass: $primaryPassDisplay' : 'Pass: •• •• •• ••',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: subtitleColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  _showPrimaryPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                  size: 18,
                                  color: subtitleColor,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  setState(() => _showPrimaryPassword = !_showPrimaryPassword);
                                },
                              ),
                            ],
                          ),
                        ] else ...[
                          Text(
                            'Primary: Not Configured',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: subtitleColor,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // New WiFi Credentials Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.black12,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'New WiFi Credentials',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _newSsidCtrl,
                          style: GoogleFonts.inter(fontSize: 13, color: textColor),
                          decoration: InputDecoration(
                            labelText: 'New SSID',
                            labelStyle: GoogleFonts.inter(color: subtitleColor, fontSize: 12),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _newPassCtrl,
                          obscureText: !_showNewPassword,
                          style: GoogleFonts.inter(fontSize: 13, color: textColor),
                          decoration: InputDecoration(
                            labelText: 'New Password',
                            labelStyle: GoogleFonts.inter(color: subtitleColor, fontSize: 12),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showNewPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                size: 18,
                                color: subtitleColor,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setState(() => _showNewPassword = !_showNewPassword);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Reset Button
                  ElevatedButton.icon(
                    onPressed: _isResetting ? null : _handleReset,
                    icon: _isResetting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.wifi_protected_setup_rounded, size: 18),
                    label: Text(
                      _isResetting ? 'Resetting...' : 'Reset WiFi & Provision via BT',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.offline,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, bool isDark, {Color? valueColor, Widget? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: isDark ? Colors.white38 : Colors.black45,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                icon,
                const SizedBox(width: 4),
              ],
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
