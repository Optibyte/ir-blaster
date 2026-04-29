import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:esp/widgets/top_navbar.dart';
import 'package:esp/screens/ac_app/system_view.dart';
import 'package:esp/screens/ac_app/device_detail_page.dart';
import 'package:esp/screens/ac_app/ac_control_page.dart';
import 'package:esp/screens/ac_app/dashboard_screen.dart';

class HomePage extends StatefulWidget {
  final VoidCallback? onBack;
  const HomePage({super.key, this.onBack});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 1; // Start on Dashboard (index 1 since 0 is Back)
  int _systemCount = 0;
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      body: Column(
        children: [
          // Top Navbar
          SafeArea(
            bottom: false,
            child: TopNavbar(
              showIcons: true,
              hideBranding: _currentIndex == 2, // Only hide branding for Systems
              title: _currentIndex == 2 ? 'SYSTEMS VIEW' : 'VIEWS',
              // subtitle: 'HVAC MONITORING',
              totalCount: _currentIndex == 2 ? '$_systemCount' : null,
            ),
          ),

          // Body
          Expanded(
            child: IndexedStack(
              index: _currentIndex - 1, // Offset by 1 because 0 is Back
              children: [
                const DashboardScreen(),
                SystemViewPage(
                  onCountChanged: (count) => setState(() => _systemCount = count),
                  onViewPressed: (systemId, systemName, systemShortId) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DeviceDetailPage(
                          deviceName: systemName,
                          systemId: systemId,
                          systemShortId: systemShortId,
                        ),
                      ),
                    );
                  },
                ),
                _buildLogs(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            if (index == 0) {
              widget.onBack?.call();
            } else {
              setState(() => _currentIndex = index);
            }
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFF6CC042),
          unselectedItemColor: isDark ? Colors.white38 : Colors.black38,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: GoogleFonts.poppins(
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: GoogleFonts.poppins(
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.arrow_back_ios_new_rounded),
              label: 'Back',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard_rounded),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.layers_outlined),
              activeIcon: Icon(Icons.layers_rounded),
              label: 'Systems',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.history_rounded),
              activeIcon: Icon(Icons.history_rounded),
              label: 'Logs',
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildLogs() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          // Internal header removed to prevent double-header issue
          const SizedBox(height: 20),

          // 1. Connected Devices
          _buildSummaryItem(
            'CONNECTED DEVICES',
            'Total : ',
            '50',
            null,
            isDark,
          ),
          _buildDivider(isDark),

          // 2. Disconnected Devices
          _buildSummaryItem(
            'DISCONNECTED DEVICES',
            'Total : ',
            '10',
            null,
            isDark,
          ),
          _buildDivider(isDark),

          // 3. AC Status
          _buildSummaryItem(
            'AC STATUS',
            'NO. ON : ',
            '50',
            'NO. OFF : 10',
            isDark,
          ),
          _buildDivider(isDark),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
    String title,
    String label,
    String value,
    String? extra,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white : const Color(0xFF1B172E),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            RichText(
              text: TextSpan(
                style: GoogleFonts.poppins(
                  color: isDark ? Colors.white : const Color(0xFF1B172E),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                children: [
                  TextSpan(text: label),
                  TextSpan(
                    text: value,
                    style: const TextStyle(color: Color(0xFF6CC042)),
                  ),
                  if (extra != null) ...[
                    const TextSpan(text: '     '),
                    TextSpan(text: extra.split(':')[0] + ': '),
                    TextSpan(
                      text: extra.split(':')[1],
                      style: const TextStyle(color: Color(0xFF6CC042)),
                    ),
                  ],
                ],
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF6CC042).withOpacity(0.4),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'View List',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDivider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Divider(
        color: (isDark ? Colors.white : const Color(0xFF1B172E)).withOpacity(
          0.1,
        ),
        thickness: 1,
      ),
    );
  }
}
