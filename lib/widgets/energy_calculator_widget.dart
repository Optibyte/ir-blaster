import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class EnergyCalculatorWidget extends StatefulWidget {
  const EnergyCalculatorWidget({super.key});

  @override
  State<EnergyCalculatorWidget> createState() => _EnergyCalculatorWidgetState();
}

class _EnergyCalculatorWidgetState extends State<EnergyCalculatorWidget> {
  final TextEditingController _energyController = TextEditingController(text: '863.3082');
  final TextEditingController _costPerEnergyController = TextEditingController(text: '13');
  final TextEditingController _costPerCo2Controller = TextEditingController(text: '0.82');

  double _energyCost = 0.0;
  double _co2Emission = 0.0;

  @override
  void initState() {
    super.initState();
    _calculateValues();
    _energyController.addListener(_calculateValues);
    _costPerEnergyController.addListener(_calculateValues);
    _costPerCo2Controller.addListener(_calculateValues);
  }

  @override
  void dispose() {
    _energyController.dispose();
    _costPerEnergyController.dispose();
    _costPerCo2Controller.dispose();
    super.dispose();
  }

  void _calculateValues() {
    final energy = double.tryParse(_energyController.text) ?? 0.0;
    final costPerEnergy = double.tryParse(_costPerEnergyController.text) ?? 0.0;
    final costPerCo2 = double.tryParse(_costPerCo2Controller.text) ?? 0.0;

    setState(() {
      _energyCost = energy * costPerEnergy;
      _co2Emission = energy * costPerCo2;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? const Color(0xFF6CC042) : const Color(0xFF1B172E);
    final bgColor = isDark ? const Color(0xFF2A244D) : Colors.white;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: primaryColor.withOpacity(0.1),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calculate_outlined, color: primaryColor, size: 24),
              const SizedBox(width: 12),
              Text(
                'Energy Calculator',
                style: GoogleFonts.poppins(
                  color: isDark ? Colors.white : primaryColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Inputs Row
          Row(
            children: [
              Expanded(child: _buildInputField('Energy', Icons.bolt, _energyController, isDark, primaryColor, const Color(0xFFF59E0B))),
              const SizedBox(width: 12),
              Expanded(child: _buildInputField('Cost Per Energy', Icons.currency_rupee, _costPerEnergyController, isDark, primaryColor, const Color(0xFF10B981))),
              const SizedBox(width: 12),
              Expanded(child: _buildInputField('Cost Per CO₂', Icons.cloud_outlined, _costPerCo2Controller, isDark, primaryColor, const Color(0xFF3B82F6))),
            ],
          ),
          const SizedBox(height: 24),

          // Read-only Outputs
          _buildOutputField('Energy Cost', Icons.currency_rupee, _energyCost.toStringAsFixed(4), isDark, primaryColor, const Color(0xFF10B981)),
          const SizedBox(height: 16),
          _buildOutputField('CO₂ Emission', Icons.cloud_outlined, _co2Emission.toStringAsFixed(2), isDark, primaryColor, const Color(0xFF3B82F6)),
        ],
      ),
    );
  }

  Widget _buildInputField(String label, IconData icon, TextEditingController controller, bool isDark, Color primaryColor, Color iconColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 14),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  color: (isDark ? Colors.white : primaryColor).withOpacity(0.8),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 45,
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.3) : Colors.grey.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primaryColor.withOpacity(0.15)),
          ),
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white : primaryColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOutputField(String label, IconData icon, String value, bool isDark, Color primaryColor, Color iconColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: (isDark ? Colors.white : primaryColor).withOpacity(0.8),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withOpacity(0.3) : Colors.grey.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primaryColor.withOpacity(0.15)),
          ),
          child: Text(
            value,
            style: GoogleFonts.poppins(
              color: isDark ? Colors.white : primaryColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}
