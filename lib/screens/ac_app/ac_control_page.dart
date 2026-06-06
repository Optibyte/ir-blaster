import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;

class ACControlPage extends StatefulWidget {
  const ACControlPage({super.key});

  @override
  State<ACControlPage> createState() => _ACControlPageState();
}

class _ACControlPageState extends State<ACControlPage> {
  double _setTemperature = 24.0;
  double _actualTemperature = 32.5;
  double _humidity = 45.0;

  TimeOfDay _scheduleStartTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _scheduleEndTime = const TimeOfDay(hour: 18, minute: 0);

  TimeOfDay _lunchStartTime = const TimeOfDay(hour: 12, minute: 30);
  TimeOfDay _lunchEndTime = const TimeOfDay(hour: 13, minute: 30);

  bool _isScheduleEnabled = true;
  bool _isLunchEnabled = true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = const Color(0xFF6CC042);
    final accentColor = const Color(0xFF0EA5E9);
    final cardColor = isDark ? const Color(0xFF2A244D) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CONTROL PANEL',
                    style: GoogleFonts.poppins(
                      color: textColor.withOpacity(0.4),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Office AC System',
                    style: GoogleFonts.poppins(
                      color: textColor,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.power_settings_new_rounded,
                    color: primaryColor, size: 28),
              ),
            ],
          ),

          const SizedBox(height: 30),

          // Actual Temperature - BIGGER as requested
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? const Color(0xFF2A244D).withOpacity(0.5)
                    : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withOpacity(0.1),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.black.withOpacity(0.03),
                  width: 2,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer Ring
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: CircularProgressIndicator(
                      value: _actualTemperature / 40,
                      strokeWidth: 12,
                      backgroundColor: isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.black.withOpacity(0.03),
                      valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  // Inner Content
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'ACTUAL TEMP',
                        style: GoogleFonts.poppins(
                          color: textColor.withOpacity(0.4),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _actualTemperature.toStringAsFixed(1),
                            style: GoogleFonts.poppins(
                              color: textColor,
                              fontSize: 72, // Even bigger font
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 2),
                            child: Text(
                              '°C',
                              style: GoogleFonts.poppins(
                                color: primaryColor,
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: primaryColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                  color: primaryColor, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'RUNNING',
                              style: GoogleFonts.poppins(
                                color: primaryColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 40),

          // Temperature & Humidity Controls Row
          Row(
            children: [
              Expanded(
                child: _buildControlCard(
                  title: 'TARGET TEMP',
                  value: '${_setTemperature.toInt()}°C',
                  icon: Icons.thermostat_rounded,
                  color: accentColor,
                  isDark: isDark,
                  onIncrement: () => setState(() =>
                      _setTemperature = math.min(30, _setTemperature + 1)),
                  onDecrement: () => setState(() =>
                      _setTemperature = math.max(16, _setTemperature - 1)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildControlCard(
                  title: 'HUMIDITY',
                  value: '${_humidity.toInt()}%',
                  icon: Icons.water_drop_rounded,
                  color: Colors.indigoAccent,
                  isDark: isDark,
                  onIncrement: () =>
                      setState(() => _humidity = math.min(100, _humidity + 5)),
                  onDecrement: () =>
                      setState(() => _humidity = math.max(0, _humidity - 5)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Daily Schedule Card
          _buildTimeCard(
            title: 'DAILY SCHEDULE',
            startTime: _scheduleStartTime,
            endTime: _scheduleEndTime,
            isEnabled: _isScheduleEnabled,
            color: const Color(0xFFF59E0B),
            isDark: isDark,
            onToggle: (val) => setState(() => _isScheduleEnabled = val),
            onStartTimeTap: () => _selectTime(context, true, true),
            onEndTimeTap: () => _selectTime(context, true, false),
          ),

          const SizedBox(height: 16),

          // Lunch Time Card
          _buildTimeCard(
            title: 'LUNCH TIME',
            startTime: _lunchStartTime,
            endTime: _lunchEndTime,
            isEnabled: _isLunchEnabled,
            color: primaryColor,
            isDark: isDark,
            onToggle: (val) => setState(() => _isLunchEnabled = val),
            onStartTimeTap: () => _selectTime(context, false, true),
            onEndTimeTap: () => _selectTime(context, false, false),
          ),
        ],
      ),
    );
  }

  Widget _buildControlCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
    required VoidCallback onIncrement,
    required VoidCallback onDecrement,
  }) {
    final cardColor = isDark ? const Color(0xFF2A244D) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color.withOpacity(0.6), size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.poppins(
                  color: textColor.withOpacity(0.4),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.poppins(
              color: textColor,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _circleButton(Icons.remove, isDark, onDecrement),
              _circleButton(Icons.add, isDark, onIncrement),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeCard({
    required String title,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    required bool isEnabled,
    required Color color,
    required bool isDark,
    required ValueChanged<bool> onToggle,
    required VoidCallback onStartTimeTap,
    required VoidCallback onEndTimeTap,
  }) {
    final cardColor = isDark ? const Color(0xFF2A244D) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.05),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Switch.adaptive(
                value: isEnabled,
                onChanged: onToggle,
                activeColor: color,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _timePickerButton(
                  'START',
                  startTime.format(context),
                  isDark,
                  onStartTimeTap,
                ),
              ),
              const SizedBox(width: 20),
              Icon(Icons.arrow_forward_rounded,
                  color: textColor.withOpacity(0.2)),
              const SizedBox(width: 20),
              Expanded(
                child: _timePickerButton(
                  'END',
                  endTime.format(context),
                  isDark,
                  onEndTimeTap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timePickerButton(
      String label, String time, bool isDark, VoidCallback onTap) {
    final textColor = isDark ? Colors.white : const Color(0xFF1B172E);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(
              color: textColor.withOpacity(0.4),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            time,
            style: GoogleFonts.poppins(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton(IconData icon, bool isDark, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.05),
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            color: isDark ? Colors.white70 : Colors.black87, size: 20),
      ),
    );
  }

  Future<void> _selectTime(
      BuildContext context, bool isSchedule, bool isStart) async {
    final initialTime = isSchedule
        ? (isStart ? _scheduleStartTime : _scheduleEndTime)
        : (isStart ? _lunchStartTime : _lunchEndTime);

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF6CC042),
              onPrimary: Colors.white,
              surface: Color(0xFF131122),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF131122),
            timePickerTheme: const TimePickerThemeData(
              backgroundColor: Color(0xFF131122),
              dialBackgroundColor: Color(0xFF1B172E),
              dialHandColor: Color(0xFF6CC042),
              dialTextColor: Colors.white,
              entryModeIconColor: Colors.white,
              hourMinuteColor: Color(0xFF1B172E),
              hourMinuteTextColor: Colors.white,
              dayPeriodColor: Color(0xFF1B172E),
              dayPeriodTextColor: Colors.white,
              dayPeriodBorderSide: BorderSide.none,
              helpTextStyle: TextStyle(color: Colors.white),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isSchedule) {
          if (isStart)
            _scheduleStartTime = picked;
          else
            _scheduleEndTime = picked;
        } else {
          if (isStart)
            _lunchStartTime = picked;
          else
            _lunchEndTime = picked;
        }
      });
    }
  }
}
