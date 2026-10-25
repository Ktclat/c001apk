import 'dart:async';
import 'dart:isolate';

import 'package:characters/characters.dart';

import 'markdown_content.dart';

/// One cancellable worker owned by one mounted detail. Never a shared cache.
/// Timeouts actually kill the isolate, rather than merely ignoring its Future.
class DetailParseJob<T> {
  DetailParseJob({this.budget = const Duration(seconds: 2)});
  final Duration budget;
  Isolate? _isolate;
  ReceivePort? _port;
  Timer? _timer;
  Completer<T?>? _pending;
  bool _closed = false;

  Future<T?> run(void Function((SendPort, Object)) entry, Object input) async {
    cancel();
    if (_closed) return null;
    final completer = Completer<T?>();
    final port = ReceivePort();
    _pending = completer;
    _port = port;
    void finish(T? result) {
      if (_pending != completer) return;
      cancel();
      if (!completer.isCompleted) completer.complete(result);
    }

    port.listen((dynamic message) {
      if (_pending != completer) return;
      if (message is T) {
        // Detach the completer before cleanup so cancellation does not replace
        // the successful result with null.
        _pending = null;
        cancel();
        if (!completer.isCompleted) completer.complete(message);
      } else {
        finish(null);
      }
    });
    _timer = Timer(budget, () => finish(null));
    try {
      final spawned = await Isolate.spawn(
        entry,
        (port.sendPort, input),
        onError: port.sendPort,
        onExit: port.sendPort,
        errorsAreFatal: true,
      );
      if (_pending != completer || _closed) {
        spawned.kill(priority: Isolate.immediate);
      } else {
        _isolate = spawned;
      }
    } on Exception {
      finish(null);
    }
    return completer.future;
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _port?.close();
    _port = null;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete(null);
  }

  void dispose() {
    _closed = true;
    cancel();
  }
}

void parseDetailBodies((SendPort, Object) request) {
  final sources = request.$2 as Map<String, String>;
  final total = sources.values.fold<int>(
    0,
    (sum, source) => sum + source.length,
  );
  final withinBudget = sources.length <= 128 && total <= 262144;
  request.$1.send(<String, MarkdownContent>{
    for (final entry in sources.entries)
      entry.key: withinBudget
          ? entry.key.endsWith(':title')
              ? MarkdownContent.legacy(entry.value)
              : entry.key.endsWith(':label') ||
                      entry.key.endsWith(':description')
                  ? MarkdownContent.literal(entry.value)
                  : MarkdownContent.parse(entry.value)
          : MarkdownContent.fallback(entry.value, '正文较长，已保留完整原文'),
  });
}

class SourcePage {
  const SourcePage(
    this.text,
    this.nextOffset, {
    this.notice,
    this.splitUntil = 0,
  });
  final String text;
  final int nextOffset;
  final String? notice;
  final int splitUntil;
}

/// Normal pages preserve graphemes. A pathological overlong single cluster is
/// split only at code-point boundaries with an explicit notice, never dropped.
/// Indexed range iteration avoids copying the entire remaining source.
void prepareSourcePage((SendPort, Object) request) {
  final (source, offset, splitUntil) = request.$2 as (String, int, int);
  void splitCluster(int clusterEnd) {
    var end = offset + 4000;
    if (end > clusterEnd) end = clusterEnd;
    if (end < source.length &&
        end > offset &&
        source.codeUnitAt(end - 1) >= 0xd800 &&
        source.codeUnitAt(end - 1) <= 0xdbff &&
        source.codeUnitAt(end) >= 0xdc00 &&
        source.codeUnitAt(end) <= 0xdfff) {
      end--;
    }
    request.$1.send(
      SourcePage(
        source.substring(offset, end),
        end,
        splitUntil: end < clusterEnd ? clusterEnd : 0,
        notice: '单个字形过长，暂按编码片段显示；原文内容未修改',
      ),
    );
  }

  if (splitUntil > offset) {
    splitCluster(splitUntil);
    return;
  }
  final out = StringBuffer();
  var units = 0;
  final range = CharacterRange.at(source, offset);
  while (range.moveNext()) {
    final end = source.length - range.stringAfterLength;
    final length = end - range.stringBeforeLength;
    if (length > 4000 && units == 0) {
      splitCluster(end);
      return;
    }
    if (units + length > 4000) break;
    out.write(range.current);
    units += length;
    if (units >= 4000) break;
  }
  request.$1.send(SourcePage(out.toString(), offset + units));
}
