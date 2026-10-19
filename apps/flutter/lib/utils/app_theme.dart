import 'package:flutter/material.dart';

/// Font choices are stored as stable integer values in the settings box.
///
/// Flutter's Material defaults to Roboto on Android. The Android "sans-serif"
/// family requests the device's native sans-serif mapping instead, so OEM
/// system font changes can take effect when the ROM exposes them to Flutter.
enum AppFontChoice {
  system,
  material;

  static AppFontChoice fromStorage(Object? value) =>
      value == AppFontChoice.material.index
          ? AppFontChoice.material
          : AppFontChoice.system;

  String get label => switch (this) {
        AppFontChoice.system => '跟随系统（推荐）',
        AppFontChoice.material => 'Material 默认',
      };

  String get description => switch (this) {
        AppFontChoice.system => '优先使用手机的系统无衬线字体，实际效果取决于设备和系统',
        AppFontChoice.material => '使用 Flutter 的默认平台字体，便于和原版对比',
      };

  String? familyForPlatform(TargetPlatform platform) {
    if (this == AppFontChoice.material) return null;
    return switch (platform) {
      TargetPlatform.android || TargetPlatform.linux => 'sans-serif',
      TargetPlatform.windows => 'Segoe UI',
      // Flutter already chooses the platform's standard font on iOS/macOS.
      TargetPlatform.iOS ||
      TargetPlatform.macOS ||
      TargetPlatform.fuchsia => null,
    };
  }
}

/// Applies the selected font consistently to Material widgets and improves
/// Chinese text rhythm without changing touch target dimensions.
ThemeData applyAppTypography(
  ThemeData theme, {
  AppFontChoice fontChoice = AppFontChoice.system,
}) {
  final fontFamily = fontChoice.familyForPlatform(theme.platform);
  final themedText = fontFamily == null
      ? theme.textTheme
      : theme.textTheme.apply(fontFamily: fontFamily);
  final textTheme = themedText.copyWith(
    bodyLarge: themedText.bodyLarge?.copyWith(height: 1.5),
    bodyMedium: themedText.bodyMedium?.copyWith(height: 1.45),
    bodySmall: themedText.bodySmall?.copyWith(height: 1.4),
  );
  final primaryTextTheme = fontFamily == null
      ? theme.primaryTextTheme
      : theme.primaryTextTheme.apply(fontFamily: fontFamily);
  final base = theme.copyWith(
    textTheme: textTheme,
    primaryTextTheme: primaryTextTheme,
  );

  return base.copyWith(
    appBarTheme: base.appBarTheme.copyWith(
      centerTitle: false,
      scrolledUnderElevation: 0,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontSize: 18,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: base.colorScheme.onSurface,
      ),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      titleTextStyle: textTheme.titleMedium?.copyWith(
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w500,
        color: base.colorScheme.onSurface,
      ),
      subtitleTextStyle: textTheme.bodyMedium?.copyWith(
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: base.colorScheme.onSurfaceVariant,
      ),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontSize: 18,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: base.colorScheme.onSurface,
      ),
    ),
  );
}

/// Preserves the user's OS accessibility text scaling and the app's slider.
class AppTextScaler extends TextScaler {
  const AppTextScaler(this.system, this.factor);
  final TextScaler system;
  final double factor;
  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;
  @override
  double get textScaleFactor => scale(14) / 14;
  @override
  bool operator ==(Object other) =>
      other is AppTextScaler &&
      other.system == system &&
      other.factor == factor;
  @override
  int get hashCode => Object.hash(system, factor);
}
