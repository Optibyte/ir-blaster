import 'package:flutter/material.dart';

class FanSpeedWidget extends StatelessWidget {
  final Color themeGreen;
  final VoidCallback onSwing;

  const FanSpeedWidget({
    super.key,
    required this.themeGreen,
    required this.onSwing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSwing,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 110,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: themeGreen, borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            const Icon(Icons.swap_horiz, color: Colors.black),
            const SizedBox(height: 6),
            const Text('SWING', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
