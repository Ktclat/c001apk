import 'dart:async';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'components/custom_toast.dart';
import 'components/update_check_tile.dart';
import 'constants/constants.dart';
import 'logic/network/request.dart';
import 'pages/webview/captcha_page.dart';
import 'router/app_pages.dart';
import 'utils/storage_util.dart';
import 'utils/app_theme.dart';
import 'utils/bundled_font_licenses.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledFontLicenses();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = WindowOptions(
      minimumSize: const Size(400, 700),
      size: const Size(400, 700),
      center: true,
      skipTaskbar: false,
      titleBarStyle:
          Platform.isMacOS ? TitleBarStyle.hidden : TitleBarStyle.normal,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  await GStorage.init();
  HttpOverrides.global = CustomHttpOverrides();

  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
      statusBarBrightness: GStorage.getBrightness(),
      systemNavigationBarIconBrightness: GStorage.getBrightness(),
    ));
  }

  Request().captchaVerifier = verifyCaptcha;
  runApp(const C001APKAPP());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = Get.context;
    if (context != null) unawaited(AppUpdates.check(context, automatic: true));
  });
}

class C001APKAPP extends StatelessWidget {
  const C001APKAPP({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(builder: (lightDynamic, darkDynamic) {
      return ValueListenableBuilder(
        valueListenable: GStorage.settings.listenable(keys: [
          SettingsBoxKey.useMaterial,
          SettingsBoxKey.staticColor,
          SettingsBoxKey.selectedTheme,
          SettingsBoxKey.fontScale,
          SettingsBoxKey.fontChoice,
          SettingsBoxKey.readingPreset,
        ]),
        builder: (context, settings, _) =>
            _buildApp(context, lightDynamic, darkDynamic),
      );
    });
  }

  Widget _buildApp(BuildContext context, ColorScheme? lightDynamic,
      ColorScheme? darkDynamic) {
    bool useMaterial =
        GStorage.settings.get(SettingsBoxKey.useMaterial, defaultValue: true);
    int staticColor =
        GStorage.settings.get(SettingsBoxKey.staticColor, defaultValue: 0);
    double fontScale =
        GStorage.settings.get(SettingsBoxKey.fontScale, defaultValue: 1.0);
    final fontChoice = GStorage.fontChoice;
    ColorScheme? lightColorScheme;
    ColorScheme? darkColorScheme;
    if (lightDynamic != null && darkDynamic != null && useMaterial) {
      lightColorScheme = lightDynamic.harmonized();
      darkColorScheme = darkDynamic.harmonized();
    } else {
      lightColorScheme = ColorScheme.fromSeed(
        seedColor: Constants.seedColors[staticColor],
        brightness: Brightness.light,
      );
      darkColorScheme = ColorScheme.fromSeed(
        seedColor: Constants.seedColors[staticColor],
        brightness: Brightness.dark,
      );
    }

    final lightTheme = applyAppTypography(ThemeData(
      fontFamily: fontChoice.familyForPlatform(defaultTargetPlatform),
      colorScheme: lightColorScheme,
      useMaterial3: true,
      navigationBarTheme: NavigationBarThemeData(
          surfaceTintColor: (lightDynamic != null && useMaterial)
              ? lightColorScheme.surfaceTint
              : lightColorScheme.surfaceContainer),
      snackBarTheme: SnackBarThemeData(
        actionTextColor: lightColorScheme.primary,
        backgroundColor: lightColorScheme.secondaryContainer,
        closeIconColor: lightColorScheme.secondary,
        contentTextStyle: TextStyle(color: lightColorScheme.secondary),
        elevation: 20,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          // Avoid zooming a complex, image-heavy feed during route changes.
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      popupMenuTheme: PopupMenuThemeData(
        surfaceTintColor: lightColorScheme.surfaceTint,
      ),
      cardTheme: CardThemeData(
        surfaceTintColor: lightColorScheme.surfaceTint,
        shadowColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        surfaceTintColor: lightColorScheme.surfaceTint,
      ),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: lightColorScheme.onInverseSurface,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        refreshBackgroundColor: lightColorScheme.onSecondary,
      ),
    ), fontChoice: fontChoice);
    final darkTheme = applyAppTypography(ThemeData(
      fontFamily: fontChoice.familyForPlatform(defaultTargetPlatform),
      colorScheme: darkColorScheme,
      useMaterial3: true,
      navigationBarTheme: NavigationBarThemeData(
          surfaceTintColor: (lightDynamic != null && useMaterial)
              ? darkColorScheme.surfaceTint
              : darkColorScheme.surfaceContainer),
      snackBarTheme: SnackBarThemeData(
        actionTextColor: darkColorScheme.primary,
        backgroundColor: darkColorScheme.secondaryContainer,
        closeIconColor: darkColorScheme.secondary,
        contentTextStyle: TextStyle(color: darkColorScheme.secondary),
        elevation: 20,
      ),
      // Keep the pre-migration Android dark-mode transition. Newer Flutter
      // changes its default; that behavior is outside this toolchain update.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
        },
      ),
      popupMenuTheme: PopupMenuThemeData(
        surfaceTintColor: darkColorScheme.surfaceTint,
      ),
      cardTheme: CardThemeData(
        surfaceTintColor: darkColorScheme.surfaceTint,
        shadowColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        surfaceTintColor: darkColorScheme.surfaceTint,
      ),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: darkColorScheme.onInverseSurface,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        refreshBackgroundColor: darkColorScheme.onSecondary,
      ),
    ), fontChoice: fontChoice);
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: Constants.APP_NAME,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: GStorage.getThemeMode(),
      getPages: AppPages.getPages,
      initialRoute: '/',
      builder: (BuildContext context, Widget? child) {
        final brightness = switch (GStorage.getThemeMode()) {
          ThemeMode.light => Brightness.light,
          ThemeMode.dark => Brightness.dark,
          ThemeMode.system => MediaQuery.platformBrightnessOf(context),
        };
        // GetMaterialApp retains its initial themes. Apply the current theme
        // above the navigator so asynchronous system colors and settings
        // changes also reach existing routes and dialogs.
        return AnimatedTheme(
          data: brightness == Brightness.dark ? darkTheme : lightTheme,
          child: FlutterSmartDialog(
            toastBuilder: (String msg) => CustomToast(msg: msg),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: AppTextScaler(
                      MediaQuery.textScalerOf(context), fontScale)),
              child: child!,
            ),
          ),
        );
      },
    );
  }
}

class CustomHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)..userAgent = GStorage.userAgent;
  }
}
