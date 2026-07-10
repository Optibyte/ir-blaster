import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ir_blaster_ac/screens/mode_selection_page.dart';
import 'package:ir_blaster_ac/screens/ac_app/dashboard_screen.dart';
import 'package:ir_blaster_ac/screens/ac_app/system_view.dart';
import 'package:ir_blaster_ac/screens/ac_app/device_detail_page.dart';
import 'package:ir_blaster_ac/widgets/top_navbar.dart';

class MainNavigationPage extends StatefulWidget {
  final int initialIndex;
  const MainNavigationPage({super.key, this.initialIndex = 0});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _currentIndex = 0;
  late final PageController _pageController;
  int _systemCount = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1B172E) : const Color(0xFFF8FAFC),
      body: Column(
        children: [
          // Top Navbar (Only show for AC App tabs)
          if (_currentIndex > 0)
            SafeArea(
              bottom: false,
              child: TopNavbar(
                showIcons: true,
                hideBranding: _currentIndex == 1, // Hide branding on Systems View
                title: _currentIndex == 1 ? 'SYSTEMS VIEW' : 'SUMMARY',
                totalCount: _currentIndex == 1 ? '$_systemCount' : null,
              ),
            ),

          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              children: [
                const ModeSelectionPage(),
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
                const DashboardScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(isDark),
    );
  }

  Widget _buildBottomBar(bool isDark) {
    if (_currentIndex == 0) {
      // Mode Selection Navbar
      return Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: 0,
          onTap: (index) {
            if (index == 1) {
              _pageController.animateToPage(1,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut);
            }
          },
          backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          selectedItemColor: const Color(0xFF6CC042),
          unselectedItemColor: isDark ? Colors.white54 : Colors.black45,
          selectedLabelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 12),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_remote),
              label: 'Mode Selection',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.grid_view_outlined),
              label: 'Views',
            ),
          ],
        ),
      );
    } else {
      // AC App Navbar
      return Container(
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
              _pageController.animateToPage(0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut);
            } else {
              _pageController.animateToPage(index,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut);
            }
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFF6CC042),
          unselectedItemColor: isDark ? Colors.white38 : Colors.black38,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700),
          unselectedLabelStyle: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.arrow_back_ios_new_rounded),
              label: 'Back',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.layers_outlined),
              activeIcon: Icon(Icons.layers_rounded),
              label: 'Systems',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard_rounded),
              label: 'Summary',
            ),
          ],
        ),
      );
    }
  }
}
