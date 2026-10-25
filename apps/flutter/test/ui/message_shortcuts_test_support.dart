import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const messageShortcutTitles = [
  '本地收藏',
  '浏览历史',
  '我的常去',
  '我的收藏',
  '我的赞',
  '我的回复',
];

Finder messageShortcut(String title) =>
    find.byKey(ValueKey('message-shortcut-$title'));

void expectMessageShortcutLayout(WidgetTester tester, String title) {
  final target = messageShortcut(title);
  expect(target, findsOneWidget);
  final targetRect = tester.getRect(target);
  expect(targetRect.width, greaterThanOrEqualTo(48));
  expect(targetRect.height, greaterThanOrEqualTo(48));
  final text = find.descendant(of: target, matching: find.text(title));
  final icon = find.descendant(of: target, matching: find.byType(Icon));
  expect(
      tester.getRect(icon).bottom, lessThanOrEqualTo(tester.getRect(text).top));
  expect(tester.getRect(icon).center.dx,
      closeTo(tester.getRect(text).center.dx, 0.01));
  final widget = tester.widget<Text>(text);
  expect(widget.maxLines, isNull);
  expect(widget.overflow, isNot(TextOverflow.ellipsis));
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: text, matching: find.byType(RichText)));
  expect(paragraph.didExceedMaxLines, isFalse);
  expect(paragraph.text.toPlainText(), title);
  // Check every glyph, not merely the unabridged Text widget string. Font
  // ascent can extend above the paragraph's line-height box without clipping;
  // the tile padding must contain those bounds inside the card's actual clip.
  for (var i = 0; i < title.length; i++) {
    final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1));
    expect(boxes, isNotEmpty, reason: '$title: glyph $i must be laid out');
    for (final box in boxes) {
      expect(box.left, greaterThanOrEqualTo(-0.01));
      expect(box.right, lessThanOrEqualTo(paragraph.size.width + 0.01));
      final globalBox =
          box.toRect().shift(paragraph.localToGlobal(Offset.zero));
      expect(globalBox.left, greaterThanOrEqualTo(targetRect.left));
      expect(globalBox.right, lessThanOrEqualTo(targetRect.right));
      expect(globalBox.top, greaterThanOrEqualTo(targetRect.top));
      expect(globalBox.bottom, lessThanOrEqualTo(targetRect.bottom));
    }
  }
  final semantics = tester
      .getSemantics(find.bySemanticsLabel(RegExp('^$title\$')))
      .getSemanticsData();
  expect(semantics.label, title);
  expect(semantics.flagsCollection.isButton, isTrue);
  expect(semantics.hasAction(ui.SemanticsAction.tap), isTrue);
}
