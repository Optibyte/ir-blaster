import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:ir_blaster_ac/core/config/app_config.dart';
import 'package:ir_blaster_ac/core/services/local_cache_service.dart';

// Removed unused imports

// DashboardScreen manages its own tabs — no HomePage rebuild on tab switch
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _tabIndex = 0; // 0=Status, 1=Trends, 2=Schedule

  bool _isLoading = true;
  Map<String, dynamic>? _summary;
  List<dynamic> _equipments = [];
  Map<String, String> _systemsMap = {};
  Map<String, List<dynamic>> _groupedEquipments = {};

  @override
  void initState() {
    super.initState();
    _loadCachedData();
    _fetchSummaryData();
  }

  Future<void> _loadCachedData() async {
    final cached = await LocalCacheService.getDashboardData();
    if (cached != null && mounted) {
      final data = cached['data'];
      final timestamp = cached['timestamp'];
      final diff = DateTime.now().millisecondsSinceEpoch - (timestamp as int);

      // Only show cache if it's less than 24 hours old (optional)
      if (diff < 86400000) {
        setState(() {
          _summary = data['summary'];
          _equipments = data['equipments'];
          _groupedEquipments =
              _processEquipments(data['equipments'], data['systemsMap'] ?? {});
          _isLoading = false; // Stop loading immediately as we have cache
        });
      }
    }
  }

  Map<String, List<dynamic>> _processEquipments(
      List<dynamic> equipments, Map<String, dynamic> sMap) {
    final Map<String, List<dynamic>> gMap = {};
    for (var e in equipments) {
      final sId = e['systemId'];
      final sysName = (sId != null && sMap.containsKey(sId))
          ? sMap[sId]!
          : (e['acType'] ?? 'General System');
      gMap.putIfAbsent(sysName, () => []).add(e);
    }
    return gMap;
  }

  Future<void> _fetchSummaryData() async {
    try {
      final companyId = await AuthService.getCompanyId() ?? '';
      final siteId = await AuthService.getSiteId() ?? '';
      final zoneId = await AuthService.getZoneId() ?? '';
      final bucket = await AuthService.getBucket() ?? '';
      final token = await AuthService.getCookieHeader() ?? '';

      final url =
          '${AppConfig.provisionBaseUrl}/equipments/ac/by-company?companyId=$companyId&siteId=$siteId&zoneId=$zoneId';
      debugPrint('🌐 [Dashboard] Fetching AC Summary: $url');

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
        if (body['status'] == 1) {
          // Also fetch systems to map systemId to Name
          final systemsUrl =
              '${AppConfig.provisionBaseUrl}/systems?companyId=$companyId&siteId=$siteId';
          final systemsResponse = await http.get(
            Uri.parse(systemsUrl),
            headers: {
              'Authorization': 'Bearer $token',
              'Cookie': 'auth_token=$token',
              'Content-Type': 'application/json',
            },
          );

          Map<String, String> sMap = {};
          if (systemsResponse.statusCode == 200) {
            final sBody = jsonDecode(systemsResponse.body);
            if (sBody['status'] == 1 && sBody['data'] != null) {
              final currentBucket = bucket.toLowerCase();
              for (var s in sBody['data']) {
                final sShortId = (s['shortId'] ??
                            s['ShortId'] ??
                            s['systemShortId'] ??
                            s['SystemShortId'] as String?)
                        ?.toLowerCase() ??
                    '';
                final sId =
                    (s['systemId'] ?? s['SystemId'] ?? s['id'] ?? s['Id'])
                        ?.toString();
                final sName = (s['name'] ??
                        s['Name'] ??
                        s['systemName'] ??
                        s['SystemName']) as String? ??
                    'Unknown System';

                // Trust the API's filtering. If it's in the response, include it.
                if (sId != null) {
                  sMap[sId] = sName;
                }
              }
            }
          }

          // Pre-calculate grouping and filter equipments locally
          final Map<String, List<dynamic>> gMap = {};
          final List<dynamic> allEquipments = body['data'] ?? [];
          final List<dynamic> filteredEquipments = [];

          for (var e in allEquipments) {
            final sId = e['systemId'];
            // Only include equipment if its system is in our filtered map (bucket matched)
            if (sId != null && sMap.containsKey(sId)) {
              final sysName = sMap[sId]!;
              gMap.putIfAbsent(sysName, () => []).add(e);
              filteredEquipments.add(e);
            }
          }

          // Recalculate summary based on filtered equipments
          int total = filteredEquipments.length;
          int on = 0;
          int off = 0;
          int notConnected = 0;

          for (var e in filteredEquipments) {
            final status = e['onOffStatus'];
            if (status != null && status['isOnline'] == true) {
              if (status['acStatus'] == 'ON') {
                on++;
              } else {
                off++;
              }
            } else {
              notConnected++;
            }
          }

          final localSummary = {
            'total': total,
            'on': on,
            'off': off,
            'notConnected': notConnected,
          };

          if (mounted) {
            setState(() {
              _summary = localSummary;
              _equipments = filteredEquipments;
              _systemsMap = sMap;
              _groupedEquipments = gMap;
              _isLoading = false;
            });

            // Save to cache for next time
            LocalCacheService.saveDashboardData({
              'summary': localSummary,
              'equipments': filteredEquipments,
              'systemsMap': sMap,
            });
          }
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('❌ [Dashboard] Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Tab Chips ──────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(
            children: [
              _chip('Summary', 0, isDark),
              const SizedBox(width: 10),
              _chip('Trends', 1, isDark),
            ],
          ),
        ),

        // ── Tab Body ──────────────────────────────────────
        Expanded(
          child: _buildBody(isDark, textColor),
        ),
      ],
    );
  }

  Widget _buildBody(bool isDark, Color textColor) {
    switch (_tabIndex) {
      case 1:
        return _TrendsView(isDark: isDark, textColor: textColor);
      default:
        return _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF6CC042)))
            : _StatusView(
                isDark: isDark,
                textColor: textColor,
                summary: _summary ?? {},
                equipments: _equipments,
                systemsMap: _systemsMap,
                groupedEquipments: _groupedEquipments,
              );
    }
  }

  Widget _chip(String label, int index, bool isDark) {
    final isActive = _tabIndex == index;
    const primary = Color(0xFF6CC042);
    return GestureDetector(
      onTap: () => setState(() => _tabIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? primary.withValues(alpha: isDark ? 0.2 : 0.1)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.black.withValues(alpha: 0.02)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive
                ? primary
                : (isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05)),
            width: 1.5,
          ),
          boxShadow: [
            if (isActive)
              BoxShadow(
                color: primary.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            color: isActive
                ? (isDark ? Colors.white : primary)
                : (isDark ? Colors.white54 : Colors.black45),
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// STATUS VIEW
// ──────────────────────────────────────────────────────────────
class _StatusView extends StatelessWidget {
  final bool isDark;
  final Color textColor;
  final Map<String, dynamic> summary;
  final List<dynamic> equipments;
  final Map<String, String> systemsMap;
  final Map<String, List<dynamic>> groupedEquipments;

  const _StatusView({
    required this.isDark,
    required this.textColor,
    required this.summary,
    required this.equipments,
    required this.systemsMap,
    required this.groupedEquipments,
  });

  Widget _smallMetricCard(
      String title, int value, Color color, IconData icon, Color cardColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 10),
          Text('$value',
              style: GoogleFonts.poppins(
                  color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
          Text(title,
              style: GoogleFonts.poppins(
                  color: textColor.withValues(alpha: 0.5),
                  fontSize: 9,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? const Color(0xFF2A244D) : Colors.white;

    final segments = [
      ChartSegment(
          'Running', (summary['on'] ?? 0).toDouble(), const Color(0xFF6CC042)),
      ChartSegment(
          'Offline', (summary['off'] ?? 0).toDouble(), const Color(0xFFEF4444)),
      ChartSegment('Not Connected', (summary['notConnected'] ?? 0).toDouble(),
          const Color(0xFF94A3B8)),
    ];

    final int totalUnits = summary['total'] ?? 0;
    final int notConnUnits = summary['notConnected'] ?? 0;
    final int connectedUnits = totalUnits - notConnUnits;
    final int runningUnits = summary['on'] ?? 0;
    final String runningPercentage =
        totalUnits > 0 ? '${(runningUnits * 100 / totalUnits).round()}%' : '0%';

    // Group by systemName (Already pre-calculated in State)
    final grouped = groupedEquipments;

    final floors = grouped.entries.map((entry) {
      final list = entry.value;
      int running = 0, offline = 0, notConn = 0;
      for (var item in list) {
        final status = item['onOffStatus'];
        if (status != null && status['isOnline'] == true) {
          if (status['acStatus'] == 'ON') {
            running++;
          } else {
            offline++;
          }
        } else {
          notConn++;
        }
      }
      return _FloorData(entry.key, list.length, running, 0, offline + notConn);
    }).toList();

    // Map to popup data
    final allEquipment = equipments.map((e) {
      final statusObj = e['onOffStatus'];
      String status = 'Offline';
      if (statusObj != null && statusObj['isOnline'] == true) {
        status = statusObj['acStatus'] == 'ON' ? 'Running' : 'Offline';
      }
      return _EquipData(e['name'] ?? 'Unknown', e['systemId'] ?? '', status,
          e['acType'] ?? 'General AC');
    }).toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header('Overview'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _smallMetricCard(
                      'Total AC',
                      totalUnits,
                      const Color(0xFF0EA5E9),
                      Icons.grid_view_rounded,
                      cardColor)),
              const SizedBox(width: 10),
              Expanded(
                  child: _smallMetricCard('Connected', connectedUnits,
                      const Color(0xFF8B5CF6), Icons.wifi_rounded, cardColor)),
              const SizedBox(width: 10),
              Expanded(
                  child: _smallMetricCard(
                      'Disconnected',
                      notConnUnits,
                      const Color(0xFF94A3B8),
                      Icons.wifi_off_rounded,
                      cardColor)),
            ],
          ),
          const SizedBox(height: 28),
          _header('AC Status Distribution'),
          const SizedBox(height: 12),
          // Doughnut Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: _cardDeco(isDark, cardColor),
            child: Row(
              children: [
                SizedBox(
                  width: 160,
                  height: 160,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      RepaintBoundary(
                        child: CustomPaint(
                          size: const Size(160, 160),
                          painter: DoughnutPainter(
                            segments: segments,
                            bgColor: isDark
                                ? textColor.withValues(alpha: 0.05)
                                : const Color(0xFFF3F4F6),
                            strokeWidth: 32,
                          ),
                        ),
                      ),
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(runningPercentage,
                            style: GoogleFonts.poppins(
                                color: textColor,
                                fontSize: 32,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(width: 28),
                Expanded(
                  child: Column(
                    children: segments
                        .map((seg) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Row(children: [
                                Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                        color: seg.color,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                              color: seg.color
                                                  .withValues(alpha: 0.3),
                                              blurRadius: 6)
                                        ])),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Text(seg.label,
                                        style: GoogleFonts.poppins(
                                            color: textColor.withValues(
                                                alpha: 0.7),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500))),
                                Text('${seg.value.toInt()}',
                                    style: GoogleFonts.poppins(
                                        color: textColor,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700)),
                              ]),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _header('AC Status by System'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: _cardDeco(isDark, cardColor),
            child: Column(
              children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Status by System',
                          style: GoogleFonts.poppins(
                              color: textColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      GestureDetector(
                        onTap: () => _showEquipmentPopup(
                            context, allEquipment, isDark, systemsMap),
                        child: Text('View All',
                            style: GoogleFonts.poppins(
                                color: const Color(0xFF0EA5E9),
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ),
                    ]),
                const SizedBox(height: 20),
                ...floors.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: _floorRow(f, textColor),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _floorRow(_FloorData f, Color textColor) {
    final total = f.running + f.alert + f.offline;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(f.name,
              style: GoogleFonts.poppins(
                  color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
          Text('${f.total} Units',
              style: GoogleFonts.poppins(
                  color: textColor.withValues(alpha: 0.4),
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 8,
          child: Row(children: [
            Flexible(
                flex: (f.running * 100 / total).round(),
                child: Container(color: const Color(0xFF6CC042))),
            if (f.alert > 0)
              Flexible(
                  flex: (f.alert * 100 / total).round(),
                  child: Container(color: const Color(0xFFF43F5E))),
            if (f.offline > 0)
              Flexible(
                  flex: (f.offline * 100 / total).round(),
                  child: Container(color: const Color(0xFF94A3B8))),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        _statusIndicator('${f.running} Running', const Color(0xFF6CC042)),
        if (f.alert > 0) ...[
          const SizedBox(width: 16),
          _statusIndicator('${f.alert} Alert', const Color(0xFFF43F5E))
        ],
        if (f.offline > 0) ...[
          const SizedBox(width: 16),
          _statusIndicator('${f.offline} Offline', const Color(0xFF94A3B8))
        ],
      ]),
    ]);
  }

  Widget _statusIndicator(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.poppins(
                color: color, fontSize: 10, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _header(String title) => Text(title.toUpperCase(),
      style: GoogleFonts.poppins(
          color: textColor.withValues(alpha: 0.4),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2));

  BoxDecoration _cardDeco(bool isDark, Color cardColor) => BoxDecoration(
      color: cardColor,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05)));
}

// ──────────────────────────────────────────────────────────────
// TRENDS VIEW
// ──────────────────────────────────────────────────────────────
class _TrendsView extends StatefulWidget {
  final bool isDark;
  final Color textColor;
  const _TrendsView({required this.isDark, required this.textColor});

  @override
  State<_TrendsView> createState() => _TrendsViewState();
}

class _TrendsViewState extends State<_TrendsView> {
  bool _isLoading = true;
  List<double> _tempData = [];
  List<String> _tempLabels = [];
  String _currentTemp = '--°C';

  List<double> _humData = [];
  List<String> _humLabels = [];
  String _currentHum = '--%';

  DateTimeRange _selectedRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 0)),
    end: DateTime.now(),
  );

  @override
  void initState() {
    super.initState();
    _fetchTrendsData();
  }

  Future<void> _fetchTrendsData() async {
    try {
      final token = await AuthService.getCookieHeader() ?? '';
      final companyId = await AuthService.getCompanyId() ?? '';
      final siteId = await AuthService.getSiteId() ?? '';

      // Fetch Live Equipment Data
      final url =
          '${AppConfig.provisionBaseUrl}/equipments/ac/by-company?companyId=$companyId&siteId=$siteId';
      debugPrint('🌐 [TrendsView] Fetching Live Data: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json'
        },
      );

      if (mounted) {
        setState(() {
          if (response.statusCode == 200) {
            final body = jsonDecode(response.body);
            if (body['status'] == 1 && body['data'] != null) {
              final equipments = body['data'] as List<dynamic>;

              List<double> tempValues = [];
              List<double> humValues = [];
              List<String> labels = [];

              for (var e in equipments) {
                final status = e['onOffStatus'];
                if (status != null &&
                    status['temperature'] != null &&
                    status['humidity'] != null) {
                  tempValues.add((status['temperature'] as num).toDouble());
                  humValues.add((status['humidity'] as num).toDouble());

                  String name = e['name'] ?? 'Unknown';
                  labels.add(
                      name.length > 8 ? '${name.substring(0, 8)}...' : name);
                }
              }

              if (tempValues.length > 1) {
                _tempData = tempValues;
                _humData = humValues;
                _tempLabels = labels;
                _humLabels = labels;

                double avgTemp =
                    tempValues.reduce((a, b) => a + b) / tempValues.length;
                double avgHum =
                    humValues.reduce((a, b) => a + b) / humValues.length;

                _currentTemp = '${avgTemp.toStringAsFixed(1)}°C';
                _currentHum = '${avgHum.toStringAsFixed(1)}%';
              } else {
                _tempData = [0, 0];
                _humData = [0, 0];
                _tempLabels = ['No Data', 'No Data'];
                _humLabels = ['No Data', 'No Data'];
              }
            }
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [TrendsView] Error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      initialDateRange: _selectedRange,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: widget.isDark
              ? const ColorScheme.dark(
                  primary: Colors.blueAccent,
                  onPrimary: Colors.white,
                  surface: Color(0xFF1E1E1E))
              : const ColorScheme.light(
                  primary: Colors.blue, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );

    if (range != null) {
      setState(() {
        _selectedRange = range;
        _isLoading = true;
      });
      _fetchTrendsData();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 100),
        child:
            Center(child: CircularProgressIndicator(color: Color(0xFF6CC042))),
      );
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ENVIRONMENTAL TRENDS',
                  style: GoogleFonts.poppins(
                      color: widget.textColor.withValues(alpha: 0.4),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2)),
              InkWell(
                onTap: _pickDateRange,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: widget.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: widget.isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.black.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month,
                          size: 16, color: widget.textColor),
                      const SizedBox(width: 8),
                      Text(
                        '${_selectedRange.start.day}/${_selectedRange.start.month} - ${_selectedRange.end.day}/${_selectedRange.end.month}',
                        style: GoogleFonts.poppins(
                            color: widget.textColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LineChartCard(
            title: 'Average Temperature Trend (°C)',
            color: const Color(0xFF0EA5E9),
            data: _tempData.length > 1
                ? _tempData
                : [0, 0], // Needs at least 2 points to draw line
            labels: _tempLabels.length > 1
                ? [_tempLabels.first, _tempLabels.last]
                : ['00:00', '23:59'],
            currentValue: _currentTemp,
          ),
          const SizedBox(height: 20),
          LineChartCard(
            title: 'Average Humidity Trend (%)',
            color: const Color(0xFF6CC042),
            data: _humData.length > 1 ? _humData : [0, 0],
            labels: _humLabels.length > 1
                ? [_humLabels.first, _humLabels.last]
                : ['00:00', '23:59'],
            currentValue: _currentHum,
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// LINE CHART CARD (self-contained hover state)
// ──────────────────────────────────────────────────────────────
class LineChartCard extends StatefulWidget {
  final String title;
  final Color color;
  final List<double> data;
  final List<String> labels;
  final String currentValue;

  const LineChartCard({
    super.key,
    required this.title,
    required this.color,
    required this.data,
    required this.labels,
    required this.currentValue,
  });

  @override
  State<LineChartCard> createState() => _LineChartCardState();
}

class _LineChartCardState extends State<LineChartCard> {
  final ValueNotifier<int?> _hoverIndexNotifier = ValueNotifier<int?>(null);

  @override
  void dispose() {
    _hoverIndexNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF2A244D) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);

    return Container(
      height: 260,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(widget.title,
                      style: GoogleFonts.poppins(
                          color: textColor.withValues(alpha: 0.5),
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(widget.currentValue,
                      style: GoogleFonts.poppins(
                          color: textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                ])),
            const SizedBox.shrink(),
          ]),
          const SizedBox(height: 20),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) {
                  final idx = (d.localPosition.dx /
                          constraints.maxWidth *
                          (widget.data.length - 1))
                      .round()
                      .clamp(0, widget.data.length - 1);
                  if (_hoverIndexNotifier.value != idx)
                    _hoverIndexNotifier.value = idx;
                },
                onPanEnd: (_) => _hoverIndexNotifier.value = null,
                onTapDown: (d) {
                  final idx = (d.localPosition.dx /
                          constraints.maxWidth *
                          (widget.data.length - 1))
                      .round()
                      .clamp(0, widget.data.length - 1);
                  _hoverIndexNotifier.value = idx;
                },
                onTapUp: (_) => _hoverIndexNotifier.value = null,
                child: Stack(clipBehavior: Clip.none, children: [
                  ValueListenableBuilder<int?>(
                    valueListenable: _hoverIndexNotifier,
                    builder: (context, hoverIndex, _) {
                      return RepaintBoundary(
                        child: CustomPaint(
                          size:
                              Size(constraints.maxWidth, constraints.maxHeight),
                          painter: LineChartPainter(
                            data: widget.data,
                            color: widget.color,
                            isDark: isDark,
                            hoverIndex: hoverIndex,
                          ),
                        ),
                      );
                    },
                  ),
                  ValueListenableBuilder<int?>(
                    valueListenable: _hoverIndexNotifier,
                    builder: (context, hoverIndex, _) {
                      if (hoverIndex == null) return const SizedBox.shrink();
                      return _tooltip(
                          constraints,
                          hoverIndex,
                          widget.data[hoverIndex],
                          widget.color,
                          textColor,
                          isDark);
                    },
                  ),
                ]),
              );
            }),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: widget.labels
                .map((l) => Text(l,
                    style: GoogleFonts.poppins(
                        color: textColor.withValues(alpha: 0.3),
                        fontSize: 10,
                        fontWeight: FontWeight.w600)))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _tooltip(BoxConstraints c, int idx, double val, Color color,
      Color textColor, bool isDark) {
    double x = (idx / (widget.data.length - 1)) * c.maxWidth;
    x = x.clamp(45.0, c.maxWidth - 45.0);
    return Positioned(
      left: x - 45,
      top: -12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1B172E) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${idx.toString().padLeft(2, '0')}:00',
                  style: GoogleFonts.poppins(
                      color: textColor.withValues(alpha: 0.4),
                      fontSize: 9,
                      fontWeight: FontWeight.w600)),
              Text(val.toStringAsFixed(2),
                  style: GoogleFonts.poppins(
                      color: textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
            ]),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// MODELS & PAINTERS
// ──────────────────────────────────────────────────────────────
class ChartSegment {
  final String label;
  final double value;
  final Color color;
  const ChartSegment(this.label, this.value, this.color);
}

class _FloorData {
  final String name;
  final int total, running, alert, offline;
  const _FloorData(
      this.name, this.total, this.running, this.alert, this.offline);
}

enum _PopupViewType { list, chart }

class _EquipData {
  final String id;
  final String systemId;
  final String status;
  final String acType;
  const _EquipData(this.id, this.systemId, this.status, this.acType);
}

void _showEquipmentPopup(BuildContext context, List<_EquipData> equipment,
    bool isDark, Map<String, String> systemsMap) {
  final bgColor = isDark ? const Color(0xFF1B172E) : const Color(0xFFF8FAFC);
  final textColor = isDark ? Colors.white : const Color(0xFF1B172E);

  // Group by systemName
  final Map<String, List<_EquipData>> grouped = {};
  for (var e in equipment) {
    final name =
        systemsMap.containsKey(e.systemId) ? systemsMap[e.systemId]! : e.acType;
    grouped.putIfAbsent(name, () => []).add(e);
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 30,
                offset: const Offset(0, -10))
          ],
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SYSTEM STATUS MAP',
                          style: GoogleFonts.poppins(
                              color: textColor,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _statusLegend(
                              'AC ON', const Color(0xFF6CC042), isDark),
                          const SizedBox(width: 16),
                          _statusLegend(
                              'AC OFF', const Color(0xFFF59E0B), isDark),
                          const SizedBox(width: 16),
                          _statusLegend(
                              'OFFLINE', const Color(0xFF94A3B8), isDark),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6CC042).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.hub_outlined,
                        color: const Color(0xFF6CC042), size: 24),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, indent: 32, endIndent: 32),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 80),
                child: Column(
                  children: grouped.entries.map((entry) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 48),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.03)
                                  : Colors.black.withValues(alpha: 0.02),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(entry.key.toUpperCase(),
                                style: GoogleFonts.poppins(
                                    color: textColor.withValues(alpha: 0.6),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5)),
                          ),
                          const SizedBox(height: 32),
                          _StatusCircuitHub(
                            units: entry.value,
                            isDark: isDark,
                            textColor: textColor,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _statusLegend(String label, Color color, bool isDark) {
  return Row(
    children: [
      Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label,
          style: GoogleFonts.poppins(
              color: color.withValues(alpha: 0.8),
              fontSize: 9,
              fontWeight: FontWeight.w700)),
    ],
  );
}

class _StatusCircuitHub extends StatefulWidget {
  final List<_EquipData> units;
  final bool isDark;
  final Color textColor;

  const _StatusCircuitHub(
      {required this.units, required this.isDark, required this.textColor});

  @override
  State<_StatusCircuitHub> createState() => _StatusCircuitHubState();
}

class _StatusCircuitHubState extends State<_StatusCircuitHub>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return CustomPaint(
            size: const Size(double.infinity, 260),
            painter: _StatusCircuitPainter(
              units: widget.units,
              isDark: widget.isDark,
              textColor: widget.textColor,
              pulse: _pulseController.value,
            ),
          );
        },
      ),
    );
  }
}

class _StatusCircuitPainter extends CustomPainter {
  final List<_EquipData> units;
  final bool isDark;
  final Color textColor;
  final double pulse;

  _StatusCircuitPainter(
      {required this.units,
      required this.isDark,
      required this.textColor,
      required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final hubRadius = 45.0;
    final orbitRadius = 90.0;

    final onColor = const Color(0xFF6CC042);
    final offColor = const Color(0xFFF59E0B);
    final offlineColor = const Color(0xFF94A3B8);

    // 1. Draw Background Grid/Pattern
    final gridPaint = Paint()
      ..color = textColor.withValues(alpha: 0.03)
      ..strokeWidth = 1;
    for (double i = 0; i < size.width; i += 30)
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    for (double i = 0; i < size.height; i += 30)
      canvas.drawLine(Offset(0, i), Offset(size.width, i), gridPaint);

    // 2. Draw Orbit Track
    canvas.drawCircle(
        center,
        orbitRadius,
        Paint()
          ..color = textColor.withValues(alpha: 0.05)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);

    // 3. Draw Nodes and Connections
    for (int i = 0; i < units.length; i++) {
      final angle = (i / units.length) * 2 * math.pi - math.pi / 2;
      final nodePos = Offset(center.dx + orbitRadius * math.cos(angle),
          center.dy + orbitRadius * math.sin(angle));

      // Determine Status Color
      Color color = offlineColor;
      bool isPulse = false;
      if (units[i].status == 'Running') {
        color = onColor;
        isPulse = true;
      } else if (units[i].status == 'Offline') {
        color = offColor; // AC is OFF but connected
      } else {
        color = offlineColor; // Disconnected
      }

      // Connection Line (High-Tech Style)
      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.1)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
          Offset(center.dx + hubRadius * math.cos(angle),
              center.dy + hubRadius * math.sin(angle)),
          nodePos,
          linePaint);

      // Node Glow
      if (isPulse) {
        final glowSize = 12 + (pulse * 8);
        canvas.drawCircle(
            nodePos,
            glowSize,
            Paint()
              ..color = color.withValues(alpha: 0.2 * (1 - pulse))
              ..style = PaintingStyle.fill);
      }

      // Node Circle
      canvas.drawCircle(
          nodePos,
          8,
          Paint()
            ..color = color
            ..style = PaintingStyle.fill);
      canvas.drawCircle(
          nodePos,
          8,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);

      // Label
      final labelPainter = TextPainter(
        text: TextSpan(
          text: units[i].id,
          style: GoogleFonts.poppins(
              color: textColor.withValues(alpha: 0.8),
              fontSize: 9,
              fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Label Positioning
      double lx = nodePos.dx + (18 * math.cos(angle));
      double ly = nodePos.dy + (18 * math.sin(angle));
      if (math.cos(angle).abs() < 0.1)
        lx -= labelPainter.width / 2;
      else if (math.cos(angle) < 0) lx -= labelPainter.width;
      labelPainter.paint(canvas, Offset(lx, ly));
    }

    // 4. Hub Node (Central Core)
    final hubPaint = Paint()
      ..color = isDark ? const Color(0xFF2A244D) : Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, hubRadius, hubPaint);
    canvas.drawCircle(
        center,
        hubRadius,
        Paint()
          ..color = onColor.withValues(alpha: 0.2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4);

    // Hub Stats
    final onCount = units.where((u) => u.status == 'Running').length;
    final totalCount = units.length;
    final hubTextPainter = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
              text: '$onCount',
              style: GoogleFonts.poppins(
                  color: onColor, fontSize: 20, fontWeight: FontWeight.w900)),
          TextSpan(
              text: '/$totalCount\n',
              style: GoogleFonts.poppins(
                  color: textColor.withValues(alpha: 0.4),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          TextSpan(
              text: 'AC ACTIVE',
              style: GoogleFonts.poppins(
                  color: textColor.withValues(alpha: 0.3),
                  fontSize: 7,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1)),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    hubTextPainter.paint(canvas,
        center - Offset(hubTextPainter.width / 2, hubTextPainter.height / 2));
  }

  @override
  bool shouldRepaint(_StatusCircuitPainter old) =>
      old.pulse != pulse || old.units.length != units.length;
}

class DoughnutPainter extends CustomPainter {
  final List<ChartSegment> segments;
  final Color bgColor;
  final double strokeWidth;
  const DoughnutPainter(
      {required this.segments, required this.bgColor, this.strokeWidth = 24});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = bgColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt);
    double total = segments.fold(0, (s, e) => s + e.value);
    if (total == 0) return;
    double angle = -math.pi / 2;
    for (final seg in segments) {
      final sweep = (seg.value / total) * 2 * math.pi;
      if (sweep > 0)
        canvas.drawArc(
            rect,
            angle,
            sweep,
            false,
            Paint()
              ..color = seg.color
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeWidth
              ..strokeCap = StrokeCap.butt);
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(DoughnutPainter old) =>
      old.bgColor != bgColor || old.segments.length != segments.length;
}

class LineChartPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final bool isDark;
  final int? hoverIndex;
  const LineChartPainter(
      {required this.data,
      required this.color,
      required this.isDark,
      this.hoverIndex});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final maxV = data.reduce(math.max) * 1.1;
    final minV = data.reduce(math.min) * 0.9;
    final range = (maxV - minV) == 0 ? 1.0 : maxV - minV;
    double xOf(int i) => (i / (data.length - 1)) * size.width;
    double yOf(double v) => size.height - ((v - minV) / range * size.height);

    final fill = Path()
      ..moveTo(xOf(0), size.height)
      ..lineTo(xOf(0), yOf(data[0]));
    final line = Path()..moveTo(xOf(0), yOf(data[0]));
    for (int i = 1; i < data.length; i++) {
      final cp = xOf(i - 1) + (xOf(i) - xOf(i - 1)) / 2;
      fill.cubicTo(
          cp, yOf(data[i - 1]), cp, yOf(data[i]), xOf(i), yOf(data[i]));
      line.cubicTo(
          cp, yOf(data[i - 1]), cp, yOf(data[i]), xOf(i), yOf(data[i]));
    }
    fill
      ..lineTo(xOf(data.length - 1), size.height)
      ..close();

    canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: isDark ? 0.3 : 0.15),
              color.withValues(alpha: 0)
            ],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
    canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..strokeWidth = 3.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round);

    if (hoverIndex != null && hoverIndex! < data.length) {
      final hx = xOf(hoverIndex!);
      final hy = yOf(data[hoverIndex!]);
      canvas.drawLine(
          Offset(hx, 0),
          Offset(hx, size.height),
          Paint()
            ..color = color.withValues(alpha: 0.15)
            ..strokeWidth = 1.5);
      canvas.drawCircle(
          Offset(hx, hy), 10, Paint()..color = color.withValues(alpha: 0.2));
      canvas.drawCircle(Offset(hx, hy), 6, Paint()..color = color);
      canvas.drawCircle(Offset(hx, hy), 3, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(LineChartPainter old) =>
      old.hoverIndex != hoverIndex ||
      old.isDark != isDark ||
      old.data.length != data.length;
}
