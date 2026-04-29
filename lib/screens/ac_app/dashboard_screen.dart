import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;

import 'package:esp/core/constants/colors.dart';
import 'schedule_overview_page.dart';

// DashboardScreen manages its own tabs — no HomePage rebuild on tab switch
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _tabIndex = 0; // 0=Status, 1=Trends, 2=Schedule

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
              _chip('Status', 0, isDark),
              const SizedBox(width: 10),
              _chip('Trends', 1, isDark),
              const SizedBox(width: 10),
              _chip('Schedule', 2, isDark),
            ],
          ),
        ),

        // ── Metric Cards (Status tab only) ────────────────
        if (_tabIndex == 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                _metricCard('TOTAL AC', '45', const Color(0xFF0EA5E9), isDark),
                const SizedBox(width: 12),
                _metricCard('RUNNING', '38', const Color(0xFF6CC042), isDark),
                const SizedBox(width: 12),
                _metricCard('OFFLINE', '7', const Color(0xFFF59E0B), isDark),
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
      case 2:
        return const ScheduleOverviewContent();
      default:
        return _StatusView(isDark: isDark, textColor: textColor);
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
              ? primary.withOpacity(isDark ? 0.2 : 0.1) 
              : (isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? primary : (isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
            width: 1.5,
          ),
          boxShadow: [
            if (isActive)
              BoxShadow(
                color: primary.withOpacity(0.2),
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

  Widget _metricCard(String label, String value, Color color, bool isDark) {
    final bg = isDark ? const Color(0xFF2D2D44) : Colors.white;
    final tc = isDark ? Colors.white : const Color(0xFF1B172E);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: (isDark ? Colors.white : Colors.black).withOpacity(0.05),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                label.contains('TOTAL') ? Icons.grid_view_rounded : 
                label.contains('RUNNING') ? Icons.play_arrow_rounded : 
                Icons.pause_rounded,
                color: color,
                size: 14,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: tc.withOpacity(0.4),
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.poppins(
                color: tc,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
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
  const _StatusView({required this.isDark, required this.textColor});

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? const Color(0xFF2A244D) : Colors.white;

    const segments = [
      ChartSegment('Running', 38, Color(0xFF6CC042)),
      ChartSegment('Offline', 7, Color(0xFF94A3B8)),
      ChartSegment('Alert', 5, Color(0xFFF43F5E)),
    ];

    final floors = [
      _FloorData('Floor 1', 10, 8, 1, 1),
      _FloorData('Floor 2', 15, 12, 2, 1),
      _FloorData('Floor 3', 20, 18, 4, 2),
    ];

    // All individual equipment entries for the popup
    final allEquipment = [
      _EquipData('AC-101', 'Floor 1', 'Running'),
      _EquipData('AC-102', 'Floor 1', 'Running'),
      _EquipData('AC-103', 'Floor 1', 'Running'),
      _EquipData('AC-104', 'Floor 1', 'Running'),
      _EquipData('AC-105', 'Floor 1', 'Running'),
      _EquipData('AC-106', 'Floor 1', 'Running'),
      _EquipData('AC-107', 'Floor 1', 'Running'),
      _EquipData('AC-108', 'Floor 1', 'Running'),
      _EquipData('AC-109', 'Floor 1', 'Alert'),
      _EquipData('AC-110', 'Floor 1', 'Offline'),
      _EquipData('AC-201', 'Floor 2', 'Running'),
      _EquipData('AC-202', 'Floor 2', 'Running'),
      _EquipData('AC-203', 'Floor 2', 'Running'),
      _EquipData('AC-204', 'Floor 2', 'Running'),
      _EquipData('AC-205', 'Floor 2', 'Running'),
      _EquipData('AC-206', 'Floor 2', 'Running'),
      _EquipData('AC-207', 'Floor 2', 'Running'),
      _EquipData('AC-208', 'Floor 2', 'Running'),
      _EquipData('AC-209', 'Floor 2', 'Running'),
      _EquipData('AC-210', 'Floor 2', 'Running'),
      _EquipData('AC-211', 'Floor 2', 'Running'),
      _EquipData('AC-212', 'Floor 2', 'Running'),
      _EquipData('AC-213', 'Floor 2', 'Alert'),
      _EquipData('AC-214', 'Floor 2', 'Alert'),
      _EquipData('AC-215', 'Floor 2', 'Offline'),
      _EquipData('AC-301', 'Floor 3', 'Running'),
      _EquipData('AC-302', 'Floor 3', 'Running'),
      _EquipData('AC-303', 'Floor 3', 'Running'),
      _EquipData('AC-304', 'Floor 3', 'Running'),
      _EquipData('AC-305', 'Floor 3', 'Running'),
      _EquipData('AC-306', 'Floor 3', 'Running'),
      _EquipData('AC-307', 'Floor 3', 'Running'),
      _EquipData('AC-308', 'Floor 3', 'Running'),
      _EquipData('AC-309', 'Floor 3', 'Running'),
      _EquipData('AC-310', 'Floor 3', 'Running'),
      _EquipData('AC-311', 'Floor 3', 'Running'),
      _EquipData('AC-312', 'Floor 3', 'Running'),
      _EquipData('AC-313', 'Floor 3', 'Running'),
      _EquipData('AC-314', 'Floor 3', 'Running'),
      _EquipData('AC-315', 'Floor 3', 'Running'),
      _EquipData('AC-316', 'Floor 3', 'Running'),
      _EquipData('AC-317', 'Floor 3', 'Running'),
      _EquipData('AC-318', 'Floor 3', 'Running'),
      _EquipData('AC-319', 'Floor 3', 'Alert'),
      _EquipData('AC-320', 'Floor 3', 'Alert'),
      _EquipData('AC-321', 'Floor 3', 'Alert'),
      _EquipData('AC-322', 'Floor 3', 'Alert'),
      _EquipData('AC-323', 'Floor 3', 'Offline'),
      _EquipData('AC-324', 'Floor 3', 'Offline'),
    ];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header('AC Status Distribution'),
          const SizedBox(height: 12),
          // Doughnut Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: _cardDeco(isDark, cardColor),
            child: Row(
              children: [
                SizedBox(
                  width: 130, height: 130,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      RepaintBoundary(
                        child: CustomPaint(
                          size: const Size(130, 130),
                          painter: DoughnutPainter(
                            segments: segments,
                            bgColor: isDark ? AppColors.background.withValues(alpha: 0.5) : const Color(0xFFF3F4F6),
                          ),
                        ),
                      ),
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('45', style: GoogleFonts.poppins(color: textColor, fontSize: 32, fontWeight: FontWeight.w800)),
                        Text('TOTAL UNITS', style: GoogleFonts.poppins(color: textColor.withOpacity(0.4), fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(width: 28),
                Expanded(
                  child: Column(
                    children: segments.map((seg) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(children: [
                        Container(width: 10, height: 10, decoration: BoxDecoration(color: seg.color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: seg.color.withValues(alpha: 0.3), blurRadius: 6)])),
                        const SizedBox(width: 10),
                        Expanded(child: Text(seg.label, style: GoogleFonts.poppins(color: textColor.withValues(alpha: 0.7), fontSize: 13, fontWeight: FontWeight.w500))),
                        Text('${seg.value.toInt()}', style: GoogleFonts.poppins(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
                      ]),
                    )).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _header('AC Status by Equipment'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: _cardDeco(isDark, cardColor),
            child: Column(
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('AC Status by Systems', style: GoogleFonts.poppins(color: textColor, fontSize: 15, fontWeight: FontWeight.w700)),
                  GestureDetector(
                    onTap: () => _showEquipmentPopup(context, allEquipment, isDark),
                    child: Text('View All', style: GoogleFonts.poppins(color: const Color(0xFF0EA5E9), fontSize: 13, fontWeight: FontWeight.w600)),
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
          Text(f.name, style: GoogleFonts.poppins(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
          Text('${f.total} Units', style: GoogleFonts.poppins(color: textColor.withOpacity(0.4), fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 8, 
          child: Row(children: [
            Flexible(flex: (f.running * 100 / total).round(), child: Container(color: const Color(0xFF6CC042))),
            if (f.alert > 0) Flexible(flex: (f.alert * 100 / total).round(), child: Container(color: const Color(0xFFF43F5E))),
            if (f.offline > 0) Flexible(flex: (f.offline * 100 / total).round(), child: Container(color: const Color(0xFF94A3B8))),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      Row(children: [
        _statusIndicator('${f.running} Running', const Color(0xFF6CC042)),
        if (f.alert > 0) ...[const SizedBox(width: 16), _statusIndicator('${f.alert} Alert', const Color(0xFFF43F5E))],
        if (f.offline > 0) ...[const SizedBox(width: 16), _statusIndicator('${f.offline} Offline', const Color(0xFF94A3B8))],
      ]),
    ]);
  }

  Widget _statusIndicator(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.poppins(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _header(String title) => Text(title.toUpperCase(),
      style: GoogleFonts.poppins(color: textColor.withValues(alpha: 0.4), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2));

  BoxDecoration _cardDeco(bool isDark, Color cardColor) => BoxDecoration(
      color: cardColor,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05)));
}

// ──────────────────────────────────────────────────────────────
// TRENDS VIEW
// ──────────────────────────────────────────────────────────────
class _TrendsView extends StatelessWidget {
  final bool isDark;
  final Color textColor;
  const _TrendsView({required this.isDark, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ENVIRONMENTAL TRENDS', style: GoogleFonts.poppins(color: textColor.withValues(alpha: 0.4), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          const SizedBox(height: 12),
          const LineChartCard(
            title: 'Average Temperature Trend (°C)',
            color: Color(0xFF0EA5E9),
            data: [27.5, 28.2, 27.8, 28.5, 27.9, 29.1, 30.2, 29.5, 31.2, 31.84, 31.5, 31.2, 30.8],
            labels: ['00:00', '04:00', '08:00', '12:00', '16:00', '20:00'],
            currentValue: '31.84°C',
          ),
          const SizedBox(height: 20),
          const LineChartCard(
            title: 'Average Humidity Trend (%)',
            color: Color(0xFF6CC042),
            data: [35, 33, 30, 28, 32, 31, 34, 31, 33, 31.9, 36, 38, 37],
            labels: ['00:00', '04:00', '08:00', '12:00', '16:00', '20:00'],
            currentValue: '31.90%',
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
  int? _hoverIndex;

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
        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, style: GoogleFonts.poppins(color: textColor.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(widget.currentValue, style: GoogleFonts.poppins(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Text('Today', style: GoogleFonts.poppins(color: textColor.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w600)),
                Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: textColor.withValues(alpha: 0.7)),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) {
                  final idx = (d.localPosition.dx / constraints.maxWidth * (widget.data.length - 1)).round().clamp(0, widget.data.length - 1);
                  if (_hoverIndex != idx) setState(() => _hoverIndex = idx);
                },
                onPanEnd: (_) => setState(() => _hoverIndex = null),
                onTapDown: (d) {
                  final idx = (d.localPosition.dx / constraints.maxWidth * (widget.data.length - 1)).round().clamp(0, widget.data.length - 1);
                  setState(() => _hoverIndex = idx);
                },
                onTapUp: (_) => setState(() => _hoverIndex = null),
                child: Stack(clipBehavior: Clip.none, children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                      painter: LineChartPainter(data: widget.data, color: widget.color, isDark: isDark, hoverIndex: _hoverIndex),
                    ),
                  ),
                  if (_hoverIndex != null) _tooltip(constraints, _hoverIndex!, widget.data[_hoverIndex!], widget.color, textColor, isDark),
                ]),
              );
            }),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: widget.labels.map((l) => Text(l, style: GoogleFonts.poppins(color: textColor.withValues(alpha: 0.3), fontSize: 10, fontWeight: FontWeight.w600))).toList(),
          ),
        ],
      ),
    );
  }

  Widget _tooltip(BoxConstraints c, int idx, double val, Color color, Color textColor, bool isDark) {
    double x = (idx / (widget.data.length - 1)) * c.maxWidth;
    x = x.clamp(45.0, c.maxWidth - 45.0);
    return Positioned(
      left: x - 45, top: -12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1B172E) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('${idx.toString().padLeft(2, '0')}:00', style: GoogleFonts.poppins(color: textColor.withValues(alpha: 0.4), fontSize: 9, fontWeight: FontWeight.w600)),
          Text(val.toStringAsFixed(2), style: GoogleFonts.poppins(color: textColor, fontSize: 13, fontWeight: FontWeight.w800)),
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
  const _FloorData(this.name, this.total, this.running, this.alert, this.offline);
}

class _EquipData {
  final String id;
  final String floor;
  final String status;
  const _EquipData(this.id, this.floor, this.status);
}

void _showEquipmentPopup(BuildContext context, List<_EquipData> equipment, bool isDark) {
  final cardColor = isDark ? const Color(0xFF2A244D) : Colors.white;
  final bgColor = isDark ? const Color(0xFF1B172E) : const Color(0xFFF5F5F5);
  final textColor = isDark ? Colors.white : const Color(0xFF1B172E);

  Color statusColor(String s) {
    if (s == 'Running') return const Color(0xFF6CC042);
    if (s == 'Alert') return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('All Equipments',
                      style: GoogleFonts.poppins(color: textColor, fontSize: 18, fontWeight: FontWeight.w800)),
                  Text('${equipment.length} units',
                      style: GoogleFonts.poppins(color: textColor.withValues(alpha: 0.4), fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            // Legend
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Row(
                children: [
                  _legendDot(const Color(0xFF6CC042), 'Running', textColor),
                  const SizedBox(width: 16),
                  _legendDot(const Color(0xFFF59E0B), 'Alert', textColor),
                  const SizedBox(width: 16),
                  _legendDot(const Color(0xFFEF4444), 'Offline', textColor),
                ],
              ),
            ),
            const Divider(height: 1),
            // List
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: equipment.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final e = equipment[i];
                  final sc = statusColor(e.status);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: sc.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: sc.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.ac_unit_rounded, color: sc, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.id, style: GoogleFonts.poppins(color: textColor, fontSize: 14, fontWeight: FontWeight.w700)),
                              Text(e.floor, style: GoogleFonts.poppins(color: textColor.withValues(alpha: 0.4), fontSize: 11, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: sc.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: sc.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 6, height: 6, decoration: BoxDecoration(color: sc, shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Text(e.status, style: GoogleFonts.poppins(color: sc, fontSize: 11, fontWeight: FontWeight.w700)),
                            ],
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
  );
}

Widget _legendDot(Color color, String label, Color textColor) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 6),
    Text(label, style: GoogleFonts.poppins(color: textColor.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.w600)),
  ],
);

class DoughnutPainter extends CustomPainter {
  final List<ChartSegment> segments;
  final Color bgColor;
  final double strokeWidth;
  const DoughnutPainter({required this.segments, required this.bgColor, this.strokeWidth = 24});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(center, radius, Paint()..color = bgColor..style = PaintingStyle.stroke..strokeWidth = strokeWidth..strokeCap = StrokeCap.round);
    double total = segments.fold(0, (s, e) => s + e.value);
    if (total == 0) return;
    double angle = -math.pi / 2;
    const gap = 0.06;
    for (final seg in segments) {
      final sweep = (seg.value / total) * 2 * math.pi - gap;
      if (sweep > 0) canvas.drawArc(rect, angle + gap / 2, sweep, false, Paint()..color = seg.color..style = PaintingStyle.stroke..strokeWidth = strokeWidth..strokeCap = StrokeCap.round);
      angle += sweep + gap;
    }
  }

  @override
  bool shouldRepaint(DoughnutPainter old) => old.bgColor != bgColor || old.segments.length != segments.length;
}

class LineChartPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final bool isDark;
  final int? hoverIndex;
  const LineChartPainter({required this.data, required this.color, required this.isDark, this.hoverIndex});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final maxV = data.reduce(math.max) * 1.1;
    final minV = data.reduce(math.min) * 0.9;
    final range = (maxV - minV) == 0 ? 1.0 : maxV - minV;
    double xOf(int i) => (i / (data.length - 1)) * size.width;
    double yOf(double v) => size.height - ((v - minV) / range * size.height);

    final fill = Path()..moveTo(xOf(0), size.height)..lineTo(xOf(0), yOf(data[0]));
    final line = Path()..moveTo(xOf(0), yOf(data[0]));
    for (int i = 1; i < data.length; i++) {
      final cp = xOf(i - 1) + (xOf(i) - xOf(i - 1)) / 2;
      fill.cubicTo(cp, yOf(data[i - 1]), cp, yOf(data[i]), xOf(i), yOf(data[i]));
      line.cubicTo(cp, yOf(data[i - 1]), cp, yOf(data[i]), xOf(i), yOf(data[i]));
    }
    fill..lineTo(xOf(data.length - 1), size.height)..close();

    canvas.drawPath(fill, Paint()..shader = LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [color.withValues(alpha: isDark ? 0.3 : 0.15), color.withValues(alpha: 0)],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));
    canvas.drawPath(line, Paint()..color = color..strokeWidth = 3.5..style = PaintingStyle.stroke..strokeCap = StrokeCap.round);

    if (hoverIndex != null && hoverIndex! < data.length) {
      final hx = xOf(hoverIndex!); final hy = yOf(data[hoverIndex!]);
      canvas.drawLine(Offset(hx, 0), Offset(hx, size.height), Paint()..color = color.withValues(alpha: 0.15)..strokeWidth = 1.5);
      canvas.drawCircle(Offset(hx, hy), 10, Paint()..color = color.withValues(alpha: 0.2));
      canvas.drawCircle(Offset(hx, hy), 6, Paint()..color = color);
      canvas.drawCircle(Offset(hx, hy), 3, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(LineChartPainter old) => old.hoverIndex != hoverIndex || old.isDark != isDark || old.data.length != data.length;
}
