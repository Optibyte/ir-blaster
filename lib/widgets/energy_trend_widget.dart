import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:esp/core/services/api_service.dart';
import 'package:esp/widgets/skeleton.dart';

import 'dart:math' as math;

/// Widget showing energy consumption trend with line chart
class EnergyTrendWidget extends StatefulWidget {
  const EnergyTrendWidget({super.key});

  @override
  State<EnergyTrendWidget> createState() => _EnergyTrendWidgetState();
}

class _EnergyTrendWidgetState extends State<EnergyTrendWidget> {
  final ApiService _apiService = ApiService();
  List<double> _trendData = [];
  List<String> _trendLabels = [];
  bool _isLoading = true;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  final ValueNotifier<int?> _hoverIndex = ValueNotifier<int?>(null);

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _hoverIndex.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final start = DateTime(_startDate.year, _startDate.month, _startDate.day, 0, 0, 0);
      final stop = DateTime(_endDate.year, _endDate.month, _endDate.day, 23, 55, 0);
      
      final data = await _apiService.fetchEnergySummary(start: start, stop: stop);
      if (!mounted) return;
      
      setState(() {
        if (data['success'] == true && data['trend'] != null) {
          final List trend = data['trend'];
          _trendData = trend.map((e) => (e['value'] as num).toDouble()).toList();
          _trendLabels = trend.map((e) {
            final ts = DateTime.parse(e['timestamp']).toLocal();
            return '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
          }).toList();
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching trend: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF6CC042),
              surface: Color(0xFF1A1625),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final primaryColor = isDark ? const Color(0xFF6CC042) : const Color(0xFF1B172E);

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
              Row(
                children: [
                  Icon(Icons.analytics_outlined, color: primaryColor, size: 14),
                  const SizedBox(width: 8),
                  Text(
                    'Trend',
                    style: GoogleFonts.poppins(
                      color: isDark ? Colors.white : colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
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
                            '${_startDate.day}/${_startDate.month} - ${_endDate.day}/${_endDate.month}',
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
              _isLoading 
                ? const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Skeleton(height: 180, borderRadius: 16),
                  )
                : _TrendChart(
                    data: _trendData, 
                    labels: _trendLabels, 
                    hoverIndex: _hoverIndex,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<double> data;
  final List<String> labels;
  final ValueNotifier<int?> hoverIndex;

  const _TrendChart({
    required this.data, 
    required this.labels, 
    required this.hoverIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final primaryColor = isDark ? const Color(0xFF6CC042) : const Color(0xFF0369A1);
    final accentColor = isDark ? const Color(0xFF86EFAC) : const Color(0xFF7DD3FC);

    if (data.isEmpty) {
      return Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: isDark ? Colors.white10 : Colors.black.withOpacity(0.1)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'No data available', 
            style: GoogleFonts.poppins(color: Colors.grey, fontSize: 12)
          )
        ),
      );
    }

    return GestureDetector(
      onPanUpdate: (details) => _handleTouch(details.localPosition, context),
      onPanEnd: (_) => hoverIndex.value = null,
      onPanCancel: () => hoverIndex.value = null,
      onTapDown: (details) => _handleTouch(details.localPosition, context),
      child: Container(
        height: 200,
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
        decoration: BoxDecoration(
          color: isDark ? Colors.black.withOpacity(0.2) : colorScheme.primary.withOpacity(0.02),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.05) : colorScheme.primary.withOpacity(0.05),
            width: 1,
          ),
        ),
        child: ValueListenableBuilder<int?>(
          valueListenable: hoverIndex,
          builder: (context, currentHover, _) {
            return CustomPaint(
              painter: _LineChartPainter(
                data: data, 
                timeLabels: labels,
                isDark: isDark,
                primaryColor: primaryColor,
                accentColor: accentColor,
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
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final double width = box.size.width - 16;
    if (width <= 0) return;
    
    final int index = ((localPosition.dx - 8) / width * (data.length - 1)).round().clamp(0, data.length - 1);
    hoverIndex.value = index;
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> data;
  final List<String> timeLabels;
  final bool isDark;
  final Color primaryColor;
  final Color accentColor;
  final int? hoverIndex;

  _LineChartPainter({
    required this.data,
    required this.timeLabels,
    required this.isDark,
    required this.primaryColor,
    required this.accentColor,
    this.hoverIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

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
    for (int i = 0; i <= 4; i++) {
      final y = (size.height / 4) * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final maxValue = data.reduce((a, b) => math.max(a, b)) * 1.2;
    final minValue = 0.0;
    final range = maxValue == 0 ? 1.0 : maxValue - minValue;

    Path path = Path();
    Path fillPath = Path();

    double? hoverX, hoverY;

    for (int i = 0; i < data.length; i++) {
      final x = data.length > 1 ? (i / (data.length - 1)) * size.width : size.width / 2;
      final y = size.height - ((data[i] - minValue) / range * size.height);

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
        final prevY = size.height - ((data[i - 1] - minValue) / range * size.height);
        final cp1x = prevX + (x - prevX) / 2;
        path.cubicTo(cp1x, prevY, cp1x, y, x, y);
        fillPath.cubicTo(cp1x, prevY, cp1x, y, x, y);
      }

      if (i == data.length - 1) {
        fillPath.lineTo(x, size.height);
        fillPath.close();
      }
    }

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, linePaint);

    if (hoverIndex != null && hoverX != null && hoverY != null) {
      final indicatorPaint = Paint()
        ..color = primaryColor.withOpacity(0.3)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(hoverX, 0), Offset(hoverX, size.height), indicatorPaint);

      final String tooltipText = '${data[hoverIndex!].toStringAsFixed(1)} kWh';
      final String timeText = timeLabels[hoverIndex!];
      
      final textPainter = TextPainter(textDirection: TextDirection.ltr);
      textPainter.text = TextSpan(
        children: [
          TextSpan(text: '$timeText\n', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.w500)),
          TextSpan(text: tooltipText, style: GoogleFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      );
      textPainter.layout();

      final double tooltipWidth = textPainter.width + 16;
      final double tooltipHeight = textPainter.height + 12;
      double tooltipX = hoverX - (tooltipWidth / 2);
      double tooltipY = hoverY - tooltipHeight - 15;

      if (tooltipX < 0) tooltipX = 4;
      if (tooltipX + tooltipWidth > size.width) tooltipX = size.width - tooltipWidth - 4;
      if (tooltipY < 0) tooltipY = hoverY + 15;

      final RRect tooltipRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(tooltipX, tooltipY, tooltipWidth, tooltipHeight),
        const Radius.circular(8),
      );

      canvas.drawRRect(tooltipRect, Paint()..color = const Color(0xFF1B172E).withOpacity(0.9));
      canvas.drawRRect(tooltipRect, Paint()..color = primaryColor.withOpacity(0.5)..style = PaintingStyle.stroke);
      
      textPainter.paint(canvas, Offset(tooltipX + 8, tooltipY + 6));

      canvas.drawCircle(Offset(hoverX, hoverY), 6, Paint()..color = primaryColor.withOpacity(0.2));
      canvas.drawCircle(Offset(hoverX, hoverY), 3, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(hoverX, hoverY), 2, Paint()..color = primaryColor);
    }

    final int labelCount = math.min(5, timeLabels.length);
    if (labelCount > 0) {
      final labelPainter = TextPainter(textDirection: TextDirection.ltr);
      for (int i = 0; i < labelCount; i++) {
        final index = labelCount > 1 ? (i * (timeLabels.length - 1) ~/ (labelCount - 1)) : 0;
        final x = timeLabels.length > 1 ? (index / (timeLabels.length - 1)) * size.width : size.width / 2;
        
        labelPainter.text = TextSpan(
          text: timeLabels[index],
          style: GoogleFonts.poppins(
            color: (isDark ? Colors.white : Colors.black).withOpacity(0.4),
            fontSize: 7,
            fontWeight: FontWeight.w600,
          ),
        );
        labelPainter.layout();
        labelPainter.paint(canvas, Offset(x - (labelPainter.width / 2), size.height + 10));
      }
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter oldDelegate) => 
      oldDelegate.hoverIndex != hoverIndex || 
      oldDelegate.data != data || 
      oldDelegate.isDark != isDark;
}
