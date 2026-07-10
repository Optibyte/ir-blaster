import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';
import 'package:ir_blaster_ac/core/services/auth_service.dart';
import 'package:ir_blaster_ac/screens/main_navigation_page.dart';
import 'package:ir_blaster_ac/screens/ac_app/platform_admin_page.dart';
import 'package:ir_blaster_ac/screens/ac_app/company_sites_page.dart';
import 'package:ir_blaster_ac/screens/ac_app/company_admin_page.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _emailError;
  String? _passwordError;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    setState(() {
      _emailError = null;
      _passwordError = null;
    });

    if (email.isEmpty) {
      setState(() => _emailError = 'Email is required');
      return;
    }
    if (!AuthService.isValidEmail(email)) {
      setState(() => _emailError = 'Please enter a valid email address');
      return;
    }
    if (password.isEmpty) {
      setState(() => _passwordError = 'Password is required');
      return;
    }

    setState(() => _isLoading = true);

    final error = await AuthService.login(email, password);
    debugPrint('🔎 [SignIn] Login completed. error=$error');

    if (!mounted) return;

    if (error == null) {
      final verifiedUserData = await AuthService.verify();
      final userData = verifiedUserData ?? await AuthService.getUserData();
      final role = AuthService.roleFromUserData(userData);
      final companyId = AuthService.extractCompanyId(userData);

      debugPrint(
          '🔎 [SignIn] Verify completed. verified=${verifiedUserData != null}');
      debugPrint('🔎 [SignIn] Role="$role" companyId="$companyId"');

      if (!mounted) return;

      // ── AC System Access Check after verify ──
      if (companyId != null && companyId.isNotEmpty) {
        debugPrint(
            '🔎 [SignIn] Calling check-ac-access for companyId=$companyId');
        final hasAcAccess = await AuthService.checkAcSystemAccess(companyId);
        debugPrint('🔎 [SignIn] check-ac-access result=$hasAcAccess');
        if (!hasAcAccess) {
          await AuthService.logout();
          if (!mounted) return;
          setState(() => _isLoading = false);
          _showSnackBar(
            'The current account is not authorized for this application.',
            isError: true,
          );
          return;
        }
      }

      setState(() => _isLoading = false);

      Widget destination;
      if (AuthService.isPlatformAdminRole(role)) {
        destination = PlatformAdminPage(companyId: companyId);
      } else if (AuthService.isCompanyAdminRole(role)) {
        destination = const CompanyAdminPage();
      } else {
        final siteId =
            userData?['site']?.toString() ?? userData?['siteId']?.toString();
        if (siteId != null && siteId.isNotEmpty) {
          destination = const MainNavigationPage();
        } else {
          final companyId = AuthService.extractCompanyId(userData);
          final companyName =
              AuthService.extractCompanyName(userData) ?? 'Company Dashboard';
          final bucket = AuthService.extractBucket(userData) ?? '';
          destination = CompanySitesPage(
            companyId: companyId ?? '',
            companyName: companyName,
            bucket: bucket,
          );
        }
      }

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => destination),
        (route) => false,
      );
    } else {
      setState(() => _isLoading = false);
      _showSnackBar(error, isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        backgroundColor: isError ? AppColors.offline : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ── Logo & Branding ──
                    _buildLogo(isDark),
                    const SizedBox(height: 16),

                    Text(
                      'Smart Control Hub',
                      style: GoogleFonts.outfit(
                        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Sign in to manage your climate grid.',
                      style: GoogleFonts.inter(
                        color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),

                    const SizedBox(height: 40),

                    // ── Email Field ──
                    _buildFloatingTextField(
                      controller: _emailController,
                      focusNode: _emailFocus,
                      label: 'Email Address',
                      hint: 'you@company.com',
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      errorText: _emailError,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 16),

                    // ── Password Field ──
                    _buildFloatingTextField(
                      controller: _passwordController,
                      focusNode: _passwordFocus,
                      label: 'Password',
                      hint: '••••••••',
                      icon: Icons.lock_outline_rounded,
                      obscure: _obscurePassword,
                      errorText: _passwordError,
                      isDark: isDark,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textHint,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── Sign In Button ──
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _isLoading
                            ? _buildLoadingButton(isDark)
                            : _buildSignInButton(isDark),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Forgot Password ──
                    TextButton(
                      onPressed: () {},
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Forgot Password?',
                        style: GoogleFonts.inter(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),

                    // ── Footer ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: GoogleFonts.inter(fontSize: 12, height: 1.5),
                          children: [
                            TextSpan(
                              text: 'Only the user who has the license of ',
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.textSecondaryDark.withValues(alpha: 0.6)
                                    : AppColors.textSecondary.withValues(alpha: 0.6),
                              ),
                            ),
                            TextSpan(
                              text: 'Sustainabyte Technology Pvt. Ltd.',
                              style: TextStyle(
                                color: isDark ? AppColors.primaryLight : AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            TextSpan(
                              text: ' can access this dashboard',
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.textSecondaryDark.withValues(alpha: 0.6)
                                    : AppColors.textSecondary.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo(bool isDark) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.15),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Image.asset(
          'assets/images/logo.png',
          width: 80,
          height: 80,
          fit: BoxFit.contain,
          errorBuilder: (c, e, s) => Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primaryLight],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.settings_remote_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
    String? errorText,
    Widget? suffixIcon,
  }) {
    final hasError = errorText != null && errorText.isNotEmpty;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      keyboardType: keyboardType,
      cursorColor: AppColors.primary,
      style: GoogleFonts.inter(
        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        prefixIcon: Icon(
          icon,
          color: hasError
              ? AppColors.offline
              : (isDark ? AppColors.textSecondaryDark : AppColors.textHint),
          size: 20,
        ),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: isDark
            ? AppColors.surfaceDark
            : (hasError
                ? AppColors.offline.withValues(alpha: 0.04)
                : AppColors.primarySurface.withValues(alpha: 0.3)),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: hasError ? AppColors.offline : AppColors.divider,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: hasError
                ? AppColors.offline
                : (isDark ? AppColors.dividerDark : AppColors.divider),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: hasError ? AppColors.offline : AppColors.primary,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.offline, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.offline, width: 2),
        ),
        labelStyle: GoogleFonts.inter(
          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          fontSize: 14,
        ),
        hintStyle: GoogleFonts.inter(
          color: isDark
              ? AppColors.textSecondaryDark.withValues(alpha: 0.5)
              : AppColors.textHint.withValues(alpha: 0.6),
          fontSize: 14,
        ),
        errorStyle: GoogleFonts.inter(
          color: AppColors.offline,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildSignInButton(bool isDark) {
    return ElevatedButton(
      key: const ValueKey('sign_in'),
      onPressed: _handleSignIn,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Sign In',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward_rounded, size: 18),
        ],
      ),
    );
  }

  Widget _buildLoadingButton(bool isDark) {
    return Container(
      key: const ValueKey('loading'),
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
