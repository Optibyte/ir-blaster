import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ir_blaster_ac/core/config/app_config.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/services/mqtt_service.dart';
import 'package:ir_blaster_ac/core/services/admin_service.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';

class IRLearningConfigPage extends StatefulWidget {
  final String? initialDeviceId;

  const IRLearningConfigPage({super.key, this.initialDeviceId});

  @override
  State<IRLearningConfigPage> createState() => _IRLearningConfigPageState();
}

class _IRLearningConfigPageState extends State<IRLearningConfigPage> {
  final MqttService _mqttService = MqttService();
  StreamSubscription<SirisResponse>? _responseSub;
  StreamSubscription<SirisDeviceState>? _stateSub;

  List<Map<String, dynamic>> _devices = [];
  String _selectedDeviceId = '';
  bool _isLoadingDevices = false;

  String _lastSavedTarget = '';
  String _lastSavedLength = '';
  String _lastSavedMessage = '';


  // Selected temperatures for step capture/erase
  int _selectedUpTemp = 24; // Range: 16-29
  int _selectedDownTemp = 24; // Range: 17-30

  @override
  void initState() {
    super.initState();
    _selectedDeviceId = widget.initialDeviceId ?? _mqttService.deviceId;
    _loadDevices();
    _subscribeToMqttResponses();

    // Query status on load if connected
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestStatus();
    });
  }

  @override
  void dispose() {
    _responseSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  String _getItemCategory(Map<String, dynamic> d) {
    if (d['itemType'] == 'system') return 'System';
    return 'Equipment';
  }

  String _getEquipmentName(Map<String, dynamic> d) {
    if (d['itemType'] == 'system') {
      return (d['name'] ?? d['systemName'] ?? d['Name'] ?? 'System').toString().trim();
    }
    final eqName = (d['equipmentName'] ?? d['EquipmentName'] ?? d['name'] ?? d['Name'] ?? '').toString().trim();
    if (eqName.isNotEmpty) return eqName;
    final shortId = _getEquipmentShortId(d);
    return shortId.isNotEmpty ? shortId : 'AC Equipment';
  }

  String _getSystemName(Map<String, dynamic> d) {
    final sysName = (d['systemName'] ?? d['SystemName'] ?? d['system_name'] ?? '').toString().trim();
    if (sysName.isNotEmpty) return sysName;
    if (d['itemType'] == 'system') {
      return (d['name'] ?? d['Name'] ?? d['systemName'] ?? '').toString().trim();
    }
    return '';
  }

  String _getPrimaryDeviceId(Map<String, dynamic> d) {
    final imei = (d['imei'] ?? d['Imei'] ?? '').toString().trim();
    if (imei.isNotEmpty) return imei;
    final eqName = (d['equipmentName'] ?? d['EquipmentName'] ?? d['name'] ?? d['Name'] ?? '').toString().trim();
    if (eqName.isNotEmpty && eqName != 'AC Equipment' && eqName != 'System') return eqName;
    final devId = (d['deviceId'] ?? d['equipmentId'] ?? d['id'] ?? d['Id'] ?? '').toString().trim();
    if (devId.isNotEmpty) return devId;
    final shortId = (d['shortId'] ?? d['ShortId'] ?? d['equipmentShortId'] ?? d['systemShortId'] ?? '').toString().trim();
    return shortId;
  }

  String _getEquipmentShortId(Map<String, dynamic> d) {
    final sId = (d['shortId'] ?? d['ShortId'] ?? d['equipmentShortId'] ?? d['ShortID'] ?? d['systemShortId'] ?? '').toString().trim();
    if (sId.isNotEmpty) return sId;
    final id = (d['id'] ?? d['Id'] ?? d['deviceId'] ?? d['equipmentId'] ?? d['systemId'] ?? '').toString().trim();
    if (id.length > 12) {
      return '${id.substring(0, 8)}...${id.substring(id.length - 4)}';
    }
    return id;
  }

  String _getDropdownLabel(Map<String, dynamic> d) {
    final isSystem = d['itemType'] == 'system';
    final equipName = _getEquipmentName(d);
    final sysName = _getSystemName(d);

    if (isSystem) {
      return sysName.isNotEmpty ? 'System: $sysName' : equipName;
    } else {
      if (sysName.isNotEmpty && sysName != equipName) {
        return '$equipName • System: $sysName';
      } else {
        return equipName;
      }
    }
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoadingDevices = true);
    try {
      final companyId = await AuthService.getCompanyId() ?? '';
      final siteId = await AuthService.getSiteId() ?? '';
      final token = await AuthService.getCookieHeader() ?? '';

      // 1. Fetch equipments from primary endpoint
      List<Map<String, dynamic>> equipments = [];
      try {
        equipments = await AdminService.fetchEquipments(companyId: companyId, siteId: siteId);
      } catch (e) {
        debugPrint('⚠️ [IRLearningConfig] fetchEquipments error: $e');
      }

      // 2. Fetch systems to get system names & fallback equipment lists
      final systems = await AdminService.fetchSystems(companyId: companyId, siteId: siteId);

      // Build systemNameMap for lookup
      final Map<String, String> systemNameMap = {};
      for (var sys in systems) {
        final sysId = (sys['systemId'] ?? sys['Id'] ?? sys['systemid'] ?? '').toString();
        final sName = (sys['name'] ?? sys['systemName'] ?? sys['Name'] ?? '').toString();
        if (sysId.isNotEmpty && sName.isNotEmpty) {
          systemNameMap[sysId.toLowerCase()] = sName;
        }
      }

      if (equipments.isEmpty && systems.isNotEmpty) {
        for (var sys in systems) {
          final sysId = (sys['systemId'] ?? sys['Id'] ?? sys['systemid'] ?? '').toString();
          if (sysId.isNotEmpty) {
            try {
              final url = '${AppConfig.provisionBaseUrl}/systems/equipment/$sysId?companyId=$companyId&siteId=$siteId';
              final response = await http.get(
                Uri.parse(url),
                headers: {
                  'Authorization': 'Bearer $token',
                  'Cookie': 'auth_token=$token',
                  'Content-Type': 'application/json',
                },
              );
              if (response.statusCode == 200) {
                final body = jsonDecode(response.body);
                if (body['status'] == 1 && body['data'] is List) {
                  final List<dynamic> list = body['data'];
                  equipments.addAll(list.map((e) => Map<String, dynamic>.from(e)));
                }
              }
            } catch (_) {}
          }
        }
      }

      // 3. Merge local provisioned devices
      try {
        final prefs = await SharedPreferences.getInstance();
        final localDevicesJson = prefs.getString('local_provisioned_devices') ?? '[]';
        final List<dynamic> localList = jsonDecode(localDevicesJson);
        for (var localDev in localList) {
          final localMap = Map<String, dynamic>.from(localDev);
          final String localId = (localMap['id'] ?? localMap['shortId'] ?? '').toString();
          final exists = equipments.any((e) {
            final eId = (e['id'] ?? e['Id'] ?? e['shortId'] ?? e['ShortId'] ?? '').toString();
            return eId.toLowerCase() == localId.toLowerCase();
          });
          if (!exists) {
            equipments.add(localMap);
          }
        }
      } catch (_) {}

      final List<Map<String, dynamic>> deviceList = [];
      final Set<String> addedIds = {};

      // Add Equipments with itemType = 'equipment'
      for (var e in equipments) {
        final Map<String, dynamic> map = Map<String, dynamic>.from(e);
        map['itemType'] = 'equipment';
        final sysId = (map['systemId'] ?? map['SystemId'] ?? '').toString().toLowerCase();
        if ((map['systemName'] == null || map['systemName'].toString().trim().isEmpty) && systemNameMap.containsKey(sysId)) {
          map['systemName'] = systemNameMap[sysId];
        }

        final id = _getPrimaryDeviceId(map);
        if (id.isNotEmpty && !addedIds.contains(id.toLowerCase())) {
          addedIds.add(id.toLowerCase());
          deviceList.add(map);
        }
      }

      // Add Systems with itemType = 'system' ONLY as fallback if no equipments exist
      if (deviceList.isEmpty) {
        for (var s in systems) {
          final Map<String, dynamic> map = Map<String, dynamic>.from(s);
          map['itemType'] = 'system';
          final id = _getPrimaryDeviceId(map);
          if (id.isNotEmpty && !addedIds.contains(id.toLowerCase())) {
            addedIds.add(id.toLowerCase());
            deviceList.add(map);
          }
        }
      }

      // 4. Fetch live AC statuses from /mqtt/ac/status (matching system_view.dart)
      try {
        final zoneId = await AuthService.getZoneId() ?? '';
        final statusUrl = '${AppConfig.provisionBaseUrl}/mqtt/ac/status?companyId=$companyId&siteId=$siteId&zoneId=$zoneId';
        final statusResponse = await http.get(
          Uri.parse(statusUrl),
          headers: {
            'Authorization': 'Bearer $token',
            'Cookie': 'auth_token=$token',
            'Content-Type': 'application/json',
          },
        );

        if (statusResponse.statusCode == 200) {
          final body = jsonDecode(statusResponse.body);
          final List<dynamic> systemsData = body['systems'] ?? [];
          final Map<String, Map<String, dynamic>> statusByEquipmentId = {};
          final Map<String, Map<String, dynamic>> statusByDevId = {};

          for (var sys in systemsData) {
            final List<dynamic> eqs = sys['equipments'] ?? [];
            for (var eq in eqs) {
              final eqId = (eq['equipmentId'] ?? eq['EquipmentId'] ?? eq['id'] ?? eq['Id'] ?? '').toString();
              final devId = (eq['deviceId'] ?? eq['DeviceId'] ?? eq['shortId'] ?? eq['ShortId'] ?? eq['imei'] ?? '').toString();
              if (eqId.isNotEmpty) statusByEquipmentId[eqId.toLowerCase()] = Map<String, dynamic>.from(eq);
              if (devId.isNotEmpty) statusByDevId[devId.toLowerCase()] = Map<String, dynamic>.from(eq);
            }
          }

          // Merge live status into deviceList items
          for (var map in deviceList) {
            final eqId = (map['id'] ?? map['Id'] ?? map['equipmentId'] ?? map['EquipmentId'] ?? '').toString().toLowerCase();
            final pId = _getPrimaryDeviceId(map).toLowerCase();
            final sId = (map['shortId'] ?? map['ShortId'] ?? '').toString().toLowerCase();

            final liveInfo = statusByEquipmentId[eqId] ?? statusByDevId[pId] ?? statusByDevId[sId];
            if (liveInfo != null) {
              final statusStr = (liveInfo['status'] ?? liveInfo['Status'] ?? 'DISCONNECTED').toString().toUpperCase();
              final bool isOnline = statusStr == 'CONNECTED' || statusStr == 'ACTIVE' || statusStr == 'ONLINE';
              map['onOffStatus'] = {
                'isOnline': isOnline,
                'status': statusStr,
                'acStatus': liveInfo['acStatus'] ?? liveInfo['ac'],
                'setTemp': liveInfo['setTemp'] ?? liveInfo['temp'],
              };
              map['status'] = statusStr;
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ [IRLearningConfig] Fetch live status error: $e');
      }

      if (mounted) {
        setState(() {
          _devices = deviceList;
          if (_selectedDeviceId.isEmpty && _devices.isNotEmpty) {
            final first = _devices.first;
            _selectedDeviceId = _getPrimaryDeviceId(first);
          }
          _isLoadingDevices = false;
        });

        if (_selectedDeviceId.isNotEmpty) {
          _onDeviceSelected(_selectedDeviceId);
        }
      }
    } catch (e) {
      debugPrint('❌ [IRLearningConfig] _loadDevices error: $e');
      if (mounted) {
        setState(() => _isLoadingDevices = false);
      }
    }
  }

  void _onDeviceSelected(String newId) async {
    Map<String, dynamic>? selectedMap;
    for (var d in _devices) {
      final pId = _getPrimaryDeviceId(d);
      final sId = (d['shortId'] ?? d['ShortId'] ?? d['equipmentShortId'] ?? '').toString();
      final eqName = _getEquipmentName(d);
      if (pId.toLowerCase() == newId.toLowerCase() ||
          sId.toLowerCase() == newId.toLowerCase() ||
          eqName.toLowerCase() == newId.toLowerCase()) {
        selectedMap = d;
        break;
      }
    }

    final String companyId = (selectedMap?['companyId'] ?? selectedMap?['CompanyId'] ?? '').toString();
    final String imei = (selectedMap?['imei'] ?? selectedMap?['Imei'] ?? newId).toString();
    final String targetId = selectedMap != null ? _getPrimaryDeviceId(selectedMap) : newId;

    if (mounted) {
      setState(() {
        _selectedDeviceId = targetId;
      });
    }

    debugPrint('🌐 [IRLearningConfig] Connecting SSE stream for deviceId=$targetId, companyId=$companyId, imei=$imei');
    await _mqttService.connect(
      deviceId: targetId,
      companyId: companyId.isNotEmpty ? companyId : null,
      imei: imei.isNotEmpty ? imei : targetId,
    );

    _requestStatus();
  }

  void _subscribeToMqttResponses() {
    _stateSub = _mqttService.stateStream.listen((_) {
      if (mounted) setState(() {});
    });
    _mqttService.addListener(() {
      if (mounted) setState(() {});
    });

    _responseSub = _mqttService.responseStream.listen((response) {
      if (!mounted) return;

      switch (response.type) {
        case SirisResponseType.irLearnWaiting:
          // Receiver armed silently
          break;

        case SirisResponseType.irLearnSaved:
          final detail = response.detail ?? response.rawPayload;
          final info = _parseSaveDetail(detail);
          final target = info['target']!;
          final length = info['length']!;

          setState(() {
            _lastSavedTarget = target;
            _lastSavedLength = length;
            _lastSavedMessage = 'Capture Successful! $target ($length)';
          });
          _showCaptureSuccessDialog(detail);
          _requestStatus();
          break;

        case SirisResponseType.irLearnCleared:
          _showSnack('🗑️ IR Signal Cleared Successfully (${response.detail ?? "Done"})', AppColors.online, icon: Icons.check_circle_rounded);
          _requestStatus();
          break;

        case SirisResponseType.irLearnStopped:
          _showSnack('IR Capture Stopped', AppColors.textSecondary);
          _requestStatus();
          break;

        case SirisResponseType.irLearnStatus:
          // Status updated
          break;

        case SirisResponseType.irLearnError:
          _showSnack('ERROR: ${response.detail}', AppColors.offline);
          break;

        default:
          break;
      }
    });
  }


  void _requestStatus() {
    _mqttService.getLearnStatus();
  }

  void _showSnack(String msg, Color bg, {IconData? icon}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon ?? (bg == AppColors.online ? Icons.check_circle_rounded : Icons.info_outline_rounded), color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: bg,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _triggerCaptureOn() {
    setState(() {
      _lastSavedMessage = '';
    });
    _mqttService.learnOn();
    _showSnack('🎉 Capture Command Sent Successfully for POWER ON', AppColors.online);
  }

  void _triggerCaptureOff() {
    setState(() {
      _lastSavedMessage = '';
    });
    _mqttService.learnOff();
    _showSnack('🎉 Capture Command Sent Successfully for POWER OFF', AppColors.online);
  }

  void _triggerCaptureUp(int temp) {
    setState(() {
      _lastSavedMessage = '';
    });
    _mqttService.learnUp(temp);
    _showSnack('🎉 Capture Command Sent Successfully for TEMP UP $temp°C', AppColors.online);
  }

  void _triggerCaptureDown(int temp) {
    setState(() {
      _lastSavedMessage = '';
    });
    _mqttService.learnDown(temp);
    _showSnack('🎉 Capture Command Sent Successfully for TEMP DOWN $temp°C', AppColors.online);
  }

  void _triggerClearOn() async {
    if (await _confirmAction('Clear POWER ON Signal', 'This will delete /ir/on.bin on device.')) {
      _mqttService.clearOn();
      _showSnack('🗑️ Clear Command Sent Successfully for POWER ON', AppColors.coolBlue, icon: Icons.delete_outline_rounded);
    }
  }

  void _triggerClearOff() async {
    if (await _confirmAction('Clear POWER OFF Signal', 'This will delete /ir/off.bin on device.')) {
      _mqttService.clearOff();
      _showSnack('🗑️ Clear Command Sent Successfully for POWER OFF', AppColors.coolBlue, icon: Icons.delete_outline_rounded);
    }
  }

  void _triggerClearUp(int temp) async {
    if (await _confirmAction('Clear UP $temp°C Signal', 'Deletes /ir/up_$temp.bin on device.')) {
      _mqttService.clearUp(temp);
      _showSnack('🗑️ Clear Command Sent Successfully for TEMP UP $temp°C', AppColors.coolBlue, icon: Icons.delete_outline_rounded);
    }
  }

  void _triggerClearDown(int temp) async {
    if (await _confirmAction('Clear DOWN $temp°C Signal', 'Deletes /ir/down_$temp.bin on device.')) {
      _mqttService.clearDown(temp);
      _showSnack('🗑️ Clear Command Sent Successfully for TEMP DOWN $temp°C', AppColors.coolBlue, icon: Icons.delete_outline_rounded);
    }
  }

  void _triggerClearAll() async {
    if (await _confirmAction(
      'CLEAR ALL IR SIGNALS?',
      'WARNING: Destructive command (v5.1). Will delete ON/OFF, all 14 UP steps, and all 14 DOWN steps (30 files total) without further confirmation.',
    )) {
      _mqttService.clearAll();
      _showSnack('🗑️ Erase All Command Sent Successfully: CLEAR_ALL', AppColors.coolBlue, icon: Icons.delete_forever_rounded);
    }
  }

  Future<bool> _confirmAction(String title, String content) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
        content: Text(content, style: GoogleFonts.inter(fontSize: 14)),
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
            child: Text('Confirm Erase', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  Map<String, String> _parseSaveDetail(String detail) {
    String clean = detail.replaceFirst(RegExp(r'.*IR_LEARN_SAVED:?', caseSensitive: false), '').trim();
    String target = clean;
    String lengthStr = '';

    if (clean.contains('LEN:')) {
      final parts = clean.split('LEN:');
      target = parts[0].replaceAll(':', ' ').trim();
      lengthStr = '${parts[1].trim()} bytes';
    }

    if (target.contains('POWER_ON') || target.contains('ON')) {
      target = 'POWER ON';
    } else if (target.contains('POWER_OFF') || target.contains('OFF')) {
      target = 'POWER OFF';
    } else if (target.contains('TEMP_UP') || target.contains('UP')) {
      final match = RegExp(r'(\d+)').firstMatch(target);
      final temp = match != null ? '${match.group(1)}°C' : '';
      target = 'TEMP UP $temp'.trim();
    } else if (target.contains('TEMP_DOWN') || target.contains('DOWN')) {
      final match = RegExp(r'(\d+)').firstMatch(target);
      final temp = match != null ? '${match.group(1)}°C' : '';
      target = 'TEMP DOWN $temp'.trim();
    }

    return {
      'target': target.isNotEmpty ? target : 'IR Signal',
      'length': lengthStr.isNotEmpty ? lengthStr : clean,
      'raw': clean,
    };
  }

  void _showCaptureSuccessDialog(String detail) {
    final info = _parseSaveDetail(detail);
    final target = info['target']!;
    final length = info['length']!;

    _showSnack('🎉 Capture Successful! $target ($length)', AppColors.online, icon: Icons.check_circle_rounded);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.online, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'IR Signal Captured!',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The IR blaster successfully learned and saved the signal.',
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.online.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.online.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  _buildInfoRow('Signal Target', target, AppColors.textSecondary, AppColors.online, isBold: true),
                  const SizedBox(height: 8),
                  _buildInfoRow('Signal Value / Length', length, AppColors.textSecondary, Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.online,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text('Done', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final subtitleColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surface;
    final borderColor = isDark ? AppColors.dividerDark : AppColors.divider;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'IR Remote Signal Config',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Status (LEARN_STATUS)',
            onPressed: _requestStatus,
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Device Picker
            _buildDevicePickerCard(isDark, cardColor, borderColor, textColor, subtitleColor),
            const SizedBox(height: 16),



            // Capture Success Banner
            if (_lastSavedMessage.isNotEmpty) ...[
              _buildSuccessBanner(isDark),
              const SizedBox(height: 16),
            ],

            // Power Signals Card (ON / OFF)
            _buildPowerSignalsCard(isDark, cardColor, borderColor, textColor, subtitleColor),
            const SizedBox(height: 16),

            // Temp Step UP Signals Card (16 - 29°C)
            _buildTempUpCard(isDark, cardColor, borderColor, textColor, subtitleColor),
            const SizedBox(height: 16),

            // Temp Step DOWN Signals Card (17 - 30°C)
            _buildTempDownCard(isDark, cardColor, borderColor, textColor, subtitleColor),
            const SizedBox(height: 24),

            // Erase All & Global Actions
            _buildGlobalActionsCard(isDark, cardColor, borderColor, textColor, subtitleColor),
          ],
        ),
      ),
    );
  }

  bool _isItemOnline(Map<String, dynamic>? item) {
    if (item == null) return false;

    final primaryId = _getPrimaryDeviceId(item);
    final eqName = (item['equipmentName'] ?? item['EquipmentName'] ?? item['name'] ?? item['Name'] ?? '').toString().trim();
    final imei = (item['imei'] ?? item['Imei'] ?? '').toString().trim();
    final devId = (item['deviceId'] ?? item['equipmentId'] ?? item['id'] ?? item['Id'] ?? '').toString().trim();
    final shortId = (item['shortId'] ?? item['ShortId'] ?? item['equipmentShortId'] ?? '').toString().trim();

    // 1. Check live telemetry from MqttService stream across all candidate keys
    for (final id in [primaryId, imei, eqName, devId, shortId, _selectedDeviceId]) {
      if (id.isNotEmpty) {
        final state = _mqttService.getLastStateFor(id);
        if (state != null) {
          return state.isActive;
        }
      }
    }

    // 2. Check onOffStatus object from API payload (same as system_view.dart)
    final statusObj = item['onOffStatus'] ?? item['OnOffStatus'];
    if (statusObj != null && statusObj is Map) {
      final isOnlineVal = statusObj['isOnline'] ?? statusObj['IsOnline'];
      if (isOnlineVal == true || isOnlineVal == 1 || isOnlineVal.toString().toLowerCase() == 'true') {
        return true;
      }
      final statusStr = (statusObj['status'] ?? statusObj['Status'] ?? '').toString().toUpperCase();
      if (statusStr == 'ACTIVE' || statusStr == 'ONLINE' || statusStr == 'CONNECTED') {
        return true;
      }
    }

    final rootStatus = (item['status'] ?? item['Status'] ?? '').toString().toUpperCase();
    if (rootStatus == 'ACTIVE' || rootStatus == 'ONLINE' || rootStatus == 'CONNECTED') {
      return true;
    }

    return false;
  }

  Widget _buildDropdownItemWidget(Map<String, dynamic> d, Color textColor) {
    final bool itemOnline = _isItemOnline(d);
    final Color dotColor = itemOnline ? AppColors.online : AppColors.offline;
    final String label = _getDropdownLabel(d);

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: textColor,
              fontWeight: itemOnline ? FontWeight.w600 : FontWeight.w400,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            softWrap: false,
          ),
        ),
      ],
    );
  }

  String _getDropdownItemValue(Map<String, dynamic> d) {
    final primary = _getPrimaryDeviceId(d);
    if (primary.isNotEmpty) return primary;
    final eqName = _getEquipmentName(d);
    if (eqName.isNotEmpty) return eqName;
    return 'UNKNOWN_${d.hashCode}';
  }

  Widget _buildDevicePickerCard(
    bool isDark,
    Color cardColor,
    Color borderColor,
    Color textColor,
    Color subtitleColor,
  ) {
    // Find selected equipment details
    Map<String, dynamic>? selectedItem;
    for (var d in _devices) {
      final pId = _getDropdownItemValue(d);
      final sId = (d['shortId'] ?? d['ShortId'] ?? d['equipmentShortId'] ?? '').toString();
      final eqName = _getEquipmentName(d);
      if (pId.toLowerCase() == _selectedDeviceId.toLowerCase() ||
          sId.toLowerCase() == _selectedDeviceId.toLowerCase() ||
          eqName.toLowerCase() == _selectedDeviceId.toLowerCase()) {
        selectedItem = d;
        break;
      }
    }

    final category = selectedItem != null ? _getItemCategory(selectedItem) : 'Equipment';
    final equipName = selectedItem != null
        ? _getEquipmentName(selectedItem)
        : (_selectedDeviceId.isNotEmpty ? _selectedDeviceId : 'Default AC Equipment');
    final sysName = selectedItem != null ? _getSystemName(selectedItem) : '';
    final shortId = selectedItem != null
        ? _getEquipmentShortId(selectedItem)
        : _selectedDeviceId;

    // Get true active online status matching system_view.dart
    final SirisDeviceState? liveState = _mqttService.getLastStateFor(_selectedDeviceId);
    final bool isOnline = _isItemOnline(selectedItem);
    final String statusText = isOnline ? 'ACTIVE' : 'INACTIVE';
    final Color statusColor = isOnline ? AppColors.online : AppColors.offline;

    // Safely compute valid dropdown item values and current selection
    final List<DropdownMenuItem<String>> dropdownItems = _devices.isEmpty
        ? [
            DropdownMenuItem<String>(
              value: _mqttService.deviceId.isNotEmpty ? _mqttService.deviceId : 'DEFAULT',
              child: Text(
                _mqttService.deviceId.isNotEmpty ? 'Default Device (${_mqttService.deviceId})' : 'Default MQTT Device',
                style: GoogleFonts.inter(color: textColor),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                softWrap: false,
              ),
            )
          ]
        : _devices.map((d) {
            final val = _getDropdownItemValue(d);
            return DropdownMenuItem<String>(
              value: val,
              child: _buildDropdownItemWidget(d, textColor),
            );
          }).toList();

    String? selectedDropdownValue;
    if (_devices.isNotEmpty) {
      final itemValues = _devices.map((d) => _getDropdownItemValue(d)).toList();
      if (itemValues.contains(_selectedDeviceId)) {
        selectedDropdownValue = _selectedDeviceId;
      } else if (selectedItem != null) {
        selectedDropdownValue = _getDropdownItemValue(selectedItem);
      } else {
        selectedDropdownValue = itemValues.first;
      }
    } else if (_mqttService.deviceId.isNotEmpty) {
      selectedDropdownValue = _mqttService.deviceId;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.router_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Target IR Blaster Device',
                    style: GoogleFonts.outfit(color: textColor, fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ],
              ),
              // Active Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusText,
                      style: GoogleFonts.inter(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _isLoadingDevices
              ? const LinearProgressIndicator(color: AppColors.primary)
              : DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: selectedDropdownValue,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: isDark ? Colors.black12 : Colors.grey.shade50,
                  ),
                  dropdownColor: cardColor,
                  items: dropdownItems,
                  onChanged: (val) {
                    if (val != null) {
                      _onDeviceSelected(val);
                    }
                  },
                ),
          const SizedBox(height: 12),

          // Device Details & Active Status Footer
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.black26 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                _buildInfoRow('Device Category', category, subtitleColor, textColor),
                const SizedBox(height: 6),
                _buildInfoRow('Equipment Name', equipName, subtitleColor, textColor),
                if (sysName.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _buildInfoRow('System Name', sysName, subtitleColor, textColor),
                ],
                const SizedBox(height: 6),
                _buildInfoRow('Target ID / Short ID', shortId.isNotEmpty ? shortId : _selectedDeviceId, subtitleColor, textColor),
                const SizedBox(height: 6),
                _buildInfoRow('Active Status', statusText, subtitleColor, statusColor, isBold: true),
                if (liveState != null) ...[
                  const SizedBox(height: 6),
                  _buildInfoRow('AC Power State', liveState.ac, subtitleColor, liveState.isPowerOn ? AppColors.online : AppColors.textSecondary),
                  if (liveState.setTemp > 0) ...[
                    const SizedBox(height: 6),
                    _buildInfoRow('Set Temperature', '${liveState.setTemp}°C', subtitleColor, textColor),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildSuccessBanner(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.online.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.online),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: AppColors.online,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Capture Successful!',
                      style: GoogleFonts.outfit(
                        color: AppColors.online,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.online.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'SAVED',
                        style: GoogleFonts.inter(color: AppColors.online, fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Signal Target: $_lastSavedTarget • Value / Length: $_lastSavedLength',
                  style: GoogleFonts.inter(
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary, size: 20),
            tooltip: 'Dismiss Banner',
            onPressed: () {
              setState(() {
                _lastSavedMessage = '';
              });
            },
          ),
        ],
      ),
    );
  }



  Widget _buildPowerSignalsCard(
    bool isDark,
    Color cardColor,
    Color borderColor,
    Color textColor,
    Color subtitleColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.power_settings_new_rounded, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Text(
                'Power IR Signals (ON / OFF)',
                style: GoogleFonts.outfit(color: textColor, fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // POWER ON Action Row
          _buildSignalActionRow(
            title: 'POWER ON',
            onCapture: _triggerCaptureOn,
            onClear: _triggerClearOn,
            textColor: textColor,
            subtitleColor: subtitleColor,
          ),
          const Divider(height: 24),

          // POWER OFF Action Row
          _buildSignalActionRow(
            title: 'POWER OFF',
            onCapture: _triggerCaptureOff,
            onClear: _triggerClearOff,
            textColor: textColor,
            subtitleColor: subtitleColor,
          ),
        ],
      ),
    );
  }

  Widget _buildTempUpCard(
    bool isDark,
    Color cardColor,
    Color borderColor,
    Color textColor,
    Color subtitleColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.arrow_upward_rounded, color: AppColors.heatOrange, size: 20),
              const SizedBox(width: 10),
              Text(
                'TEMP UP Step IR Signals (16–29°C)',
                style: GoogleFonts.outfit(color: textColor, fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('Target Temperature: ', style: GoogleFonts.inter(color: subtitleColor, fontSize: 14)),
              const Spacer(),
              DropdownButton<int>(
                value: _selectedUpTemp,
                dropdownColor: cardColor,
                items: List.generate(14, (i) => 16 + i).map((t) {
                  return DropdownMenuItem<int>(
                    value: t,
                    child: Text('$t°C', style: GoogleFonts.inter(color: textColor, fontWeight: FontWeight.w700)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedUpTemp = val);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _triggerCaptureUp(_selectedUpTemp),
                  icon: const Icon(Icons.sensors_rounded, size: 18),
                  label: Text('Capture UP $_selectedUpTemp°C', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.heatOrange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => _triggerClearUp(_selectedUpTemp),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text('Clear', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.offline,
                  side: BorderSide(color: AppColors.offline.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTempDownCard(
    bool isDark,
    Color cardColor,
    Color borderColor,
    Color textColor,
    Color subtitleColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.arrow_downward_rounded, color: AppColors.coolBlue, size: 20),
              const SizedBox(width: 10),
              Text(
                'TEMP DOWN Step IR Signals (17–30°C)',
                style: GoogleFonts.outfit(color: textColor, fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('Target Temperature: ', style: GoogleFonts.inter(color: subtitleColor, fontSize: 14)),
              const Spacer(),
              DropdownButton<int>(
                value: _selectedDownTemp,
                dropdownColor: cardColor,
                items: List.generate(14, (i) => 17 + i).map((t) {
                  return DropdownMenuItem<int>(
                    value: t,
                    child: Text('$t°C', style: GoogleFonts.inter(color: textColor, fontWeight: FontWeight.w700)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedDownTemp = val);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _triggerCaptureDown(_selectedDownTemp),
                  icon: const Icon(Icons.sensors_rounded, size: 18),
                  label: Text('Capture DOWN $_selectedDownTemp°C', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.coolBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => _triggerClearDown(_selectedDownTemp),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: Text('Clear', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.offline,
                  side: BorderSide(color: AppColors.offline.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalActionsCard(
    bool isDark,
    Color cardColor,
    Color borderColor,
    Color textColor,
    Color subtitleColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cleaning_services_rounded, color: AppColors.offline, size: 20),
              const SizedBox(width: 10),
              Text(
                'Bulk Actions & Controls',
                style: GoogleFonts.outfit(color: textColor, fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _mqttService.learnStop(),
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: Text('Stop Capture', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _triggerClearAll,
                  icon: const Icon(Icons.delete_forever_rounded, size: 18),
                  label: Text('Clear All (CLEAR_ALL)', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.offline,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSignalActionRow({
    required String title,
    required VoidCallback onCapture,
    required VoidCallback onClear,
    required Color textColor,
    required Color subtitleColor,
  }) {
    return Row(
      children: [
        Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: onCapture,
          icon: const Icon(Icons.sensors_rounded, size: 16),
          label: Text('Capture', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: onClear,
          icon: const Icon(Icons.delete_outline_rounded, size: 16),
          label: Text('Clear', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.offline,
            side: BorderSide(color: AppColors.offline.withValues(alpha: 0.5)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, Color labelColor, Color valueColor, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 12, color: labelColor, fontWeight: FontWeight.w500),
        ),
        Flexible(
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: valueColor,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}
