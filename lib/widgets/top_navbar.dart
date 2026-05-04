import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:ir_blaster_ac/core/theme/theme_provider.dart';
import 'package:provider/provider.dart';

/// Redesigned Top Navbar with premium Optibyte branding
class TopNavbar extends StatelessWidget {
  final bool showIcons;
  final String? title;
  final String? subtitle;
  final IconData? titleIcon;
  final String? totalCount;
  final bool hideBranding;

  const TopNavbar({
    super.key,
    this.showIcons = true,
    this.title,
    this.subtitle,
    this.titleIcon,
    this.totalCount,
    this.hideBranding = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: BoxDecoration(
        color: Colors.transparent,
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Row(
        children: [
          // Branding Section
          GestureDetector(
            onTap: () {
              // Maybe navigate to branding page or refresh
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!hideBranding) ...[
                  // Logo without frame
                  Container(
                    padding: const EdgeInsets.all(4),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 32,
                      height: 32,
                      fit: BoxFit.contain,
                      errorBuilder: (c, e, s) => const Icon(
                        Icons.bolt_rounded,
                        color: Color(0xFF6CC042),
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                ],
                if (hideBranding) ...[
                  // Systems View Icon
                  Icon(
                    Icons.layers_rounded,
                    color: const Color(0xFF6CC042),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                ],
                Column(
                  crossAxisAlignment: hideBranding ? CrossAxisAlignment.start : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!hideBranding)
                      Text(
                        'Optibyte',
                        style: GoogleFonts.poppins(
                          color: isDark ? Colors.white : const Color(0xFF1B172E),
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    if (title != null)
                      Text(
                        title!,
                        style: GoogleFonts.poppins(
                          color: hideBranding 
                              ? (isDark ? const Color.fromARGB(255, 232, 221, 221) : const Color(0xFF1B172E))
                              : const Color(0xFF6CC042),
                          fontSize: hideBranding ? 20 : 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: GoogleFonts.poppins(
                          color: isDark ? Colors.white.withOpacity(0.4) : Colors.black.withOpacity(0.4),
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          const Spacer(),

          // Actions & Count Section
          if (hideBranding && totalCount != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF6CC042).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF6CC042).withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    'TOTAL: ',
                    style: GoogleFonts.poppins(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    totalCount!,
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF6CC042),
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            )
          else if (showIcons && !hideBranding)
            Row(
              children: [
                _ActionButton(
                  icon: Icons.settings_outlined,
                  onPressed: () => _showProfilePopup(context),
                  isDark: isDark,
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _showProfilePopup(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final userData = await AuthService.getUserData();
    final email = await AuthService.getEmail();

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.2),
      builder: (context) => Stack(
        children: [
          Positioned(
            top: 60,
            right: 20,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 260,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1B172E) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profile Header (Small)
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: const Color(0xFF6CC042).withOpacity(0.1),
                          child: const Icon(Icons.person_rounded, color: Color(0xFF6CC042), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userData?['name'] ?? 'User',
                                style: GoogleFonts.poppins(
                                  color: isDark ? Colors.white : const Color(0xFF1B172E),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                email ?? '',
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  color: (isDark ? Colors.white : const Color(0xFF1B172E)).withOpacity(0.5),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 16),

                    const SizedBox(height: 8),

                    // Logout Item
                    _menuItem(
                      icon: Icons.logout_rounded,
                      label: 'Logout',
                      isDark: isDark,
                      color: const Color(0xFFEF4444),
                      onTap: () {
                        Navigator.pop(context);
                        _showLogoutDialog(context);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
    Widget? trailing,
    Color? color,
  }) {
    final baseColor = color ?? (isDark ? Colors.white : const Color(0xFF1B172E));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, color: baseColor.withOpacity(0.7), size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  color: baseColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2D2D44) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Logout',
          style: GoogleFonts.poppins(
            color: isDark ? Colors.white : const Color(0xFF1B172E),
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Are you sure you want to sign out of your account?',
          style: GoogleFonts.poppins(
            color: (isDark ? Colors.white : const Color(0xFF1B172E)).withOpacity(0.7),
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                color: (isDark ? Colors.white : const Color(0xFF1B172E)).withOpacity(0.5),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              await AuthService.logout();
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isDark;
  final bool hasBadge;

  const _ActionButton({
    required this.icon,
    required this.onPressed,
    required this.isDark,
    this.hasBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              icon,
              color: (isDark ? Colors.white : const Color(0xFF1B172E)).withOpacity(0.7),
              size: 22,
            ),
            if (hasBadge)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? const Color(0xFF1B172E) : Colors.white,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
