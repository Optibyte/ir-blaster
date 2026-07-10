import 'package:flutter/material.dart';

/// Design tokens for the Smart IR Blaster Controller.
/// Uses a **Modern Eco-Tech** aesthetic with Forest Green primary.
class AppColors {
  AppColors._();

  // ── Primary Palette ───────────────────────────────────────────────────
  static const Color primary = Color(0xFF2E7D52);        // Forest Green
  static const Color primaryLight = Color(0xFF4CAF7D);    // Eco Green
  static const Color primaryDark = Color(0xFF1B5E3B);     // Dark Spruce
  static const Color primarySurface = Color(0xFFE8F5EE);  // Soft Sage
  static const Color accent = Color(0xFF00BFA5);          // Mint Teal

  // ── Backgrounds & Surfaces ────────────────────────────────────────────
  static const Color background = Color(0xFFF5F7FA);      // Cool Slate
  static const Color surface = Color(0xFFFFFFFF);          // White
  static const Color backgroundDark = Color(0xFF0F1923);   // Deep Navy
  static const Color surfaceDark = Color(0xFF1A2332);      // Card Dark

  // ── Text ──────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF1A1A2E);      // Ink Blue
  static const Color textSecondary = Color(0xFF6B7280);    // Muted Gray
  static const Color textHint = Color(0xFF9CA3AF);         // Slate Outlines
  static const Color textPrimaryDark = Color(0xFFE8ECF1);
  static const Color textSecondaryDark = Color(0xFF94A3B8);

  // ── Borders & Dividers ────────────────────────────────────────────────
  static const Color divider = Color(0xFFE5E7EB);         // Border Gray
  static const Color dividerDark = Color(0xFF2A3A4A);

  // ── Status Colors ─────────────────────────────────────────────────────
  static const Color online = Color(0xFF22C55E);           // Emerald Green
  static const Color offline = Color(0xFFEF4444);          // Coral Red
  static const Color warning = Color(0xFFF59E0B);          // Amber Gold

  // ── Mode-Specific Colors ──────────────────────────────────────────────
  static const Color coolBlue = Color(0xFF3B82F6);
  static const Color heatOrange = Color(0xFFF97316);
  static const Color dryYellow = Color(0xFFEAB308);
  static const Color fanPurple = Color(0xFF8B5CF6);

  // ── Legacy compatibility ──────────────────────────────────────────────
  static const Color button = Color(0xFF2E7D52);
  static const Color running = Color(0xFF22C55E);
  static const Color stopped = Color(0xFFEF4444);
  static const Color disconnected = Color(0xFFEF4444);
  static const Color moving = Color(0xFF3B82F6);
  static const Color cardBackground = Color(0xFFF5F7FA);
  static const Color navBar = Color(0xFFFFFFFF);
  static const Color darkBlue = Color(0xFF0F1923);
  static const Color secondaryBackground = Color(0xFF1A2332);
  static const Color onDarkTextPrimary = Color(0xFFE8ECF1);
  static const Color onDarkTextSecondary = Color(0xFF94A3B8);
}
