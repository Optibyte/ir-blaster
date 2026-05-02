import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';

class ACSplashScreen extends StatelessWidget {
  const ACSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21), // Deep Navy
      body: Stack(
        children: [
          // Background Gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.5,
                  colors: [
                    Color(0xFF1D2136),
                    Color(0xFF0A0E21),
                  ],
                ),
              ),
            ),
          ),
          
          // Decorative Subtle Glow
          Center(
            child: FadeIn(
              duration: const Duration(seconds: 2),
              child: Container(
                width: 350,
                height: 350,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.05),
                      blurRadius: 120,
                      spreadRadius: 60,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Main Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo with scale and fade
                ZoomIn(
                  duration: const Duration(milliseconds: 1500),
                  child: Hero(
                    tag: 'app_logo',
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 200,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.ac_unit, color: Colors.white, size: 80);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                
                // Branding
                FadeInUp(
                  delay: const Duration(milliseconds: 800),
                  child: Text(
                    'OPTIBYTE',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 8,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                
                // Tagline
                FadeInUp(
                  delay: const Duration(milliseconds: 1200),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'SMART AC CONTROL',
                      style: GoogleFonts.inter(
                        color: Colors.cyanAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Bottom Loading Indicator (Subtle)
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: FadeIn(
              delay: const Duration(seconds: 2),
              child: Center(
                child: Column(
                  children: [
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withOpacity(0.3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Optimizing your environment...',
                      style: GoogleFonts.inter(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 12,
                        fontWeight: FontWeight.w300,
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
