import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../utils/app_theme.dart';
import '../../utils/storage_util.dart';

/// Offers an explicit system-font option and an in-place comparison preview.
class FontChoiceTile extends StatelessWidget {
  const FontChoiceTile({super.key, this.onChoiceSelected});

  /// Optional synchronous selection handler for controlled widget tests or
  /// alternative storage. The regular app writes to Hive when omitted.
  final ValueChanged<AppFontChoice>? onChoiceSelected;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable:
          GStorage.settings.listenable(keys: [SettingsBoxKey.fontChoice]),
      builder: (context, _, __) => ListTile(
        leading: const Icon(Icons.font_download_outlined),
        title: const Text('界面字体'),
        subtitle: Text('当前：${GStorage.fontChoice.label}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showFontPicker(context),
      ),
    );
  }

  void _showFontPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final platform = Theme.of(sheetContext).platform;
        // Use an untouched theme for previews; otherwise the current
        // system-font theme would also affect the Material-default sample.
        final defaultPreviewStyle =
            ThemeData(platform: platform, useMaterial3: true)
                .textTheme
                .bodyLarge;
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('界面字体',
                      style: Theme.of(sheetContext).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  for (final choice in AppFontChoice.values)
                    RadioListTile<AppFontChoice>(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      value: choice,
                      groupValue: GStorage.fontChoice,
                      title: Text(choice.label),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(choice.description),
                          const SizedBox(height: 6),
                          Text(
                            '中文阅读效果 · 字形清晰，细节自然。123 ABC',
                            style: defaultPreviewStyle?.copyWith(
                              fontFamily: choice.familyForPlatform(platform) ??
                                  defaultPreviewStyle.fontFamily,
                              fontSize: 15,
                              height: 1.52,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                      onChanged: (value) {
                        if (value == null) return;
                        // Hive publishes the new value synchronously. Do not
                        // hold the sheet open while waiting for disk IO.
                        if (onChoiceSelected != null) {
                          onChoiceSelected!(value);
                        } else {
                          unawaited(GStorage.setFontChoice(value));
                        }
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                  const SizedBox(height: 12),
                  Text(
                    '提示：不同 Android 厂商对自定义系统字体的支持不同，'
                    '思源黑体由应用离线提供；系统字体受手机厂商影响。'
                    '此前手动选过系统字体的用户可在此切换到新字体。',
                    style: Theme.of(sheetContext).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
