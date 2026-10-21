import 'device_profile.dart';

/// Validate a manually edited device profile before touching persistent data.
/// The encoded X-App-Device protocol separates fields with semicolons.
class ManualDeviceInfo {
  static DeviceProfile validate(DeviceProfile value) {
    String checked(String name, String raw) {
      final text = raw.trim();
      if (text.isEmpty) throw FormatException('请填写$name');
      if (text.length > 96 ||
          text.contains(';') ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)) {
        throw FormatException('$name包含无效字符或过长');
      }
      return text;
    }

    final manufacturer = checked('制造商', value.manufacturer);
    final brand = checked('品牌', value.brand);
    final model = checked('型号', value.model);
    final build = checked('构建号', value.buildNumber);
    final sdk = value.sdkInt.trim();
    final sdkValue = int.tryParse(sdk);
    if (sdkValue == null || sdkValue < 16 || sdkValue > 200) {
      throw const FormatException('SDK 版本必须是有效的整数（16～200）');
    }
    final androidVersion = value.androidVersion.trim();
    if (!RegExp(r'^[0-9]{1,2}(?:\.[0-9]{1,2})?$')
        .hasMatch(androidVersion)) {
      throw const FormatException('Android 版本应为数字，例如 14 或 12.1');
    }
    return DeviceProfile(manufacturer, brand, model, build, sdk, androidVersion);
  }
}
