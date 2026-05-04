import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/services/api_service.dart';
import 'package:ir_blaster_ac/widgets/skeleton.dart';

import 'package:intl/intl.dart';

/// Widget showing three key energy metrics with a premium, glassmorphic design
class EnergyMetricsWidget extends StatefulWidget {
  const EnergyMetricsWidget({super.key});

  @override
  State<EnergyMetricsWidget> createState() => _EnergyMetricsWidgetState();
}

class _EnergyMetricsWidgetState extends State<EnergyMetricsWidget> {
  final ApiService _apiService = ApiService();
  double _totalEnergy = 0;
  double _totalCost = 0;
  double _totalEmission = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day, 0, 0, 0);
      final stop = DateTime(now.year, now.month, now.day, 23, 55, 0);

      final data = await _apiService.fetchEnergySummary(
        start: start,
        stop: stop,
      );
      if (data['success'] == true) {
        if (!mounted) return;
        setState(() {
          _totalEnergy = (data['totalEnergy'] as num).toDouble();
          _totalCost = (data['totalCost'] as num).toDouble();
          _totalEmission = (data['totalCarbonEmissionKg'] as num).toDouble();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching metrics: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  final _numberFormat = NumberFormat('#,##0.00');

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(child: Skeleton(height: 130, borderRadius: 24)),
            SizedBox(width: 12),
            Expanded(child: Skeleton(height: 130, borderRadius: 24)),
            SizedBox(width: 12),
            Expanded(child: Skeleton(height: 130, borderRadius: 24)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Row(
            children: [
              // Energy Consumption Card
              Expanded(
                child: _MetricCard(
                  title: 'Consumption',
                  value: _numberFormat.format(_totalEnergy),
                  unit: 'kWh',
                  icon: Icons.bolt_rounded,
                  color: const Color(0xFFFFD700),
                  delay: 0,
                ),
              ),
              const SizedBox(width: 12),
              // Energy Cost Card
              Expanded(
                child: _MetricCard(
                  title: 'Energy Cost',
                  value: _numberFormat.format(_totalCost),
                  unit: '₹',
                  icon: Icons.currency_rupee_rounded,
                  color: const Color(0xFF6CC042),
                  delay: 1,
                ),
              ),
              const SizedBox(width: 12),
              // Energy Emission Card
              Expanded(
                child: _MetricCard(
                  title: 'Emission',
                  value: _numberFormat.format(_totalEmission),
                  unit: 'kgCO₂',
                  icon: Icons.eco_rounded,
                  color: const Color(0xFF0EA5E9),
                  delay: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final int delay;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 600 + (delay * 200)),
      curve: Curves.easeOutBack,
      builder: (context, anim, child) {
        return Transform.scale(
          scale: anim,
          child: Opacity(
            opacity: anim.clamp(0.0, 1.0),
            child: Container(
              height: 130,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A244D) : Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(isDark ? 0.05 : 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                  if (isDark)
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                ],
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.05)
                      : const Color(0xFF1B172E).withOpacity(0.2),
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const Spacer(),
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      color: (isDark ? Colors.white : const Color(0xFF1B172E)).withOpacity(
                        0.5,
                      ),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          value,
                          style: GoogleFonts.poppins(
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1B172E),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    unit,
                    style: GoogleFonts.poppins(
                      color: color.withOpacity(0.8),
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
