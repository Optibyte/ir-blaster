import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';

class ACSplashScreen extends StatefulWidget {
  const ACSplashScreen({super.key});

  @override
  State<ACSplashScreen> createState() => _ACSplashScreenState();
}

class _ACSplashScreenState extends State<ACSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1A14),
      body: Stack(
        children: [
          // Background radial gradient with Forest Green glow
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.4 + (_controller.value * 0.2),
                      colors: [
                        AppColors.primary.withValues(alpha: 0.08),
                        const Color(0xFF0A1A14),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Floating eco particles
          ...List.generate(6, (index) {
            final positions = [
              const Offset(40, 150),
              const Offset(280, 200),
              const Offset(120, 400),
              const Offset(300, 500),
              const Offset(60, 600),
              const Offset(250, 300),
            ];
            return Positioned(
              top: positions[index].dy,
              left: positions[index].dx,
              child: FadeIn(
                delay: Duration(milliseconds: 400 * index),
                duration: const Duration(seconds: 3),
                child: Container(
                  width: 3,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.15 + (index * 0.03)),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          // Main Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo with pulse animation
                ZoomIn(
                  duration: const Duration(milliseconds: 1200),
                  child: ScaleTransition(
                    scale: _pulseAnimation,
                    child: Hero(
                      tag: 'app_logo',
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              blurRadius: 60,
                              spreadRadius: 20,
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/logo.png',
                          width: 100,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppColors.primary,
                                    AppColors.primaryLight,
                                  ],
                                ),
                              ),
                              child: const Icon(
                                Icons.settings_remote_rounded,
                                color: Colors.white,
                                size: 48,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 48),

                // Brand name
                FadeInUp(
                  duration: const Duration(milliseconds: 1000),
                  delay: const Duration(milliseconds: 600),
                  child: Text(
                    'SMART CONTROL',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 6.0,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FadeInUp(
                  duration: const Duration(milliseconds: 1000),
                  delay: const Duration(milliseconds: 800),
                  child: Text(
                    'HUB',
                    style: GoogleFonts.outfit(
                      color: AppColors.primaryLight,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 12.0,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Animated accent line
                FadeIn(
                  delay: const Duration(milliseconds: 1200),
                  child: Container(
                    width: 48,
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.accent],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Tagline
                FadeInUp(
                  delay: const Duration(milliseconds: 1500),
                  child: Text(
                    'MANAGE YOUR CLIMATE GRID',
                    style: GoogleFonts.inter(
                      color: AppColors.primaryLight.withValues(alpha: 0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom loading indicator
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: FadeIn(
              delay: const Duration(seconds: 2),
              child: Center(
                child: Column(
                  children: [
                    SizedBox(
                      width: 40,
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.primary),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'CONNECTING TO SYSTEM',
                      style: GoogleFonts.inter(
                        color: Colors.white.withValues(alpha: 0.25),
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 2,
                      ),
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
}
