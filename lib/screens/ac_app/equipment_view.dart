import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:ir_blaster_ac/core/config/app_config.dart';

/// Equipment View page — mirrors the web's /equipments-view page.
/// Shows all equipment grouped by their system type, with real-time status.
class EquipmentViewPage extends StatefulWidget {
  final void Function(String equipmentId, String name, String systemId,
      String systemShortId)? onEquipmentTap;
  final void Function(int count)? onCountChanged;

  const EquipmentViewPage({super.key, this.onEquipmentTap, this.onCountChanged});

  @override
  State<EquipmentViewPage> createState() => _EquipmentViewPageState();
}

class _EquipmentViewPageState extends State<EquipmentViewPage> {
  List<Map<String, dynamic>> _allEquipments = [];
  Map<String, List<Map<String, dynamic>>> _groupedBySystem = {};
  Map<String, String> _systemNames = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchEquipments();
  }

  Future<void> _fetchEquipments() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final companyId = await AuthService.getCompanyId() ?? '';
      final siteId = await AuthService.getSiteId() ?? '';
      final token = await AuthService.getCookieHeader() ?? '';

      // 1. Fetch all AC equipments
      final queryParams = <String>[];
      if (companyId.isNotEmpty &&
          companyId != 'null' &&
          companyId != 'undefined') {
        queryParams.add('companyId=$companyId');
      }
      if (siteId.isNotEmpty && siteId != 'null' && siteId != 'undefined') {
        queryParams.add('siteId=$siteId');
      }
      final queryString =
          queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
      final url =
          '${AppConfig.provisionBaseUrl}/equipments/ac/by-company$queryString';

      debugPrint('🌐 [EquipmentView] Fetching equipments: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Cookie': 'auth_token=$token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        debugPrint(
            '⚠️ [EquipmentView] HTTP ${response.statusCode}: ${response.body}');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final body = jsonDecode(response.body);
      if (body['status'] != 1 || body['data'] == null) {
        debugPrint('⚠️ [EquipmentView] No data: status=${body['status']}');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final List<dynamic> rawList = body['data'];
      final allEquips =
          rawList.map((e) => Map<String, dynamic>.from(e)).toList();
      debugPrint(
          '✅ [EquipmentView] Fetched ${allEquips.length} equipments');

      // 2. Fetch systems map (for system names)
      Map<String, String> sysNames = {};
      try {
        final hasCompanyId = companyId.isNotEmpty &&
            companyId != 'null' &&
            companyId != 'undefined';
        final systemsUrl = hasCompanyId
            ? '${AppConfig.provisionBaseUrl}/systems/$companyId?siteId=$siteId'
            : '${AppConfig.provisionBaseUrl}/systems?companyId=$companyId&siteId=$siteId';

        final sysResponse = await http.get(
          Uri.parse(systemsUrl),
          headers: {
            'Authorization': 'Bearer $token',
            'Cookie': 'auth_token=$token',
            'Content-Type': 'application/json',
          },
        );

        if (sysResponse.statusCode == 200) {
          final sBody = jsonDecode(sysResponse.body);
          if (sBody['status'] == 1 && sBody['data'] != null) {
            for (var s in sBody['data']) {
              final sId =
                  (s['systemId'] ?? s['SystemId'] ?? s['id'] ?? s['Id'])
                      ?.toString();
              final sName = (s['name'] ??
                      s['Name'] ??
                      s['systemName'] ??
                      s['SystemName']) as String? ??
                  'Unknown System';
              if (sId != null) {
                sysNames[sId] = sName;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('⚠️ [EquipmentView] Error fetching systems: $e');
      }

      // 3. Group equipments by systemId
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (var eq in allEquips) {
        final sysId = (eq['systemId'] ?? eq['SystemId'] ?? '').toString();
        if (sysId.isEmpty) continue;
        grouped.putIfAbsent(sysId, () => []);
        grouped[sysId]!.add(eq);
      }

      if (mounted) {
        widget.onCountChanged?.call(allEquips.length);
        setState(() {
          _allEquipments = allEquips;
          _groupedBySystem = grouped;
          _systemNames = sysNames;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [EquipmentView] Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? const Color(0xFF120E1F) : Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Expanded(
            child: _isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(color: Color(0xFF6CC042)),
                  )
                : RefreshIndicator(
                    color: const Color(0xFF6CC042),
                    onRefresh: _fetchEquipments,
                    child: _allEquipments.isEmpty
                        ? _buildEmptyState(isDark)
                        : _buildEquipmentGrid(isDark),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics()),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.3),
        Center(
          child: Column(
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 56,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.1)),
              const SizedBox(height: 16),
              Text(
                'No Equipment Found',
                style: GoogleFonts.outfit(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.4)
                      : Colors.black.withValues(alpha: 0.35),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Pull down to refresh',
                style: GoogleFonts.outfit(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.25)
                      : Colors.black.withValues(alpha: 0.2),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEquipmentGrid(bool isDark) {
    final systemIds = _groupedBySystem.keys.toList();
    final cardColor = isDark ? const Color(0xFF1E1A33) : const Color(0xFFF5F5F7);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);
    final subtitleColor = isDark
        ? Colors.white.withValues(alpha: 0.5)
        : Colors.black.withValues(alpha: 0.5);

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: systemIds.length,
      itemBuilder: (context, sysIndex) {
        final sysId = systemIds[sysIndex];
        final equipments = _groupedBySystem[sysId]!;
        final systemName = _systemNames[sysId] ?? 'AC Monitoring System';

        // Determine system icon based on system name
        IconData systemIcon = Icons.ac_unit_rounded;
        Color systemIconColor = const Color(0xFF6CC042);
        if (systemName.toLowerCase().contains('light')) {
          systemIcon = Icons.lightbulb_outline_rounded;
          systemIconColor = const Color(0xFFFBBF24);
        } else if (systemName.toLowerCase().contains('energy') ||
            systemName.toLowerCase().contains('ems')) {
          systemIcon = Icons.bolt_rounded;
          systemIconColor = const Color(0xFF0EA5E9);
        } else if (systemName.toLowerCase().contains('diesel') ||
            systemName.toLowerCase().contains('dg')) {
          systemIcon = Icons.local_gas_station_rounded;
          systemIconColor = const Color(0xFFF97316);
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // System Header
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: systemIconColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(systemIcon,
                          color: systemIconColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        systemName,
                        style: GoogleFonts.outfit(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6CC042)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Equipments: ${equipments.length}',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFF6CC042),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Equipment Cards Grid
              LayoutBuilder(
                builder: (context, constraints) {
                  final crossAxisCount =
                      constraints.maxWidth > 600 ? 3 : 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: equipments.map((eq) {
                      final name =
                          (eq['name'] ?? eq['Name'] ?? 'Unknown').toString();
                      final shortId = (eq['shortId'] ??
                                  eq['ShortId'] ??
                                  eq['equipmentShortId'] ??
                                  '')
                              .toString();
                      final equipmentId =
                          (eq['equipmentId'] ?? eq['EquipmentId'] ?? '')
                              .toString();
                      final acType =
                          (eq['acType'] ?? eq['AcType'] ?? '').toString();

                      // Status
                      final statusObj =
                          eq['onOffStatus'] ?? eq['OnOffStatus'];
                      final isOnlineVal = statusObj != null
                          ? (statusObj['isOnline'] ??
                              statusObj['IsOnline'])
                          : null;
                      final bool isOnline = isOnlineVal == true ||
                          isOnlineVal == 1 ||
                          isOnlineVal.toString().toLowerCase() == 'true';
                      final acStatusVal = statusObj != null
                          ? (statusObj['acStatus'] ??
                              statusObj['AcStatus'] ??
                              'OFF')
                          : 'OFF';
                      final bool isRunning = isOnline &&
                          acStatusVal.toString().toUpperCase() == 'ON';

                      Color statusColor;
                      String statusLabel;
                      if (!isOnline) {
                        statusColor = const Color(0xFF94A3B8);
                        statusLabel = 'Offline';
                      } else if (isRunning) {
                        statusColor = const Color(0xFF6CC042);
                        statusLabel = 'Running';
                      } else {
                        statusColor = const Color(0xFFEF4444);
                        statusLabel = 'OFF';
                      }

                      final cardWidth =
                          (constraints.maxWidth - (crossAxisCount - 1) * 12) /
                              crossAxisCount;

                      return GestureDetector(
                        onTap: () {
                          widget.onEquipmentTap?.call(
                            equipmentId,
                            name,
                            sysId,
                            shortId,
                          );
                        },
                        child: Container(
                          width: cardWidth,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(16),
                            border:
                                Border.all(color: borderColor, width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top row: icon + status
                              Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: systemIconColor
                                          .withValues(alpha: 0.1),
                                      borderRadius:
                                          BorderRadius.circular(10),
                                      border: Border.all(
                                        color: systemIconColor
                                            .withValues(alpha: 0.2),
                                      ),
                                    ),
                                    child: Icon(systemIcon,
                                        color: systemIconColor, size: 20),
                                  ),
                                  const Spacer(),
                                  // Status dot
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: statusColor,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: statusColor
                                              .withValues(alpha: 0.5),
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              // Equipment name
                              Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  color: textColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              // ID badge
                              if (shortId.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF0E0B16)
                                        : Colors.white,
                                    borderRadius:
                                        BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white
                                              .withValues(alpha: 0.06)
                                          : Colors.black
                                              .withValues(alpha: 0.08),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'ID: ',
                                        style: GoogleFonts.outfit(
                                          color: subtitleColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Flexible(
                                        child: Text(
                                          shortId,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.jetBrainsMono(
                                            color: const Color(0xFF6CC042),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 8),
                              // Status pill
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: statusColor
                                          .withValues(alpha: 0.12),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      statusLabel,
                                      style: GoogleFonts.outfit(
                                        color: statusColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (acType.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        acType,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.outfit(
                                          color: subtitleColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
