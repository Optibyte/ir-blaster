import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:ir_blaster_ac/core/config/app_config.dart';

/// System View page showing list of AC monitoring systems with their equipments
class SystemViewPage extends StatefulWidget {
  final void Function(String systemId, String systemName, String systemShortId)?
      onViewPressed;
  final void Function(int count)? onCountChanged;

  const SystemViewPage({super.key, this.onViewPressed, this.onCountChanged});

  @override
  State<SystemViewPage> createState() => _SystemViewPageState();
}

class _SystemViewPageState extends State<SystemViewPage> {
  List<SystemItem> systems = [];
  bool isLoading = true;

  /// Map of systemId -> list of equipment data from the equipments API
  Map<String, List<Map<String, dynamic>>> _equipmentsBySystem = {};

  @override
  void initState() {
    super.initState();
    _fetchSystemsAndEquipments();
  }

  /// Fetches equipments from the working /equipments/ac/by-company endpoint,
  /// then derives systems by grouping equipments by systemId.
  /// This bypasses the production reverse proxy which blocks /systems/* endpoints.
  Future<void> _fetchSystemsAndEquipments() async {
    if (mounted) setState(() => isLoading = true);

    try {
      final companyId = await AuthService.getCompanyId() ?? '';
      final siteId = await AuthService.getSiteId() ?? '';
      final token = await AuthService.getCookieHeader() ?? '';

      // Fetch all equipments from the only working production endpoint
      final allEquips = await _fetchAllEquipments(companyId, siteId, token);
      debugPrint('🌐 [SystemView] Fetched ${allEquips.length} total equipments from by-company endpoint');

      // Group equipments by systemId and derive system list
      final Map<String, List<Map<String, dynamic>>> equipMap = {};
      final Map<String, SystemItem> systemMap = {};

      for (var eq in allEquips) {
        final sysId = (eq['systemId'] ?? eq['SystemId'] ?? '').toString();
        if (sysId.isEmpty) continue;

        // Add equipment to its system group
        equipMap.putIfAbsent(sysId, () => []);
        equipMap[sysId]!.add(eq);

        // Create a SystemItem from equipment data if we haven't seen this systemId yet
        if (!systemMap.containsKey(sysId)) {
          final eqName = (eq['name'] ?? eq['Name'] ?? '').toString();
          systemMap[sysId] = SystemItem(
            title: 'AC MONITORING SYSTEM',
            originalName: 'System ${systemMap.length + 1}',
            equipment: 'AC Monitoring System',
            systemId: sysId,
            systemShortId: sysId.length >= 8 ? sysId.substring(0, 8) : sysId,
            iconColor: const Color(0xFF6CC042),
          );
        }
      }

      final fetchedSystems = systemMap.values.toList();
      debugPrint('✅ [SystemView] Derived ${fetchedSystems.length} systems from ${allEquips.length} equipments');

      if (mounted) {
        widget.onCountChanged?.call(fetchedSystems.length);
        setState(() {
          systems = fetchedSystems;
          _equipmentsBySystem = equipMap;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [SystemView] Error in _fetchSystemsAndEquipments: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  /// Fetches all AC equipments for the company/site using the proxy-safe endpoint
  Future<List<Map<String, dynamic>>> _fetchAllEquipments(
      String companyId, String siteId, String token) async {
    final queryParams = <String>[];
    if (companyId.isNotEmpty && companyId != 'null' && companyId != 'undefined') {
      queryParams.add('companyId=$companyId');
    }
    if (siteId.isNotEmpty && siteId != 'null' && siteId != 'undefined') {
      queryParams.add('siteId=$siteId');
    }
    final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final url = '${AppConfig.provisionBaseUrl}/equipments/ac/by-company$queryString';

    debugPrint('🌐 [SystemView] Fetching All Equipments: $url');

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Cookie': 'auth_token=$token',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('🌐 [SystemView] Equipments response code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['status'] == 1 && body['data'] != null) {
          final List<dynamic> list = body['data'];
          debugPrint('✅ [SystemView] Equipment API returned ${list.length} items');
          return list.map((e) => Map<String, dynamic>.from(e)).toList();
        } else {
          debugPrint('⚠️ [SystemView] Equipment API returned status=${body['status']}, data is null: ${body['data'] == null}');
        }
      } else {
        debugPrint('⚠️ [SystemView] Equipment API returned HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ [SystemView] Error fetching equipments: $e');
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color:
            isDark ? const Color(0xFF120E1F) : Colors.white, // Theme background
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Section (Reduced as per user request to remove 'Equipment View' text)
          const SizedBox(height: 24),

          // Systems List
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF6CC042)),
                  )
                : RefreshIndicator(
                    color: const Color(0xFF6CC042),
                    onRefresh: _fetchSystemsAndEquipments,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics()),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      itemCount: systems.length,
                      itemBuilder: (context, index) {
                        final system = systems[index];
                        final equipments =
                            _equipmentsBySystem[system.systemId] ?? [];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _SystemCardWithEquipments(
                            system: system,
                            equipments: equipments,
                            onViewPressed:
                                (String id, String name, String shortId) {
                              if (widget.onViewPressed != null) {
                                widget.onViewPressed!(id, name, shortId);
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class SystemItem {
  final String title;
  final String originalName;
  final String equipment;
  final String systemId;
  final String systemShortId;
  final Color iconColor;

  SystemItem({
    required this.title,
    required this.originalName,
    required this.equipment,
    required this.systemId,
    required this.systemShortId,
    required this.iconColor,
  });
}

/// A system card that shows the system header + its equipment items below
class _SystemCardWithEquipments extends StatelessWidget {
  final SystemItem system;
  final List<Map<String, dynamic>> equipments;
  final void Function(String systemId, String systemName, String systemShortId)
      onViewPressed;

  const _SystemCardWithEquipments({
    required this.system,
    required this.equipments,
    required this.onViewPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);
    final pillBg = isDark ? const Color(0xFF0E0B16) : Colors.white;
    final pillBorder = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.08);
    final pillText = isDark
        ? Colors.white.withValues(alpha: 0.9)
        : const Color(0xFF1B172E);
    final subtitleColor = isDark
        ? Colors.white.withValues(alpha: 0.5)
        : Colors.black.withValues(alpha: 0.5);

    return GestureDetector(
      onTap: () => onViewPressed(
          system.systemId, system.originalName, system.systemShortId),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── System Header ──
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6CC042).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color:
                              const Color(0xFF6CC042).withValues(alpha: 0.2)),
                    ),
                    child: const Icon(
                      Icons.apartment_rounded,
                      color: Color(0xFF6CC042),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 20),
                  // System info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          system.equipment,
                          style: GoogleFonts.outfit(
                            color: textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // System Name Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: pillBg,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: pillBorder),
                          ),
                          child: Text(
                            system.originalName,
                            style: GoogleFonts.outfit(
                              color: pillText,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Equipment count badge
                  if (equipments.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6CC042).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${equipments.length}',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFF6CC042),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Equipment List ──
            if (equipments.isNotEmpty) ...[
              // Divider
              Container(
                height: 0.5,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.06),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.ac_unit_rounded,
                        size: 14,
                        color:
                            const Color(0xFF6CC042).withValues(alpha: 0.7)),
                    const SizedBox(width: 6),
                    Text(
                      '${equipments.length} Equipment${equipments.length == 1 ? '' : 's'}',
                      style: GoogleFonts.outfit(
                        color: subtitleColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Equipment items
              ...equipments.map((e) {
                final name =
                    (e['name'] ?? e['Name'] ?? 'Unknown Equipment').toString();
                final acType =
                    (e['acType'] ?? e['AcType'] ?? '').toString();
                final statusObj = e['onOffStatus'] ?? e['OnOffStatus'];
                
                final isOnlineVal = statusObj != null ? (statusObj['isOnline'] ?? statusObj['IsOnline']) : null;
                final bool isOnline = isOnlineVal == true || isOnlineVal == 1 || isOnlineVal.toString().toLowerCase() == 'true';
                
                final acStatusVal = statusObj != null ? (statusObj['acStatus'] ?? statusObj['AcStatus'] ?? 'OFF') : 'OFF';
                final String acStatus = isOnline ? acStatusVal.toString() : '';
                final bool isRunning = isOnline && acStatus.toUpperCase() == 'ON';

                // Status color and label
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

                // Temperature & Humidity
                final temp = statusObj != null ? (statusObj['temperature'] ?? statusObj['Temperature']) : null;
                final hum = statusObj != null ? (statusObj['humidity'] ?? statusObj['Humidity']) : null;

                double? tempVal;
                if (temp != null) {
                  if (temp is num) {
                    tempVal = temp.toDouble();
                  } else {
                    tempVal = double.tryParse(temp.toString());
                  }
                }

                double? humVal;
                if (hum != null) {
                  if (hum is num) {
                    humVal = hum.toDouble();
                  } else {
                    humVal = double.tryParse(hum.toString());
                  }
                }

                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.03)
                          : Colors.black.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        // Status dot
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: statusColor.withValues(alpha: 0.4),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Equipment name + type
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: GoogleFonts.outfit(
                                  color: textColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (acType.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  acType,
                                  style: GoogleFonts.outfit(
                                    color: subtitleColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Telemetry chips
                        if (isOnline && tempVal != null) ...[
                          _telemetryChip(
                              '${tempVal.toStringAsFixed(1)}°C',
                              Icons.thermostat_rounded,
                              const Color(0xFF0EA5E9),
                              isDark),
                          const SizedBox(width: 6),
                        ],
                        if (isOnline && humVal != null) ...[
                          _telemetryChip(
                              '${humVal.toStringAsFixed(0)}%',
                              Icons.water_drop_rounded,
                              const Color(0xFF8B5CF6),
                              isDark),
                          const SizedBox(width: 8),
                        ],
                        // Status pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
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
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],

            // No equipments fallback
            if (equipments.isEmpty)
              Padding(
                padding: const EdgeInsets.only(
                    left: 20, right: 20, bottom: 16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 14, color: subtitleColor),
                    const SizedBox(width: 6),
                    Text(
                      'No equipments found',
                      style: GoogleFonts.outfit(
                        color: subtitleColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _telemetryChip(
      String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
