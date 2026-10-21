import 'package:flutter/material.dart';

/// Post typography is separate from the global system/UI font and text scale.
/// Stable integer values are persisted in the user's Hive settings box.
enum ReadingPreset {
  comfortable,
  original;

  static ReadingPreset fromStorage(Object? value) =>
      value == ReadingPreset.original.index
          ? ReadingPreset.original
          : ReadingPreset.comfortable;

  String get label => switch (this) {
        ReadingPreset.comfortable => '舒适阅读（推荐）',
        ReadingPreset.original => '原版排版',
      };

  String get description => switch (this) {
        ReadingPreset.comfortable => '正文更轻巧，标题不过度加粗',
        ReadingPreset.original => '还原上游的 16sp 正文和粗体标题',
      };

  double get bodySize => this == ReadingPreset.comfortable ? 15 : 16;
  double get bodyHeight => this == ReadingPreset.comfortable ? 1.42 : 1.5;
  double get titleSize => 16;
  double get titleHeight => this == ReadingPreset.comfortable ? 1.38 : 1.5;
  FontWeight get titleWeight =>
      this == ReadingPreset.comfortable ? FontWeight.w500 : FontWeight.bold;
}
