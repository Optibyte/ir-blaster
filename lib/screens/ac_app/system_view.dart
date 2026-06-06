import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:ir_blaster_ac/core/config/app_config.dart';
import 'package:ir_blaster_ac/core/services/local_cache_service.dart';

/// System View page showing list of AC monitoring systems
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

  @override
  void initState() {
    super.initState();
    _fetchAndFilterSystems();
  }


  Future<void> _fetchAndFilterSystems() async {
    final companyId = await AuthService.getCompanyId() ?? '';
    final siteId = await AuthService.getSiteId() ?? '';
    final bucket = await AuthService.getBucket() ?? '';
    final token = await AuthService.getCookieHeader() ?? '';

    final apiUrl = '${AppConfig.provisionBaseUrl}/systems'
        '?companyId=$companyId&siteId=$siteId';

    debugPrint('🌐 [SystemView] Fetching Systems: $apiUrl');

    try {
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Cookie': 'auth_token=$token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData =
            jsonDecode(response.body) as Map<String, dynamic>;
        final List<dynamic> data = responseData['data'] as List<dynamic>;

        final filteredSystems = data.where((item) {
          final systemType = (item['systemType'] ?? item['SystemType'])
              as Map<String, dynamic>?;
          final typeName =
              ((systemType?['name'] ?? systemType?['Name']) as String?)
                      ?.toLowerCase() ??
                  '';

          // Only show AC Monitoring systems
          return typeName.contains('ac monitoring') ||
              typeName.contains('ac_monitoring') ||
              typeName.contains('acmonitoring');
        }).map((item) {
          final name = (item['name'] ??
                  item['Name'] ??
                  item['systemName'] ??
                  item['SystemName']) as String? ??
              'Unknown System';
          final id = (item['systemId'] ??
                  item['SystemId'] ??
                  item['id'] ??
                  item['Id']) as String? ??
              'No ID';
          final shortId = (item['shortId'] ??
                  item['ShortId'] ??
                  item['systemShortId'] ??
                  item['SystemShortId']) as String? ??
              name;
          final systemType = (item['systemType'] ?? item['SystemType'])
              as Map<String, dynamic>?;
          final typeName =
              (systemType?['name'] ?? systemType?['Name']) as String? ??
                  'AC Monitoring System';

          debugPrint(
              '✅ [SystemView] Mapped System: $name ($id) with shortId: $shortId');

          return SystemItem(
            title: name.toUpperCase(),
            originalName: name,
            equipment: typeName,
            systemId: id,
            systemShortId: shortId,
            iconColor: const Color(0xFF6CC042),
          );
        }).toList();

        if (mounted) {
          widget.onCountChanged?.call(filteredSystems.length);
          setState(() {
            systems = filteredSystems;
            isLoading = false;
          });
        }
      } else {
        if (mounted) {
          widget.onCountChanged?.call(0);
          setState(() {
            systems = [];
            isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ [SystemView] Error: $e');
      if (mounted) {
        widget.onCountChanged?.call(0);
        setState(() {
          systems = [];
          isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchEquipments(String systemId) async {
    // No-op or keep for background sync if needed
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF120E1F) : Colors.white, // Theme background
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
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    itemCount: systems.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _SystemCard(
                          system: systems[index],
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

class _SystemCard extends StatelessWidget {
  final SystemItem system;
  final void Function(String systemId, String systemName, String systemShortId)
      onViewPressed;

  const _SystemCard({required this.system, required this.onViewPressed});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = Theme.of(context).cardColor;
    final borderColor = isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05);
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);
    final pillBg = isDark ? const Color(0xFF0E0B16) : Colors.white;
    final pillBorder = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.08);
    final pillText = isDark ? Colors.white.withOpacity(0.9) : const Color(0xFF1B172E);

    return GestureDetector(
      onTap: () => onViewPressed(
          system.systemId, system.originalName, system.systemShortId),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor, // Dynamic Card Background
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Icon matching Web
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFF6CC042).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: const Color(0xFF6CC042).withOpacity(0.2)),
              ),
              child: const Icon(
                Icons.apartment_rounded,
                color: Color(0xFF6CC042),
                size: 28,
              ),
            ),
            const SizedBox(width: 20),
            // Content
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
                  // System Name Badge matching requested layout
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: pillBg, // Dynamic Pill
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
          ],
        ),
      ),
    );
  }
}
