import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('scroll hiding persists independently of navigation and legacy policy', () async {
    final directory =
        await Directory.systemTemp.createTemp('navigation-default-');
    Hive.init(directory.path);
    GStorage.settings = await Hive.openBox('settings');
    try {
      expect(GStorage.floatingTabBar, false);
      expect(GStorage.hideFloatingTabBarOnScroll, true);
      await GStorage.setHideFloatingTabBarOnScroll(false);
      expect(GStorage.hideFloatingTabBarOnScroll, false);
      await GStorage.setFloatingTabBar(true);
      await GStorage.setFloatingTabBar(false);
      expect(GStorage.hideFloatingTabBarOnScroll, false);
      await GStorage.setFloatingTabBar(true);
      var settings = GStorage.settings;
      for (final oldValue in [0, 1, 2, 999, 'unknown']) {
        await settings.put('floatingNavigationPolicy', oldValue);
        await settings.close();
        // Production binds its late-final box once per process. Reopen locally
        // to inspect persisted bytes without illegally rebinding that singleton.
        settings = await Hive.openBox('settings');
        expect(settings.get(SettingsBoxKey.floatingTabBar), true);
        expect(settings.get(SettingsBoxKey.hideFloatingTabBarOnScroll), false);
        expect(settings.get('floatingNavigationPolicy'), oldValue,
            reason: 'No destructive preference migration');
      }
      await settings.put(SettingsBoxKey.floatingTabBar, false);
      await settings.close();
      settings = await Hive.openBox('settings');
      expect(settings.get(SettingsBoxKey.floatingTabBar), false);
      expect(settings.get(SettingsBoxKey.hideFloatingTabBarOnScroll), false);
      expect(settings.get('floatingNavigationPolicy'), 'unknown');
      await settings.put(SettingsBoxKey.hideFloatingTabBarOnScroll, true);
      await settings.close();
      settings = await Hive.openBox('settings');
      expect(settings.get(SettingsBoxKey.hideFloatingTabBarOnScroll), true);
      expect(settings.get(SettingsBoxKey.floatingTabBar), false);
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}
