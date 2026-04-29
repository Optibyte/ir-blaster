import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:esp/core/constants/colors.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:esp/core/services/auth_service.dart';

/// System View page showing list of AC monitoring systems
class SystemViewPage extends StatefulWidget {
  final void Function(String systemId, String systemName, String systemShortId)? onViewPressed;
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
    // 1. Retrieve stored credentials
    final companyId = await AuthService.getCompanyId() ?? '';
    final siteId = await AuthService.getSiteId() ?? '';
    final bucket = await AuthService.getBucket() ?? '';
    final token = await AuthService.getCookieHeader() ?? '';

    // 2. Construct the API URL
    final apiUrl =
        'https://optibyte.sustainabyte.ai/provisionservice/v1/systems'
        '?companyId=$companyId&siteId=$siteId&bucket=$bucket';

    debugPrint('🌐 [SystemView] Fetching from API: $apiUrl');

    try {
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('📥 [SystemView] Response Status: ${response.statusCode}');
      debugPrint('📥 [SystemView] Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData =
            jsonDecode(response.body) as Map<String, dynamic>;
        final List<dynamic> data = responseData['data'] as List<dynamic>;

        // Filter and map the data (Looking for items where systemType name is "AC Monitoring System")
        final filteredSystems = data
            .where((item) {
              final systemType = item['systemType'] as Map<String, dynamic>?;
              final typeName =
                  (systemType?['name'] as String?)?.toLowerCase() ?? '';
              return typeName.contains('ac monitoring');
            })
            .map((item) {
              final name = item['name'] as String? ?? 'Unknown System';
              final id = item['systemId'] as String? ?? 'No ID';
              final shortId = item['shortId'] as String? ?? name; // Fallback to name
              final systemType = item['systemType'] as Map<String, dynamic>?;
              final typeName = systemType?['name'] as String? ?? 'AC System';

              return SystemItem(
                title: name.toUpperCase(),
                originalName: name,
                equipment:
                    typeName, // Showing the system type name (e.g. "AC Monitoring System")
                systemId: id,
                systemShortId: shortId,
                iconColor: const Color(0xFF3B82F6),
              );
            })
            .toList();

        debugPrint(
          '✅ [SystemView] Filtered ${filteredSystems.length} AC Monitoring systems',
        );

        if (mounted) {
          widget.onCountChanged?.call(filteredSystems.length);
          setState(() {
            systems = filteredSystems;
            isLoading = false;
          });
        }
      } else {
        debugPrint('❌ [SystemView] Error: ${response.body}');
        if (mounted) setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint('❌ [SystemView] Exception during fetch: $e');
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _fetchEquipments(String systemId) async {
    final companyId = await AuthService.getCompanyId() ?? '';
    final siteId = await AuthService.getSiteId() ?? '';
    final bucket = await AuthService.getBucket() ?? '';
    final token = await AuthService.getCookieHeader() ?? '';

    final url =
        'https://optibyte.sustainabyte.ai/provisionservice/v1/systems/equipment/$systemId'
        '?companyId=$companyId&siteId=$siteId&bucket=$bucket';

    debugPrint('🌐 [SystemView] Fetching Equipments: $url');

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      debugPrint(
        '📥 [SystemView] Equipments Response (${response.statusCode}): ${response.body}',
      );
    } catch (e) {
      debugPrint('❌ [SystemView] Exception fetching equipments: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        const SizedBox(height: 16),
        // Systems List
        Expanded(
          child: isLoading
              ? Center(
                  child: CircularProgressIndicator(color: colorScheme.primary),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: systems.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SystemCard(
                        system: systems[index],
                        onViewPressed: (String id, String name, String shortId) {
                          // 1. Fetch equipment details for this system
                          _fetchEquipments(id);

                          // 2. Original callback
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
  final void Function(String systemId, String systemName, String systemShortId) onViewPressed;

  const _SystemCard({required this.system, required this.onViewPressed});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: isDark
            ? LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  const Color(0xFF4A90E2).withValues(alpha: 0.4),
                  const Color(0xFF1E3A8A).withValues(alpha: 0.6),
                ],
              )
            : LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  colorScheme.primary.withValues(alpha: 0.05),
                  colorScheme.primary.withValues(alpha: 0.1),
                ],
              ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : colorScheme.primary.withValues(alpha: 0.1),
          width: 1,
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: system.iconColor.withValues(alpha: 0.1),
            ),
            child: Center(
              child: Icon(Icons.ac_unit, color: system.iconColor, size: 24),
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  system.title,
                  style: GoogleFonts.poppins(
                    color: isDark ? Colors.white : colorScheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  system.equipment,
                  style: GoogleFonts.poppins(
                    color: (isDark ? Colors.white : colorScheme.primary)
                        .withValues(alpha: 0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // View Button
          GestureDetector(
            onTap: () {
              debugPrint(
                '[SystemView] Tapped systemId: ${system.systemId}, shortId: ${system.systemShortId}, name: ${system.originalName}',
              );
              onViewPressed(system.systemId, system.originalName, system.systemShortId);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? AppColors.button : colorScheme.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'View',
                style: GoogleFonts.poppins(
                  color: isDark ? Colors.black : Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
