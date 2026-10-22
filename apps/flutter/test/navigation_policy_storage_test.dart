import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('legacy policy values remain inert across settings reopen', () async {
    final directory =
        await Directory.systemTemp.createTemp('navigation-default-');
    Hive.init(directory.path);
    GStorage.settings = await Hive.openBox('settings');
    try {
      expect(GStorage.floatingTabBar, false);
      await GStorage.setFloatingTabBar(true);
      var settings = GStorage.settings;
      for (final oldValue in [0, 1, 2, 999, 'unknown']) {
        await settings.put('floatingNavigationPolicy', oldValue);
        await settings.close();
        // Production binds its late-final box once per process. Reopen locally
        // to inspect persisted bytes without illegally rebinding that singleton.
        settings = await Hive.openBox('settings');
        expect(settings.get(SettingsBoxKey.floatingTabBar), true);
        expect(settings.get('floatingNavigationPolicy'), oldValue,
            reason: 'No destructive preference migration');
      }
      await settings.put(SettingsBoxKey.floatingTabBar, false);
      await settings.close();
      settings = await Hive.openBox('settings');
      expect(settings.get(SettingsBoxKey.floatingTabBar), false);
      expect(settings.get('floatingNavigationPolicy'), 'unknown');
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}
