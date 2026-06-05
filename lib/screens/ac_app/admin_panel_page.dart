import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:ir_blaster_ac/screens/ac_app/platform_admin_page.dart';
import 'package:ir_blaster_ac/screens/ac_app/company_admin_page.dart';
import 'package:ir_blaster_ac/screens/ac_app/sites_page.dart';

/// Routes the user to the correct admin console based on stored role.
class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({super.key});

  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage> {
  bool _isLoading = true;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  Future<void> _checkRole() async {
    try {
      final userData = await AuthService.getUserData();
      if (mounted) {
        setState(() {
          _userRole = AuthService.roleFromUserData(userData);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.button),
        ),
      );
    }

    if (AuthService.isPlatformAdminRole(_userRole ?? '')) {
      return const PlatformAdminPage();
    }

    if (AuthService.isCompanyAdminRole(_userRole ?? '')) {
      return const CompanyAdminPage();
    }

    if (AuthService.isSiteAdminRole(_userRole ?? '')) {
      return const SitesPage();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.gpp_bad_outlined,
                  color: Color(0xFFEF4444),
                  size: 48,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Access Restricted',
                style: GoogleFonts.poppins(
                  color: AppColors.onDarkTextPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You do not have permission to access the admin panel.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: AppColors.onDarkTextSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
