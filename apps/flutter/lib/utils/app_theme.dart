import 'package:flutter/material.dart';

/// Font choices are stored as stable integer values in the settings box.
///
/// Flutter's Material defaults to Roboto on Android. The Android "sans-serif"
/// family requests the device's native sans-serif mapping instead, so OEM
/// system font changes can take effect when the ROM exposes them to Flutter.
enum AppFontChoice {
  system,
  material,
  notoSans;

  static const bundledFontFamily = 'C001NotoSans';

  /// Old stored choices 0 and 1 remain valid. New installations use Noto.
  static AppFontChoice fromStorage(Object? value) => switch (value) {
        null => AppFontChoice.notoSans,
        0 => AppFontChoice.system,
        1 => AppFontChoice.material,
        2 => AppFontChoice.notoSans,
        _ => AppFontChoice.system,
      };

  String get label => switch (this) {
        AppFontChoice.system => '跟随系统',
        AppFontChoice.material => 'Material 原版',
        AppFontChoice.notoSans => '思源黑体 · 清爽（推荐）',
      };

  String get description => switch (this) {
        AppFontChoice.system => '随厂商 ROM 映射，字形与行距可能因手机而不同',
        AppFontChoice.material => '采用 Flutter/Material 原始字体映射',
        AppFontChoice.notoSans => '内置标准字重的简体中文黑体，离线显示更一致',
      };

  String? familyForPlatform(TargetPlatform platform) {
    if (this == AppFontChoice.notoSans) return bundledFontFamily;
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
  AppFontChoice fontChoice = AppFontChoice.notoSans,
}) {
  final fontFamily = fontChoice.familyForPlatform(theme.platform);
  final themedText = fontFamily == null
      ? theme.textTheme
      : theme.textTheme.apply(fontFamily: fontFamily);
  final textTheme = themedText.copyWith(
    bodyLarge: themedText.bodyLarge?.copyWith(height: 1.48),
    bodyMedium: themedText.bodyMedium?.copyWith(height: 1.46),
    bodySmall: themedText.bodySmall?.copyWith(height: 1.40),
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
