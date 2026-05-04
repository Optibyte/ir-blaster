import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ir_blaster_ac/core/services/api_service.dart';
import 'package:ir_blaster_ac/widgets/skeleton.dart';

import 'dart:math' as math;

/// Widget showing energy consumption chart for Main EB Panel
class EnergyChartWidget extends StatefulWidget {
  final String panelName;
  final double energy;
  final bool isLineChart;
  final Color? chartColor;

  const EnergyChartWidget({
    super.key,
    this.panelName = 'Main EB Panel',
    this.energy = 259.81,
    this.isLineChart = false,
    this.chartColor,
  });

  @override
  State<EnergyChartWidget> createState() => _EnergyChartWidgetState();
}

class _EnergyChartWidgetState extends State<EnergyChartWidget> {
  final ApiService _apiService = ApiService();
  List<double> _chartData = [];
  List<String> _chartLabels = [];
  double _totalEnergyValue = 0;
  bool _isLoading = true;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  List _groups = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final start = DateTime(_startDate.year, _startDate.month, _startDate.day, 0, 0, 0);
      final stop = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 55, 0);

      if (widget.isLineChart) {
        // Fetch grouped data for Main EB Panel
        final data = await _apiService.fetchGroupedEnergySummary(start: start, stop: stop);
        setState(() {
          if (data['success'] == true) {
            final List groups = data['groups'] ?? [];
            
            // Combine all group trends into a single trend for the "Main EB Panel"
            Map<String, double> combinedTrend = {};
            for (var group in groups) {
              final List trendList = group['trend'] ?? [];
              for (var point in trendList) {
                final String ts = point['timestamp'];
                final double val = (point['value'] as num).toDouble();
                combinedTrend[ts] = (combinedTrend[ts] ?? 0) + val;
              }
            }

            final sortedKeys = combinedTrend.keys.toList()..sort();
            _chartData = sortedKeys.map((k) => combinedTrend[k]!).toList();
            _chartLabels = sortedKeys.map((k) {
              final ts = DateTime.parse(k).toLocal();
              return '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
            }).toList();
            _totalEnergyValue = (data['totalEnergy'] as num).toDouble();
          }
          _isLoading = false;
        });
      } else {
        // Fetch grouped data for consumption
        final data = await _apiService.fetchGroupedEnergySummary(start: start, stop: stop);
        setState(() {
          if (data['success'] == true) {
            final List groups = data['groups'] ?? [];
            _totalEnergyValue = (data['totalEnergy'] as num).toDouble();
            _groups = groups;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching energy chart: $e');
      setState(() => _isLoading = false);
    }
  }

  String _formatDateTimeRange() {
    return '${_startDate.day}/${_startDate.month} - ${_endDate.day}/${_endDate.month}';
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: Theme.of(context).colorScheme.primary,
              onPrimary: Colors.white,
              surface: const Color(0xFF1B172E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _fetchData();
    }
  }

  final ValueNotifier<int?> _hoverIndex = ValueNotifier<int?>(null);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final primaryColor = widget.chartColor ?? (isDark ? const Color(0xFF6CC042) : const Color(0xFF1B172E));

    return GestureDetector(
      onTap: () => _hoverIndex.value = null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A244D) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFF1B172E).withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      children: [
                        Icon(
                          widget.isLineChart ? Icons.home_outlined : Icons.analytics_outlined, 
                          color: primaryColor, 
                          size: 14
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.panelName,
                            style: GoogleFonts.poppins(
                              color: isDark ? Colors.white : colorScheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _selectDateRange(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.05) : colorScheme.primary.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark ? Colors.white.withOpacity(0.1) : colorScheme.primary.withOpacity(0.1),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.calendar_today_outlined, color: primaryColor, size: 8),
                          const SizedBox(width: 4),
                          Text(
                            _formatDateTimeRange(),
                            style: GoogleFonts.poppins(
                              color: isDark ? Colors.white70 : colorScheme.primary.withOpacity(0.7),
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Chart
              _isLoading 
                ? const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Skeleton(height: 180, borderRadius: 16),
                  )
                : (widget.isLineChart
                  ? SizedBox(
                      height: 180,
                      child: _LineChart(
                        panelName: widget.panelName, 
                        data: _chartData, 
                        labels: _chartLabels, 
                        primaryColor: primaryColor,
                        hoverIndex: _hoverIndex,
                      ),
                    )
                  : _CircularEnergyChart(
                      energy: _totalEnergyValue, 
                      primaryColor: primaryColor,
                      groups: _groups,
                    )),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  final String panelName;
  final List<double> data;
  final List<String> labels;
  final Color primaryColor;
  final ValueNotifier<int?> hoverIndex;

  const _LineChart({
    required this.panelName, 
    required this.data, 
    required this.labels, 
    required this.primaryColor,
    required this.hoverIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    if (data.isEmpty) {
      return Center(child: Text('No data available', style: GoogleFonts.poppins(color: Colors.grey, fontSize: 10)));
    }

    return GestureDetector(
      onPanUpdate: (details) => _handleTouch(details.localPosition, context),
      onPanEnd: (_) => hoverIndex.value = null,
      onTapDown: (details) => _handleTouch(details.localPosition, context),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark ? Colors.black.withOpacity(0.1) : Colors.white.withOpacity(0.5),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.05) : colorScheme.primary.withOpacity(0.05), 
            width: 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ValueListenableBuilder<int?>(
          valueListenable: hoverIndex,
          builder: (context, currentHover, _) {
            return CustomPaint(
              painter: _LineChartPainter(
                data: data,
                labels: labels,
                isDark: isDark,
                primaryColor: primaryColor,
                hoverIndex: currentHover,
              ),
              size: const Size(double.infinity, 180),
            );
          },
        ),
      ),
    );
  }

  void _handleTouch(Offset localPosition, BuildContext context) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final double width = box.size.width - 16;
    if (width <= 0) return;
    
    final int index = ((localPosition.dx - 8) / width * (data.length - 1)).round().clamp(0, data.length - 1);
    hoverIndex.value = index;
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> data;
  final List<String> labels;
  final bool isDark;
  final Color primaryColor;
  final int? hoverIndex;

  _LineChartPainter({
    required this.data,
    required this.labels,
    required this.isDark,
    required this.primaryColor,
    this.hoverIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = primaryColor.withOpacity(0.2)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint();
    if (isDark) {
      fillPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          primaryColor.withOpacity(0.2),
          primaryColor.withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    } else {
      fillPaint.color = primaryColor.withOpacity(0.2);
    }

    final gridPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withOpacity(0.03)
      ..strokeWidth = 0.5;

    // Draw horizontal grid
    for (int i = 0; i <= 3; i++) {
      final y = (size.height / 3) * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (data.isEmpty) return;

    final maxValue = data.reduce((a, b) => math.max(a, b)) * 1.2;
    final range = maxValue == 0 ? 1 : maxValue;

    Path path = Path();
    Path fillPath = Path();

    double? hoverX, hoverY;

    for (int i = 0; i < data.length; i++) {
      final x = data.length > 1 ? (i / (data.length - 1)) * size.width : size.width / 2;
      final y = size.height - (data[i] / range * size.height);

      if (i == hoverIndex) {
        hoverX = x;
        hoverY = y;
      }

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        final prevX = data.length > 1 ? ((i - 1) / (data.length - 1)) * size.width : 0.0;
        final prevY = size.height - (data[i - 1] / range * size.height);
        final cp1x = prevX + (x - prevX) / 2;
        path.cubicTo(cp1x, prevY, cp1x, y, x, y);
        fillPath.cubicTo(cp1x, prevY, cp1x, y, x, y);
      }
    }
    
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, linePaint);

    // Draw Hover Effects
    if (hoverIndex != null && hoverX != null && hoverY != null) {
      final indicatorPaint = Paint()
        ..color = primaryColor.withOpacity(0.3)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(hoverX, 0), Offset(hoverX, size.height), indicatorPaint);

      final String tooltipText = '${data[hoverIndex!].toStringAsFixed(1)} kWh';
      final String timeText = labels[hoverIndex!];
      
      final textPainter = TextPainter(textDirection: TextDirection.ltr);
      textPainter.text = TextSpan(
        children: [
          TextSpan(text: '$timeText\n', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 7, fontWeight: FontWeight.w500)),
          TextSpan(text: tooltipText, style: GoogleFonts.poppins(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
        ],
      );
      textPainter.layout();

      final double tooltipWidth = textPainter.width + 12;
      final double tooltipHeight = textPainter.height + 8;
      double tooltipX = hoverX - (tooltipWidth / 2);
      double tooltipY = hoverY - tooltipHeight - 10;

      if (tooltipX < 0) tooltipX = 4;
      if (tooltipX + tooltipWidth > size.width) tooltipX = size.width - tooltipWidth - 4;
      if (tooltipY < 0) tooltipY = hoverY + 10;

      final RRect tooltipRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(tooltipX, tooltipY, tooltipWidth, tooltipHeight),
        const Radius.circular(6),
      );

      canvas.drawRRect(tooltipRect, Paint()..color = const Color(0xFF1B172E).withOpacity(0.9));
      canvas.drawRRect(tooltipRect, Paint()..color = primaryColor.withOpacity(0.5)..style = PaintingStyle.stroke);
      
      textPainter.paint(canvas, Offset(tooltipX + 6, tooltipY + 4));

      canvas.drawCircle(Offset(hoverX, hoverY), 5, Paint()..color = primaryColor.withOpacity(0.2));
      canvas.drawCircle(Offset(hoverX, hoverY), 2.5, Paint()..color = Colors.white);
    }

    final int labelCount = math.min(4, labels.length);
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < labelCount; i++) {
      final index = labelCount > 1 ? (i * (labels.length - 1) ~/ (labelCount - 1)) : 0;
      final x = labels.length > 1 ? (index / (labels.length - 1)) * size.width : size.width / 2;
      textPainter.text = TextSpan(
        text: labels[index],
        style: GoogleFonts.poppins(
          color: (isDark ? Colors.white : Colors.black).withOpacity(0.4), 
          fontSize: 7, 
          fontWeight: FontWeight.w600,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - (textPainter.width / 2), size.height + 10));
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter oldDelegate) => oldDelegate.hoverIndex != hoverIndex || oldDelegate.data != data;
}

class _CircularEnergyChart extends StatelessWidget {
  final double energy;
  final Color primaryColor;
  final List groups;
  const _CircularEnergyChart({required this.energy, required this.primaryColor, required this.groups});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 240,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withOpacity(0.2) : colorScheme.primary.withOpacity(0.02),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : colorScheme.primary.withOpacity(0.05), 
          width: 1,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 130,
                  height: 130,
                  child: CircularProgressIndicator(
                    value: 0.7, // Simplified for UI
                    strokeWidth: 14,
                    backgroundColor: isDark 
                        ? const Color(0xFF4A3B7D).withOpacity(0.3)
                        : colorScheme.primary.withOpacity(0.1),
                    color: primaryColor,
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      energy.toStringAsFixed(2),
                      style: GoogleFonts.poppins(
                        color: isDark ? Colors.white : colorScheme.primary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'kWh',
                      style: GoogleFonts.poppins(
                        color: (isDark ? Colors.white : colorScheme.primary).withOpacity(0.4),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Group Breakdown Legend
          if (groups.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: groups.map((g) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${g['groupName']}: ${(g['statistics']['total'] as num).toStringAsFixed(0)}',
                        style: GoogleFonts.poppins(
                          color: (isDark ? Colors.white : colorScheme.primary).withOpacity(0.6),
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
