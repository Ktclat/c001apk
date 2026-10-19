import 'dart:io';

import 'package:flutter/services.dart';

class DeviceProfile {
  const DeviceProfile(this.manufacturer, this.brand, this.model,
      this.buildNumber, this.sdkInt, this.androidVersion);

  final String manufacturer, brand, model, buildNumber, sdkInt, androidVersion;

  static Future<DeviceProfile> current() async {
    if (Platform.isAndroid) {
      final info = await const MethodChannel('samples.flutter.dev/channel')
          .invokeMapMethod<String, String>('getProtocolDeviceProfile');
      // Use non-unique model/system properties only. Do not request hardware
      // serial, IMEI, Android ID or OAID for the protocol profile.
      if (info == null) throw StateError('无法读取设备与系统配置');
      return DeviceProfile(
          info['manufacturer']!,
          info['brand']!,
          info['model']!,
          info['buildNumber']!,
          info['sdkInt']!,
          info['androidVersion']!);
    }
    // Desktop speaks the Android API using one consistent compatibility
    // profile; these are not properties of the user's desktop hardware.
    return const DeviceProfile(
        'Google', 'google', 'Pixel 7', 'TQ3A.230805.001', '33', '13');
  }
}
