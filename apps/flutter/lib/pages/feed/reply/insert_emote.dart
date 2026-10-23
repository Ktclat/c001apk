import 'package:flutter/widgets.dart';

const emoteMaxCodeUnits = 32768;

enum EmoteInsertionFailure { characterLimit, resourceLimit }

typedef EmoteInsertionResult = ({
  TextEditingValue value,
  EmoteInsertionFailure? failure,
});

/// Insert a whole catalog token without cutting an existing grapheme or token.
///
/// Flutter selections use UTF-16 offsets. Invalid selections append safely;
/// reversed selections replace the same range as forward selections. An offset
/// inside a grapheme moves a caret after it, or expands a range outwards, so
/// neither surrogate pairs nor combining/ZWJ sequences are left split.
/// Rejection returns the original value with an explicit failure, preserving
/// composing and selection. Callers must also leave publish state unchanged.
EmoteInsertionResult insertEmote(
  TextEditingValue value,
  String token, {
  int maxLength = 500,
}) {
  if (token.isEmpty) return (value: value, failure: null);
  if (token.length > emoteMaxCodeUnits) {
    return (value: value, failure: EmoteInsertionFailure.resourceLimit);
  }
  final text = value.text;
  final selection = value.selection;
  final valid = selection.isValid &&
      selection.start <= text.length &&
      selection.end <= text.length;
  var start = valid ? selection.start : text.length;
  var end = valid ? selection.end : text.length;
  if (text.length > emoteMaxCodeUnits) {
    // Do not scan abnormally large programmatic drafts. A complete, valid
    // selection may still recover one by replacing it with a bounded token.
    if (!valid || start != 0 || end != text.length) {
      return (value: value, failure: EmoteInsertionFailure.resourceLimit);
    }
  } else if ((start > 0 && start < text.length) ||
      (end > 0 && end < text.length)) {
    final collapsed = start == end;
    final range = CharacterRange.at(text, start, end);
    end = text.length - range.stringAfterLength;
    start = collapsed ? end : range.stringBeforeLength;
  }
  // The resource cap applies only to this action, not ordinary keyboard edits.
  if (text.length - (end - start) + token.length > emoteMaxCodeUnits) {
    return (value: value, failure: EmoteInsertionFailure.resourceLimit);
  }
  final updated = text.replaceRange(start, end, token);
  if (updated.characters.take(maxLength + 1).length > maxLength) {
    return (value: value, failure: EmoteInsertionFailure.characterLimit);
  }
  return (
    value: TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + token.length),
      composing: TextRange.empty,
    ),
    failure: null,
  );
}
