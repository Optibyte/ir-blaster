// import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Single source of truth for IR Blaster colors and [ThemeData].
///
/// Change brand / surface / text colors here — [AppColors] and [ThemeData]
/// follow automatically. User light/dark preference is applied via
/// [ThemeProvider] + [ThemeMode] in [main.dart].
abstract final class IrBlasterBrand {
  static const Color accent = Color(0xFF6CC042);
  static const Color scaffoldDark = Color(0xFF1B172E);
  static const Color surfaceDark = Color(0xFF2A244D);
  static const Color borderDark = Color(0xFF3D3560);
  static const Color scaffoldLight = Color(0xFFF8FAFC);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color borderLight = Color(0xFFE0E0E0);
  static const Color primaryDark = Color(0xFF1B172E);
  static const Color error = Color(0xFFE63946);
  static const Color running = Color(0xFF6CC042);
  static const Color stopped = Color(0xFFE63946);
  static const Color moving = Color(0xFF0077BE);
  static const Color cardBackgroundLight = Color(0xFFE5E5E5);
}

/// Semantic colors exposed through [ThemeExtension] (light + dark palettes).
@immutable
class IrBlasterColors extends ThemeExtension<IrBlasterColors> {
  const IrBlasterColors({
    required this.scaffoldBackground,
    required this.surfaceElevated,
    required this.accent,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.navBar,
    required this.cardBackground,
    required this.running,
    required this.stopped,
    required this.moving,
    required this.disconnected,
  });

  final Color scaffoldBackground;
  final Color surfaceElevated;
  final Color accent;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color navBar;
  final Color cardBackground;
  final Color running;
  final Color stopped;
  final Color moving;
  final Color disconnected;

  static const IrBlasterColors dark = IrBlasterColors(
    scaffoldBackground: IrBlasterBrand.scaffoldDark,
    surfaceElevated: IrBlasterBrand.surfaceDark,
    accent: IrBlasterBrand.accent,
    border: IrBlasterBrand.borderDark,
    textPrimary: Colors.white,
    textSecondary: Color(0xFFB0B0B0),
    navBar: IrBlasterBrand.scaffoldDark,
    cardBackground: IrBlasterBrand.surfaceDark,
    running: IrBlasterBrand.running,
    stopped: IrBlasterBrand.stopped,
    moving: IrBlasterBrand.moving,
    disconnected: IrBlasterBrand.stopped,
  );

  static const IrBlasterColors light = IrBlasterColors(
    scaffoldBackground: IrBlasterBrand.scaffoldLight,
    surfaceElevated: IrBlasterBrand.surfaceLight,
    accent: IrBlasterBrand.accent,
    border: IrBlasterBrand.borderLight,
    textPrimary: Colors.black87,
    textSecondary: Colors.black54,
    navBar: IrBlasterBrand.surfaceLight,
    cardBackground: IrBlasterBrand.cardBackgroundLight,
    running: IrBlasterBrand.running,
    stopped: IrBlasterBrand.stopped,
    moving: IrBlasterBrand.moving,
    disconnected: IrBlasterBrand.stopped,
  );

  @override
  IrBlasterColors copyWith({
    Color? scaffoldBackground,
    Color? surfaceElevated,
    Color? accent,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? navBar,
    Color? cardBackground,
    Color? running,
    Color? stopped,
    Color? moving,
    Color? disconnected,
  }) {
    return IrBlasterColors(
      scaffoldBackground: scaffoldBackground ?? this.scaffoldBackground,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      accent: accent ?? this.accent,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      navBar: navBar ?? this.navBar,
      cardBackground: cardBackground ?? this.cardBackground,
      running: running ?? this.running,
      stopped: stopped ?? this.stopped,
      moving: moving ?? this.moving,
      disconnected: disconnected ?? this.disconnected,
    );
  }

  @override
  IrBlasterColors lerp(ThemeExtension<IrBlasterColors>? other, double t) {
    if (other is! IrBlasterColors) return this;
    Color lerpColor(Color a, Color b) => Color.lerp(a, b, t)!;
    return IrBlasterColors(
      scaffoldBackground:
          lerpColor(scaffoldBackground, other.scaffoldBackground),
      surfaceElevated: lerpColor(surfaceElevated, other.surfaceElevated),
      accent: lerpColor(accent, other.accent),
      border: lerpColor(border, other.border),
      textPrimary: lerpColor(textPrimary, other.textPrimary),
      textSecondary: lerpColor(textSecondary, other.textSecondary),
      navBar: lerpColor(navBar, other.navBar),
      cardBackground: lerpColor(cardBackground, other.cardBackground),
      running: lerpColor(running, other.running),
      stopped: lerpColor(stopped, other.stopped),
      moving: lerpColor(moving, other.moving),
      disconnected: lerpColor(disconnected, other.disconnected),
    );
  }
}

/// Builds light/dark [ThemeData] via [flex_color_scheme].

/// Convenient [BuildContext] access: `context.irColors.accent`

