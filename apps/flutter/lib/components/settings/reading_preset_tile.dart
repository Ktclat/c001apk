import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../utils/reading_preset.dart';
import '../../utils/storage_util.dart';

class ReadingPresetTile extends StatelessWidget {
  const ReadingPresetTile({super.key, this.onSelected});

  /// Overrides storage in widget tests; production keeps the local preference.
  final ValueChanged<ReadingPreset>? onSelected;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: GStorage.settings
            .listenable(keys: [SettingsBoxKey.readingPreset]),
        builder: (context, _, __) => ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('正文排版'),
          subtitle: Text('当前：' + GStorage.readingPreset.label),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showPicker(context),
        ),
      );

  void _showPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('正文排版',
                  style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 8),
              for (final preset in ReadingPreset.values)
                RadioListTile<ReadingPreset>(
                  value: preset,
                  groupValue: GStorage.readingPreset,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(preset.label),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(preset.description),
                      const SizedBox(height: 6),
                      Text(
                        '九寨沟的景色，不需要滤镜也很美。',
                        style: TextStyle(
                          fontFamily: GStorage.fontChoice.familyForPlatform(
                              Theme.of(sheetContext).platform),
                          fontSize: preset.bodySize,
                          height: preset.bodyHeight,
                          fontWeight: FontWeight.w400,
                          color: Theme.of(sheetContext).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  onChanged: (value) {
                    if (value == null) return;
                    if (onSelected != null) {
                      onSelected!(value);
                    } else {
                      unawaited(GStorage.setReadingPreset(value));
                    }
                    Navigator.of(sheetContext).pop();
                  },
                ),
              const SizedBox(height: 8),
              Text('仅调整帖子与文章、主要评论的排版。'
                  '界面字体和系统字号仍在上方独立设置。',
                  style: Theme.of(sheetContext).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
