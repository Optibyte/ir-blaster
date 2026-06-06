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

class _SignInPageState extends State<SignInPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnackBar('Please enter email and password', isError: true);
      return;
    }

    if (!AuthService.isValidEmail(email)) {
      _showSnackBar('Please enter a valid email address', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    final error = await AuthService.login(email, password);
    debugPrint('🔎 [SignIn] Login completed. error=$error');

    if (!mounted) return;

    if (error == null) {
      // Login successful — verify session, then check role and navigate.
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
            'The current account is not authorized for this application. Please sign in with a valid account.',
            isError: true,
          );
          return;
        }
      } else {
        debugPrint('⚠️ [SignIn] check-ac-access skipped: companyId missing');
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
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        backgroundColor: isError ? const Color(0xFFE53935) : AppColors.button,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: isDark ? AppColors.background : Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Image.asset(
                  'assets/images/logo.png',
                  width: 76,
                  height: 76,
                  fit: BoxFit.contain,
                  errorBuilder: (c, e, s) => _fallbackLogo(),
                ),
                const SizedBox(height: 12),

                // Title
                Text(
                  'Optibyte',
                  style: GoogleFonts.poppins(
                    color: isDark ? Colors.white : colorScheme.primary,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),

                // Subtitle
                Text(
                  'Powering the Future of Energy',
                  style: GoogleFonts.poppins(
                    color: (isDark ? Colors.white : colorScheme.primary)
                        .withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 32),

                // Sign in heading
                Text(
                  'Sign in to access Dashboard',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: isDark ? Colors.white : colorScheme.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 28),

                // Email field
                _RoundedInput(
                  hint: 'Email',
                  obscure: false,
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: Icons.email_outlined,
                ),
                const SizedBox(height: 16),

                // Password field with toggle
                _RoundedInput(
                  hint: 'Password',
                  obscure: _obscurePassword,
                  controller: _passwordController,
                  prefixIcon: Icons.lock_outline,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: isDark
                          ? Colors.white38
                          : colorScheme.primary.withValues(alpha: 0.4),
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),

                const SizedBox(height: 22),

                // Sign in button
                _isLoading
                    ? _LoadingButton()
                    : _GreenButton(
                        label: 'Sign In  →',
                        onPressed: _handleSignIn,
                      ),

                const SizedBox(height: 12),

                // Forget password
                TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Forget Password ?',
                    style: GoogleFonts.poppins(
                      color: (isDark ? Colors.white : colorScheme.primary)
                          .withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Footer disclaimer
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        height: 1.5,
                      ),
                      children: [
                        TextSpan(
                          text: 'Only the user who has the license of ',
                          style: TextStyle(
                            color: (isDark ? Colors.white : colorScheme.primary)
                                .withValues(alpha: 0.55),
                          ),
                        ),
                        TextSpan(
                          text: 'Sustainabyte Technology Pvt. Ltd.',
                          style: TextStyle(
                            color:
                                isDark ? AppColors.button : colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text: ' can access this dashboard',
                          style: TextStyle(
                            color: (isDark ? Colors.white : colorScheme.primary)
                                .withValues(alpha: 0.55),
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
    );
  }

  Widget _fallbackLogo() {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.button,
            AppColors.button.withValues(alpha: 0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Icon(
        Icons.memory,
        color: Colors.white,
        size: 36,
      ),
    );
  }
}

// ─────────────────────── Widgets ───────────────────────

class _RoundedInput extends StatelessWidget {
  final String hint;
  final bool obscure;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final IconData? prefixIcon;
  final Widget? suffixIcon;

  const _RoundedInput({
    required this.hint,
    this.obscure = false,
    this.controller,
    this.keyboardType,
    this.prefixIcon,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      cursorColor: isDark ? AppColors.button : colorScheme.primary,
      style: GoogleFonts.poppins(
        color: isDark ? Colors.white : colorScheme.primary,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(
          color: (isDark ? Colors.white : colorScheme.primary)
              .withValues(alpha: 0.35),
          fontSize: 14,
        ),
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon,
                color: (isDark ? Colors.white : colorScheme.primary)
                    .withValues(alpha: 0.4),
                size: 20)
            : null,
        suffixIcon: suffixIcon,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
        filled: true,
        fillColor: isDark
            ? AppColors.secondaryBackground
            : colorScheme.primary.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: isDark
              ? BorderSide.none
              : BorderSide(color: colorScheme.primary.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: isDark
              ? BorderSide.none
              : BorderSide(color: colorScheme.primary.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
              color: isDark ? AppColors.button : colorScheme.primary, width: 1),
        ),
      ),
    );
  }
}

class _GreenButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _GreenButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? AppColors.button : colorScheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 0,
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class _LoadingButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = isDark ? AppColors.button : colorScheme.primary;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: null,
        style: ElevatedButton.styleFrom(
          backgroundColor: baseColor.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 0,
        ),
        child: const SizedBox(
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
