import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // compute()
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:esp/core/services/auth_service.dart';

// ─── Isolate-safe data class (no Flutter objects) ────────────────────────────
class _PivotInput {
  final String rawJson;
  _PivotInput(this.rawJson);
}

class _PivotResult {
  final List<String> names;
  final List<String> sortedTimes;
  final Map<String, Map<String, String>> pivot;
  _PivotResult(this.names, this.sortedTimes, this.pivot);
}

// Runs synchronously - removed compute to prevent Isolate spawn freezing
_PivotResult _buildPivot(_PivotInput input) {
  final Map<String, Map<String, String>> pivot = {};
  final Map<String, DateTime> timeToLocal = {};
  final List<String> names = [];

  try {
    final decoded = jsonDecode(input.rawJson);
    if (decoded is Map) {
      // 1. Extract column names from topicsdata
      final topics = decoded['topicsdata'] as List<dynamic>? ?? [];
      for (final t in topics) {
        final colName = t.toString();
        if (colName != '_time' && colName != 'EquipmentId') {
          names.add(colName);
        }
      }

      // 2. Extract rows from data
      final dataArray = decoded['data'] as List<dynamic>? ?? [];
      for (final row in dataArray) {
        if (row is Map) {
          final timeStr = row['_time']?.toString() ?? '';
          if (timeStr.isEmpty) continue;

          final localTime = DateTime.parse(timeStr).toLocal();
          final timeKey = '${localTime.day.toString().padLeft(2, '0')}-'
              '${localTime.month.toString().padLeft(2, '0')} '
              '${localTime.hour.toString().padLeft(2, '0')}:'
              '${localTime.minute.toString().padLeft(2, '0')}';

          pivot[timeKey] = {};
          timeToLocal[timeKey] = localTime;

          for (final col in names) {
            final val = row[col];
            if (val != null) {
              if (val is double) {
                pivot[timeKey]![col] = val.toStringAsFixed(2);
              } else {
                pivot[timeKey]![col] = val.toString();
              }
            } else {
              pivot[timeKey]![col] = '--';
            }
          }
        }
      }
    }
  } catch (e) {
    // Return empty if parsing fails
    return _PivotResult([], [], {});
  }

  // Sort descending (newest first)
  final sortedTimes = pivot.keys.toList()
    ..sort((a, b) {
      final ta = timeToLocal[a];
      final tb = timeToLocal[b];
      if (ta == null || tb == null) return 0;
      return tb.compareTo(ta);
    });

  // Cap at 288 rows (one day of 5-min intervals)
  final capped =
      sortedTimes.length > 288 ? sortedTimes.sublist(0, 288) : sortedTimes;

  return _PivotResult(names, capped, pivot);
}

// ─── Widget ──────────────────────────────────────────────────────────────────
class TrendsTable extends StatefulWidget {
  final bool isDark;
  final String systemId;
  final String systemShortId;
  final String equipmentShortId;
  final String companyId;
  final String siteId;
  final String bucket;
  final DateTimeRange dateRange;
  final List<dynamic> parameters;

  const TrendsTable({
    super.key,
    required this.isDark,
    required this.systemId,
    required this.systemShortId,
    required this.equipmentShortId,
    required this.companyId,
    required this.siteId,
    required this.bucket,
    required this.dateRange,
    required this.parameters,
  });

  @override
  State<TrendsTable> createState() => _TrendsTableState();
}

class _TrendsTableState extends State<TrendsTable> {
  Map<String, Map<String, String>> _pivot = {};
  List<String> _sortedTimes = [];
  List<String> _paramNames = [];
  bool _isLoading = false;
  bool _hasLoaded = false;
  int _currentPage = 0;
  static const int _rowsPerPage = 10;

  @override
  void initState() {
    super.initState();
    _fetchAllParameters();
  }

  @override
  void didUpdateWidget(TrendsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hasLoaded &&
        (oldWidget.dateRange != widget.dateRange ||
            oldWidget.equipmentShortId != widget.equipmentShortId)) {
      _fetchAllParameters();
    }
  }

  Future<void> _fetchAllParameters() async {
    if (widget.parameters.isEmpty) {
      setState(() {
        _isLoading = false;
        _hasLoaded = true;
      });
      return;
    }

    setState(() => _isLoading = true);
    final token = await AuthService.getCookieHeader() ?? '';

    final allParamIds = widget.parameters
        .map((p) => p['shortId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .join(',');

    final startTime = DateTime(
      widget.dateRange.start.year,
      widget.dateRange.start.month,
      widget.dateRange.start.day,
      0,
      0,
      0,
    ).toUtc().toIso8601String();

    final endTime = DateTime(
      widget.dateRange.end.year,
      widget.dateRange.end.month,
      widget.dateRange.end.day,
      23,
      59,
      59,
    ).toUtc().toIso8601String();

    final url =
        'https://optibyte.sustainabyte.ai/provisionservice/v1/systems/query'
        '?page=1&pageSize=1000'
        '&companyId=${widget.companyId}'
        '&siteId=${widget.siteId}'
        '&bucket=${widget.bucket}';

    final body = {
      "systemId": widget.systemShortId,
      "equipmentIds": [widget.equipmentShortId],
      "bucket": widget.bucket,
      "start": startTime,
      "stop": endTime,
      "companyId": widget.companyId,
      "siteId": widget.siteId,
      "measurement": "FiveminAggregatedData"
    };

    debugPrint('📋 TABLE URL: $url');
    debugPrint('📋 TABLE BODY: ${jsonEncode(body)}');

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      debugPrint('📋 TABLE STATUS: ${response.statusCode}');
      // Log first 2000 chars so we can see the full structure
      final bodyPreview = response.body.length > 2000
          ? '${response.body.substring(0, 2000)}...[truncated]'
          : response.body;
      debugPrint('📋 TABLE FULL BODY: $bodyPreview');

      if (response.statusCode == 200) {
        // We execute this directly. compute() overhead + deep copying
        // across Isolate boundaries is causing ANRs on some devices
        final result = _buildPivot(_PivotInput(response.body));

        if (mounted) {
          setState(() {
            _paramNames = result.names;
            _sortedTimes = result.sortedTimes;
            _pivot = result.pivot;
            _isLoading = false;
            _hasLoaded = true;
            _currentPage = 0;
          });
        }
      } else {
        debugPrint('❌ TABLE FAILED: ${response.statusCode} ${response.body}');
        if (mounted)
          setState(() {
            _isLoading = false;
            _hasLoaded = true;
          });
      }
    } catch (e, stack) {
      debugPrint('❌ TABLE ERROR: $e\n$stack');
      if (mounted)
        setState(() {
          _isLoading = false;
          _hasLoaded = true;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final green = const Color(0xFF6CC042);
    final textColor = isDark ? Colors.white : Colors.black;
    final subColor = isDark ? Colors.white24 : Colors.black26;

    // Cache text styles — DO NOT create inside itemBuilder
    final timeStyle = GoogleFonts.poppins(
      color: isDark ? Colors.white70 : Colors.black54,
      fontSize: 9,
      fontWeight: FontWeight.w500,
    );
    final cellStyle = GoogleFonts.poppins(
      color: textColor,
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );
    final headerStyle = GoogleFonts.poppins(
      color: green,
      fontSize: 10,
      fontWeight: FontWeight.w700,
    );

    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.03)
              : Colors.black.withOpacity(0.03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: (isDark ? Colors.white : Colors.black).withOpacity(0.06),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Data Logs',
                  style: GoogleFonts.poppins(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF6CC042)),
                    ),
                  )
                else if (_hasLoaded)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_sortedTimes.length} rows',
                      style: GoogleFonts.poppins(
                        color: green,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Auto-loads on page open — show spinner while fetching ──
            if (_isLoading)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  children: [
                    // Header Skeleton
                    Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.05)
                            : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Row Skeletons
                    ...List.generate(
                      5,
                      (index) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        height: 36,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.02)
                              : Colors.black.withOpacity(0.02),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (_sortedTimes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.table_rows_outlined,
                          size: 36, color: subColor),
                      const SizedBox(height: 8),
                      Text(
                        'No data for this period',
                        style:
                            GoogleFonts.poppins(color: subColor, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else
              // Horizontally + vertically scrollable table
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  height: 400,
                  width: 110.0 + (_paramNames.length * 85.0) + 16.0,
                  child: Column(
                    children: [
                      // Column headers
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 10),
                        decoration: BoxDecoration(
                          color: green.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 110,
                              child: Text('Time', style: headerStyle),
                            ),
                            ..._paramNames.map(
                              (name) => SizedBox(
                                width: 85,
                                child: Text(
                                  name,
                                  style: headerStyle,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Data rows — virtualized with itemExtent
                      Expanded(
                        child: ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          itemCount: (_sortedTimes.length -
                                  _currentPage * _rowsPerPage)
                              .clamp(0, _rowsPerPage),
                          itemExtent: 36,
                          itemBuilder: (context, index) {
                            final actualIndex =
                                (_currentPage * _rowsPerPage) + index;
                            final timeKey = _sortedTimes[actualIndex];
                            final rowData = _pivot[timeKey] ?? {};
                            final isEven = index % 2 == 0;

                            return Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              color: isEven
                                  ? (isDark
                                      ? const Color(0x05FFFFFF)
                                      : const Color(0x05000000))
                                  : Colors.transparent,
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 110,
                                    child: Text(timeKey, style: timeStyle),
                                  ),
                                  ..._paramNames.map(
                                    (name) => SizedBox(
                                      width: 85,
                                      child: Text(
                                        rowData[name] ?? '--',
                                        style: cellStyle,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Pagination Controls
            if (!_isLoading && _sortedTimes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Showing ${(_currentPage * _rowsPerPage) + 1} - ${((_currentPage + 1) * _rowsPerPage).clamp(0, _sortedTimes.length)} of ${_sortedTimes.length}',
                      style: GoogleFonts.poppins(color: subColor, fontSize: 12),
                    ),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _currentPage > 0
                              ? () => setState(() => _currentPage--)
                              : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: _currentPage > 0
                                  ? green.withOpacity(0.15)
                                  : (isDark
                                      ? Colors.white.withOpacity(0.05)
                                      : Colors.black.withOpacity(0.05)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.chevron_left_rounded,
                                color: _currentPage > 0 ? green : subColor),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            '${_currentPage + 1} / ${(_sortedTimes.length / _rowsPerPage).ceil()}',
                            style: GoogleFonts.poppins(
                              color: textColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: (_currentPage + 1) * _rowsPerPage <
                                  _sortedTimes.length
                              ? () => setState(() => _currentPage++)
                              : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: (_currentPage + 1) * _rowsPerPage <
                                      _sortedTimes.length
                                  ? green.withOpacity(0.15)
                                  : (isDark
                                      ? Colors.white.withOpacity(0.05)
                                      : Colors.black.withOpacity(0.05)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.chevron_right_rounded,
                                color: (_currentPage + 1) * _rowsPerPage <
                                        _sortedTimes.length
                                    ? green
                                    : subColor),
                          ),
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
}
