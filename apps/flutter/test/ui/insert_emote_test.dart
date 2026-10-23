import 'package:c001apk_flutter/pages/feed/reply/insert_emote.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TextEditingValue value(String text, int base, int extent,
          {TextRange composing = TextRange.empty}) =>
      TextEditingValue(
          text: text,
          selection: TextSelection(baseOffset: base, extentOffset: extent),
          composing: composing);

  for (final selection in [(1, 3), (3, 1)]) {
    test('replaces Chinese selection $selection and clears composing', () {
      final result = insertEmote(
              value('甲乙丙丁', selection.$1, selection.$2,
                  composing: const TextRange(start: 0, end: 4)),
              '[哈哈哈]')
          .value;
      expect(result.text, '甲[哈哈哈]丁');
      expect(result.selection, const TextSelection.collapsed(offset: 6));
      expect(result.composing, TextRange.empty);
    });
  }
  for (final selection in [(-1, -1), (-1, 2), (2, -1), (0, 9), (9, 0)]) {
    test('invalid selection $selection appends without throwing', () {
      final result =
          insertEmote(value('中文', selection.$1, selection.$2), '[强]').value;
      expect(result.text, '中文[强]');
      expect(result.selection, const TextSelection.collapsed(offset: 5));
    });
  }
  for (final offset in [0, 1, 2]) {
    test('collapsed caret $offset keeps both neighbours', () {
      final result = insertEmote(value('中文', offset, offset), '[强]').value;
      expect(result.text, '中文'.replaceRange(offset, offset, '[强]'));
      expect(result.selection.baseOffset, offset + 3);
    });
  }
  for (final grapheme in ['😀', 'e\u0301', '👩🏽‍💻', '🇨🇳']) {
    test('caret inside $grapheme advances without deleting', () {
      final result = insertEmote(value('甲$grapheme乙', 2, 2), '[强]').value;
      expect(result.text, '甲$grapheme[强]乙');
      expect(result.selection.baseOffset, 1 + grapheme.length + 3);
    });
    test('partial reversed range includes whole $grapheme', () {
      final result = insertEmote(value('甲$grapheme乙', 2, 1), '[强]').value;
      expect(result.text, '甲[强]乙');
      expect(result.selection.baseOffset, 4);
    });
  }
  test('repeated insertion follows the new collapsed caret', () {
    final first = insertEmote(value('甲乙', 1, 1), '[强]').value;
    final second = insertEmote(first, '[哈哈哈]').value;
    expect(second.text, '甲[强][哈哈哈]乙');
    expect(second.selection.baseOffset, 9);
  });
  test('500 limit rejects a whole token without changing the input value', () {
    final old = value('中' * 498, 100, 100,
        composing: const TextRange(start: 0, end: 1));
    expect(
        insertEmote(old, '[强]').failure, EmoteInsertionFailure.characterLimit);
    expect(old.text, '中' * 498);
    expect(old.selection, const TextSelection.collapsed(offset: 100));
    expect(old.composing, const TextRange(start: 0, end: 1));
    final exact = insertEmote(value('中' * 497, 497, 497), '[强]').value;
    expect(exact.text.characters.length, 500);
    expect(exact.text.endsWith('[强]'), isTrue);
  });
  test('existing over-limit draft is retained unless replacement fits', () {
    final old = value('中' * 510, 510, 510);
    expect(
        insertEmote(old, '[强]').failure, EmoteInsertionFailure.characterLimit);
    expect(old.text.characters.length, 510);
    final result = insertEmote(value(old.text, 0, 20), '[强]').value;
    expect(result.text.characters.length, 493);
  });
  test('replacement at limit frees only the selected range', () {
    final result = insertEmote(value('中' * 500, 20, 25), '[哈哈哈]').value;
    expect(result.text.characters.length, 500);
    expect(result.text.substring(20, 25), '[哈哈哈]');
  });
  test('graphemes, not UTF-16 length, determine the limit', () {
    final result = insertEmote(value('👩🏽‍💻' * 497, 0, 0), '[强]').value;
    expect(result.text.characters.length, 500);
    expect(result.text.startsWith('[强]👩🏽‍💻'), isTrue);
  });
  test('very long programmatic drafts reject cheaply but can be replaced', () {
    final text = '中' * 100000;
    expect(insertEmote(value(text, -1, -1), '[强]').failure,
        EmoteInsertionFailure.resourceLimit);
    expect(insertEmote(value(text, 0, 0), '[强]').failure,
        EmoteInsertionFailure.resourceLimit);
    expect(insertEmote(value(text, text.length, 0), '[强]').value.text, '[强]');
  });
  test('resource limit is explicit and permits only full-selection recovery',
      () {
    final text = '中' * 32769;
    for (final offsets in [(0, text.length), (text.length, 0)]) {
      final result = insertEmote(value(text, offsets.$1, offsets.$2), '[强]');
      expect(result.failure, isNull);
      expect(result.value.text, '[强]');
    }
    final partial = value(text, 1, text.length);
    final rejected = insertEmote(partial, '[强]');
    expect(rejected.failure, EmoteInsertionFailure.resourceLimit);
    expect(identical(rejected.value, partial), isTrue);
    expect(insertEmote(value('原稿', 0, 2), '中' * 32769).failure,
        EmoteInsertionFailure.resourceLimit);
    final combining = 'e${'\u0301' * 32765}';
    expect(
        insertEmote(
                value(combining, combining.length, combining.length), '[哈哈哈]')
            .failure,
        EmoteInsertionFailure.resourceLimit);
  });
  test('empty token leaves the value intact', () {
    final old = value('中文', 0, 1, composing: const TextRange(start: 0, end: 1));
    expect(identical(insertEmote(old, '').value, old), isTrue);
  });
}
