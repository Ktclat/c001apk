import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:c001apk_flutter/utils/storage_util.dart';
import 'package:c001apk_flutter/utils/floating_navigation_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('policy defaults and accessibility suppression matrix', () {
    for (final invalid in [null, -1, 3, 'hideOnScroll', true]) {
      expect(FloatingNavigationPolicy.fromStorage(invalid),
          FloatingNavigationPolicy.automatic);
    }
    expect(FloatingNavigationPolicy.automatic.suppressionReason(true),
        'accessible_navigation');
    expect(FloatingNavigationPolicy.automatic.suppressionReason(false), isNull);
    for (final accessible in [false, true]) {
      expect(
          FloatingNavigationPolicy.hideOnScroll.suppressionReason(accessible),
          isNull);
      expect(
          FloatingNavigationPolicy.alwaysVisible.suppressionReason(accessible),
          'policy_always_visible');
    }
  });
  test('policy user choice persists across Hive close and reopen', () async {
    final directory =
        await Directory.systemTemp.createTemp('navigation-policy-');
    Hive.init(directory.path);
    GStorage.settings = await Hive.openBox('settings');
    try {
      expect(GStorage.floatingNavigationPolicy,
          FloatingNavigationPolicy.automatic);
      await GStorage.setFloatingNavigationPolicy(
          FloatingNavigationPolicy.hideOnScroll);
      await GStorage.settings.close();
      final reopened = await Hive.openBox('settings');
      expect(
          FloatingNavigationPolicy.fromStorage(
              reopened.get(SettingsBoxKey.floatingNavigationPolicy)),
          FloatingNavigationPolicy.hideOnScroll);
      await reopened.close();
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}
