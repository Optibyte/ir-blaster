import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/theme/theme_provider.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:ir_blaster_ac/screens/ac_app/sigin.dart';
import 'package:ir_blaster_ac/screens/ac_app/create_system_page.dart';
import 'package:ir_blaster_ac/screens/ac_app/create_equipment_page.dart';
import 'package:ir_blaster_ac/screens/ac_app/equipment_list_page.dart';
import 'package:ir_blaster_ac/screens/ac_app/system_list_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Sign Out',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Are you sure you want to sign out?',
          style: GoogleFonts.inter(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.offline,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Sign Out', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await AuthService.logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SignInPage()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final subtitleColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surface;
    final borderColor = isDark ? AppColors.dividerDark : AppColors.divider;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'System Configurations',
            style: GoogleFonts.outfit(
              color: textColor,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),



          // ── App Configuration ──
          _buildSectionCard(
            title: 'App Configuration',
            icon: Icons.tune_rounded,
            iconColor: AppColors.fanPurple,
            isDark: isDark,
            cardColor: cardColor,
            borderColor: borderColor,
            textColor: textColor,
            subtitleColor: subtitleColor,
            children: [
              // Dark Mode Toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.dark_mode_rounded, size: 18, color: subtitleColor),
                      const SizedBox(width: 12),
                      Text(
                        'Dark Mode',
                        style: GoogleFonts.inter(
                          color: textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Consumer<ThemeProvider>(
                    builder: (context, themeProvider, _) {
                      return Switch.adaptive(
                        value: themeProvider.isDarkMode,
                        onChanged: (val) => themeProvider.setDarkMode(val),
                        activeColor: AppColors.primary,
                        activeTrackColor: AppColors.primarySurface,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── System Management ──
          _buildSectionCard(
            title: 'System Management',
            icon: Icons.settings_rounded,
            iconColor: AppColors.primary,
            isDark: isDark,
            cardColor: cardColor,
            borderColor: borderColor,
            textColor: textColor,
            subtitleColor: subtitleColor,
            children: [
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreateSystemPage()),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.add_circle_outline_rounded, size: 18, color: subtitleColor),
                          const SizedBox(width: 12),
                          Text(
                            'Create System',
                            style: GoogleFonts.inter(
                              color: textColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Icon(Icons.chevron_right_rounded, size: 20, color: subtitleColor),
                    ],
                  ),
                ),
              ),
              const Divider(height: 16),
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SystemListPage()),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.dns_rounded, size: 18, color: subtitleColor),
                          const SizedBox(width: 12),
                          Text(
                            'Manage Systems',
                            style: GoogleFonts.inter(
                              color: textColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Icon(Icons.chevron_right_rounded, size: 20, color: subtitleColor),
                    ],
                  ),
                ),
              ),
              const Divider(height: 16),
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreateEquipmentPage()),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.ac_unit_rounded, size: 18, color: subtitleColor),
                          const SizedBox(width: 12),
                          Text(
                            'Create Equipment',
                            style: GoogleFonts.inter(
                              color: textColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Icon(Icons.chevron_right_rounded, size: 20, color: subtitleColor),
                    ],
                  ),
                ),
              ),
              const Divider(height: 16),
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const EquipmentListPage()),
                  );
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.edit_attributes_rounded, size: 18, color: subtitleColor),
                          const SizedBox(width: 12),
                          Text(
                            'Manage Equipment',
                            style: GoogleFonts.inter(
                              color: textColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      Icon(Icons.chevron_right_rounded, size: 20, color: subtitleColor),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── About & Version ──
          _buildSectionCard(
            title: 'About & Version',
            icon: Icons.info_outline_rounded,
            iconColor: AppColors.coolBlue,
            isDark: isDark,
            cardColor: cardColor,
            borderColor: borderColor,
            textColor: textColor,
            subtitleColor: subtitleColor,
            children: [
              _buildInfoRow('App', 'Smart IR Blaster Controller', subtitleColor, textColor),
              _buildInfoRow('Version', '1.0.0', subtitleColor, textColor),
              _buildInfoRow('By', 'Sustainabyte Technology Pvt. Ltd.', subtitleColor, textColor),
            ],
          ),

          const SizedBox(height: 24),

          // ── Sign Out Button ──
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _handleLogout,
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: Text(
                'Sign Out',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.offline,
                side: BorderSide(color: AppColors.offline.withValues(alpha: 0.3)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required bool isDark,
    required Color cardColor,
    required Color borderColor,
    required Color textColor,
    required Color subtitleColor,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: GoogleFonts.outfit(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color subtitleColor, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              color: subtitleColor,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: GoogleFonts.inter(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
