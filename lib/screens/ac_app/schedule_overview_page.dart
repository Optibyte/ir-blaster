import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';

class ScheduleOverviewPage extends StatelessWidget {
  const ScheduleOverviewPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.background : Colors.grey[50];
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          'SCHEDULE OVERVIEW',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: textColor,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: const ScheduleOverviewContent(),
    );
  }
}

class ScheduleOverviewContent extends StatelessWidget {
  const ScheduleOverviewContent({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;

    final schedules = [
      _ScheduleItem(
        time: '09:30 AM',
        title: 'Schedule ON',
        subtitle: 'AC will turn ON',
        color: const Color(0xFF3B82F6),
      ),
      _ScheduleItem(
        time: '01:00 PM',
        title: 'Lunch OFF',
        subtitle: 'AC will turn OFF',
        color: const Color(0xFFF59E0B),
      ),
      _ScheduleItem(
        time: '02:00 PM',
        title: 'Lunch ON',
        subtitle: 'AC will turn ON',
        color: const Color(0xFF6CC042),
      ),
      _ScheduleItem(
        time: '07:00 PM',
        title: 'Schedule OFF',
        subtitle: 'AC will turn OFF',
        color: const Color(0xFFEF4444),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A244D) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFF1B172E).withOpacity(0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Schedule Overview (All Systems)',
              style: GoogleFonts.poppins(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 32),
            ...List.generate(schedules.length, (index) {
              return _buildScheduleRow(
                context,
                schedules[index],
                isLast: index == schedules.length - 1,
                textColor: textColor,
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleRow(BuildContext context, _ScheduleItem item, {required bool isLast, required Color textColor}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: item.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: item.color.withOpacity(0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: textColor.withOpacity(0.1),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 80,
            child: Text(
              item.time,
              style: GoogleFonts.poppins(
                color: textColor.withOpacity(0.9),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            width: 1.5,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: textColor.withOpacity(0.1),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: GoogleFonts.poppins(
                      color: item.color,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    style: GoogleFonts.poppins(
                      color: textColor.withOpacity(0.4),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleItem {
  final String time;
  final String title;
  final String subtitle;
  final Color color;

  _ScheduleItem({
    required this.time,
    required this.title,
    required this.subtitle,
    required this.color,
  });
}
