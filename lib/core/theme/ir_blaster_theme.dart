import 'package:flutter/material.dart';
import 'package:ir_blaster_ac/core/constants/colors.dart';

/// Single source of truth for IR Blaster colors via [ThemeExtension].
///
/// Uses the **Modern Eco-Tech** palette from [AppColors].
/// User light/dark preference is applied via [ThemeProvider] + [ThemeMode] in [main.dart].
abstract final class IrBlasterBrand {
  static const Color accent = AppColors.primary;
  static const Color scaffoldDark = AppColors.backgroundDark;
  static const Color surfaceDark = AppColors.surfaceDark;
  static const Color borderDark = AppColors.dividerDark;
  static const Color scaffoldLight = AppColors.background;
  static const Color surfaceLight = AppColors.surface;
  static const Color borderLight = AppColors.divider;
  static const Color primaryDark = AppColors.backgroundDark;
  static const Color error = AppColors.offline;
  static const Color running = AppColors.online;
  static const Color stopped = AppColors.offline;
  static const Color moving = AppColors.coolBlue;
  static const Color cardBackgroundLight = AppColors.background;
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
    scaffoldBackground: AppColors.backgroundDark,
    surfaceElevated: AppColors.surfaceDark,
    accent: AppColors.primary,
    border: AppColors.dividerDark,
    textPrimary: AppColors.textPrimaryDark,
    textSecondary: AppColors.textSecondaryDark,
    navBar: AppColors.surfaceDark,
    cardBackground: AppColors.surfaceDark,
    running: AppColors.online,
    stopped: AppColors.offline,
    moving: AppColors.coolBlue,
    disconnected: AppColors.offline,
  );

  static const IrBlasterColors light = IrBlasterColors(
    scaffoldBackground: AppColors.background,
    surfaceElevated: AppColors.surface,
    accent: AppColors.primary,
    border: AppColors.divider,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    navBar: AppColors.surface,
    cardBackground: AppColors.background,
    running: AppColors.online,
    stopped: AppColors.offline,
    moving: AppColors.coolBlue,
    disconnected: AppColors.offline,
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
