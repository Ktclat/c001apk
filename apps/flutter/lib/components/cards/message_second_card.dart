import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../pages/history/history_page.dart' show HistoryType;
import '../../pages/ffflist/ffflist_page.dart' show FFFListType;

Widget messageSeconfCard(bool isLogin, BuildContext context) {
  final shortcuts = [
    _MessageShortcut(
      '本地收藏',
      Icons.archive_outlined,
      () => Get.toNamed(
        '/history',
        arguments: {'type': HistoryType.Favorite},
      ),
    ),
    _MessageShortcut(
      '浏览历史',
      Icons.history,
      () => Get.toNamed(
        '/history',
        arguments: {'type': HistoryType.History},
      ),
    ),
    _MessageShortcut(
      '我的常去',
      Icons.my_location,
      isLogin
          ? () => Get.toNamed(
                '/ffflist',
                arguments: {'type': FFFListType.RECENT},
              )
          : () {},
    ),
    _MessageShortcut(
      '我的收藏',
      Icons.star_border,
      isLogin
          ? () => Get.toNamed(
                '/ffflist',
                arguments: {'type': FFFListType.COLLECTION},
              )
          : () {},
    ),
    _MessageShortcut(
      '我的赞',
      Icons.favorite_border,
      isLogin
          ? () => Get.toNamed(
                '/ffflist',
                arguments: {'type': FFFListType.LIKE},
              )
          : () {},
    ),
    _MessageShortcut(
      '我的回复',
      Icons.messenger_outline,
      isLogin
          ? () => Get.toNamed(
                '/ffflist',
                arguments: {'type': FFFListType.REPLY},
              )
          : () {},
    ),
  ];

  return Material(
    clipBehavior: Clip.hardEdge,
    borderRadius: const BorderRadius.all(Radius.circular(12)),
    color: Theme.of(context).colorScheme.onInverseSurface,
    child: LayoutBuilder(
      builder: (context, constraints) {
        var columns = 3;
        final textStyle = DefaultTextStyle.of(context).style;
        final painter = TextPainter(
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
          maxLines: 2,
        );
        try {
          // Prefer the existing three-column layout and at most two lines.
          // Measure the actual inherited font/scaler and available card width,
          // not device names or a guessed breakpoint. The one-column fallback
          // may wrap further rather than ever hiding a functional name.
          for (; columns > 1; columns--) {
            final cellWidth = (constraints.maxWidth - (columns - 1)) / columns;
            if (cellWidth < 48) continue;
            final labelsFit = shortcuts.every((shortcut) {
              painter.text = TextSpan(text: shortcut.title, style: textStyle);
              painter.layout(maxWidth: cellWidth - 16);
              return !painter.didExceedMaxLines;
            });
            if (labelsFit) break;
          }
        } finally {
          painter.dispose();
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var start = 0; start < shortcuts.length; start += columns)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var column = 0; column < columns; column++) ...[
                      if (column > 0)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: VerticalDivider(width: 1),
                        ),
                      Expanded(
                        child: _MessageShortcutTile(
                          shortcut: shortcuts[start + column],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _MessageShortcut {
  const _MessageShortcut(this.title, this.icon, this.onTap);

  final String title;
  final IconData icon;
  final VoidCallback onTap;
}

class _MessageShortcutTile extends StatelessWidget {
  const _MessageShortcutTile({required this.shortcut});

  final _MessageShortcut shortcut;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: shortcut.title,
      button: true,
      onTap: shortcut.onTap,
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('message-shortcut-${shortcut.title}'),
        onTap: shortcut.onTap,
        excludeFromSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  shortcut.icon,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                Text(
                  shortcut.title,
                  textAlign: TextAlign.center,
                  softWrap: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
