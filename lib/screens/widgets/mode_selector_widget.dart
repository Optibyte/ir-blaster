import 'package:flutter/material.dart';

class ModeSelectorWidget extends StatelessWidget {
  final Color themeGreen;
  final VoidCallback onMode;

  const ModeSelectorWidget({
    super.key,
    required this.themeGreen,
    required this.onMode,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onMode,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 110,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: themeGreen, borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            const Icon(Icons.tune, color: Colors.black),
            const SizedBox(height: 6),
            const Text('MODE', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
