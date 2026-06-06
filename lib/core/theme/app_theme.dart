import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // Dark Blue color from the original theme
  static const Color darkBlue = Color(0xFF1B172E);
  static const Color accentGreen = Color(0xFF6CC042);
  static const Color secondaryDark = Color(0xFF2A244D);
  
  // 👈 CHANGE YOUR PREFERRED LIGHT MODE CARD COLOR HERE
  static const Color preferredLightCardColor = Color(0xFFF8F9FA);

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: darkBlue,
    primaryColor: darkBlue,
    cardColor: secondaryDark,
    textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
    colorScheme: const ColorScheme.dark(
      primary: accentGreen,
      onPrimary: Colors.white,
      secondary: accentGreen,
      surface: secondaryDark,
      background: darkBlue,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: darkBlue,
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accentGreen,
        foregroundColor: Colors.white,
        textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
      ),
    ),
  );

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: Colors.white,
    primaryColor: darkBlue,
    cardColor: preferredLightCardColor,
    textTheme: GoogleFonts.poppinsTextTheme(ThemeData.light().textTheme),
    colorScheme: const ColorScheme.light(
      primary: darkBlue,
      onPrimary: Colors.white,
      secondary: accentGreen,
      surface: Colors.white,
      background: Colors.white,
      onSurface: darkBlue,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      elevation: 0,
      iconTheme: IconThemeData(color: darkBlue),
      titleTextStyle: TextStyle(color: darkBlue, fontSize: 20, fontWeight: FontWeight.bold),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: darkBlue,
        foregroundColor: Colors.white,
        textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
      ),
    ),
  );
}
