import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ir_blaster_ac/core/services/api_service.dart';
import 'package:ir_blaster_ac/widgets/skeleton.dart';


class TopEquipmentWidget extends StatefulWidget {
  const TopEquipmentWidget({super.key});

  @override
  State<TopEquipmentWidget> createState() => _TopEquipmentWidgetState();
}

class _TopEquipmentWidgetState extends State<TopEquipmentWidget> {
  final ApiService _apiService = ApiService();
  List<dynamic> _equipmentData = [];
  bool _isLoading = true;
  String _selectedRange = 'today';

  final List<Map<String, String>> _timeRanges = [
    {'label': 'Today', 'value': 'today'},
    {'label': 'Yesterday', 'value': 'yesterday'},
    {'label': 'This Week', 'value': 'thisweek'},
    {'label': 'This Month', 'value': 'thismonth'},
    {'label': 'This Year', 'value': 'thisyear'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final response = await _apiService.fetchTopEquipmentConsumption(timeRange: _selectedRange);
      if (mounted) {
        setState(() {
          dynamic dataField = response['data'];
          if (dataField is Map && dataField.containsKey('data')) {
            _equipmentData = dataField['data'] ?? [];
          } else if (dataField is List) {
            _equipmentData = dataField;
          } else {
            _equipmentData = [];
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching top equipment: $e');
      if (mounted) {
        setState(() {
          _equipmentData = [];
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? const Color(0xFF8B5CF6) : const Color(0xFF1B172E);
    final accentColor = const Color(0xFFA78BFA);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A244D) : Colors.white,
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
          // Time Range Selector
          _buildRangeSelector(isDark, primaryColor),
          const SizedBox(height: 24),
          
          if (_isLoading)
            Column(
              children: List.generate(5, (index) => const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Skeleton(height: 30, borderRadius: 8),
              )),
            )
          else if (_equipmentData.isEmpty)
            SizedBox(
              height: 200,
              child: Center(
                child: Text(
                  'No data available for this range',
                  style: GoogleFonts.poppins(color: Colors.grey, fontSize: 12),
                ),
              ),
            )
          else
            ..._equipmentData.map((data) => _buildHorizontalBar(data, isDark, primaryColor, accentColor)).toList(),
        ],
      ),
    );
  }

  Widget _buildRangeSelector(bool isDark, Color primaryColor) {
    final accentColor = const Color(0xFF8B5CF6); // Violet accent

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: _timeRanges.map((range) {
          final isSelected = _selectedRange == range['value'];
          
          return GestureDetector(
            onTap: () {
              if (!isSelected) {
                setState(() => _selectedRange = range['value']!);
                _fetchData();
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected 
                    ? accentColor 
                    : (isDark ? Colors.white.withOpacity(0.05) : primaryColor.withOpacity(0.05)),
                borderRadius: BorderRadius.circular(12),
                boxShadow: isSelected ? [
                  BoxShadow(
                    color: accentColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ] : null,
              ),
              child: Text(
                range['label']!,
                style: GoogleFonts.poppins(
                  color: isSelected 
                      ? Colors.white 
                      : (isDark ? Colors.white70 : primaryColor.withOpacity(0.6)),
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHorizontalBar(dynamic data, bool isDark, Color primaryColor, Color accentColor) {
    final String name = data['equipmentName'] ?? 'Unknown';
    final double value = (data['consumption'] ?? 0.0).toDouble();
    
    double maxValue = 1.0;
    for (var item in _equipmentData) {
      final val = (item['consumption'] ?? 0.0).toDouble();
      if (val > maxValue) maxValue = val;
    }
    
    final double percentage = value / maxValue;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  name,
                  style: GoogleFonts.poppins(
                    color: isDark ? Colors.white : primaryColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${value.toStringAsFixed(1)} kWh',
                style: GoogleFonts.poppins(
                  color: isDark ? accentColor : primaryColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              Container(
                height: 10,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              FractionallySizedBox(
                widthFactor: percentage.clamp(0.01, 1.0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 1000),
                  curve: Curves.easeOutCubic,
                  height: 10,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        accentColor,
                        accentColor.withOpacity(0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
