import 'dart:isolate';

import 'package:c001apk_flutter/logic/reading/detail_body_snapshot.dart';
import 'package:c001apk_flutter/logic/reading/detail_parse_job.dart';
import 'package:c001apk_flutter/logic/reading/markdown_content.dart';
import 'package:flutter_test/flutter_test.dart';

void _busy((SendPort, Object) _) {
  while (true) {}
}

void _answer((SendPort, Object) request) {
  request.$1.send('ready');
}

void main() {
  test(
    'snapshot identity includes owner generation feed and exact original body',
    () {
      DetailBodySnapshot make({
        String owner = 'a',
        int generation = 1,
        String feed = '123',
        String original = 'line\r\n',
        String text = '# 文',
      }) =>
          DetailBodySnapshot(
            account: owner,
            generation: generation,
            feedId: feed,
            originalBody: original,
            sources: {'body': text},
          );
      final a = make();
      expect(a.sameBody(make()), isTrue);
      expect(a.sameBody(make(owner: 'b')), isFalse);
      expect(a.sameBody(make(generation: 2)), isFalse);
      expect(a.sameBody(make(feed: '124')), isFalse);
      expect(a.sameBody(make(original: 'line\n')), isFalse);
      expect(a.sameBody(make(text: '# changed')), isFalse);
      expect(() => a.sources['body'] = 'changed', throwsUnsupportedError);
      expect(
        a.prepared({'body': MarkdownContent.parse('# 文')}).sameBody(a),
        isTrue,
      );
      final structured = DetailBodySnapshot(
        account: 'a',
        generation: 1,
        feedId: '123',
        originalBody: '[  ]',
        sources: const {},
        rawFields: const {'title': null, 'message_raw_output': '[  ]'},
      );
      expect(structured.rawFields['message_raw_output'], '[  ]');
      expect(
        () => structured.rawFields['title'] = 'changed',
        throwsUnsupportedError,
      );
    },
  );

  test(
    'cancel kills a worker and stale completion cannot replace the next result',
    () async {
      final job = DetailParseJob<String>();
      addTearDown(job.dispose);
      final first = job.run(_busy, 'old-account');
      job.cancel();
      final second = job.run(_answer, 'new-account');
      expect(await first, isNull);
      expect(await second, 'ready');
    },
  );

  test(
    'timeout actually kills non-cooperative parser, and disposal is final',
    () async {
      final job = DetailParseJob<String>(
        budget: const Duration(milliseconds: 50),
      );
      expect(await job.run(_busy, 'test'), isNull);
      expect(await job.run(_answer, 'test'), 'ready');
      job.dispose();
      expect(await job.run(_answer, 'test'), isNull);
    },
  );

  test(
    'worker parses immutable source and enforces aggregate body budget',
    () async {
      final job = DetailParseJob<Map<String, MarkdownContent>>();
      addTearDown(job.dispose);
      final results = await job.run(parseDetailBodies, {
        'body': '# 标题\r\n<!--break-->',
      });
      expect(results!['body']!.kind, DetailTextKind.markdown);
      expect(results['body']!.source, '# 标题\r\n<!--break-->');
      final over = await job.run(parseDetailBodies, {
        for (var i = 0; i < 129; i++) '$i': '# 标题',
      });
      expect(
        over!.values.every((value) => value.kind == DetailTextKind.fallback),
        isTrue,
      );
    },
  );

  test(
    'raw pages reassemble exact source without cutting extended graphemes',
    () async {
      final source = '${'甲' * 3999}👩🏽‍💻é🇨🇳\r\n<!--break--> ${'乙' * 5000}';
      final job = DetailParseJob<SourcePage>();
      addTearDown(job.dispose);
      final pieces = <String>[];
      var offset = 0;
      var splitUntil = 0;
      while (offset < source.length) {
        final page = await job.run(prepareSourcePage, (
          source,
          offset,
          splitUntil,
        ));
        expect(page, isNotNull);
        expect(page!.nextOffset, greaterThan(offset));
        pieces.add(page.text);
        offset = page.nextOffset;
        splitUntil = page.splitUntil;
      }
      expect(pieces.first, '甲' * 3999);
      expect(pieces[1], startsWith('👩🏽‍💻é🇨🇳\r\n'));
      expect(pieces.join(), source);
    },
  );
  test(
      'one pathological grapheme is bounded, explicitly labeled and never dropped',
      () async {
    final source = 'a${'\u0301' * 100000}👩🏽‍💻结束';
    final job = DetailParseJob<SourcePage>();
    addTearDown(job.dispose);
    final pieces = <String>[];
    var offset = 0, splitUntil = 0;
    var sawNotice = false;
    while (offset < source.length) {
      final page = await job.run(prepareSourcePage, (
        source,
        offset,
        splitUntil,
      ));
      expect(page, isNotNull);
      expect(page!.text.length, lessThanOrEqualTo(4000));
      expect(page.nextOffset, greaterThan(offset));
      sawNotice = sawNotice || page.notice != null;
      pieces.add(page.text);
      offset = page.nextOffset;
      splitUntil = page.splitUntil;
    }
    expect(sawNotice, isTrue);
    expect(pieces.join(), source);
  });
  test(
      'raw paging preserves lone surrogates and pathological cluster code units',
      () async {
    for (final source in [
      '${'中' * 3999}\ud800Z\udfff${'尾' * 4001}',
      '\ud800a${'\u0301' * 10000}\udfff结束',
      '${'中' * 3999}😀${'尾' * 4001}\ud800',
    ]) {
      final job = DetailParseJob<SourcePage>();
      final pieces = <String>[];
      var offset = 0, splitUntil = 0;
      try {
        while (offset < source.length) {
          final page =
              await job.run(prepareSourcePage, (source, offset, splitUntil));
          expect(page, isNotNull);
          expect(page!.text.length, lessThanOrEqualTo(4000));
          expect(page.nextOffset, greaterThan(offset));
          pieces.add(page.text);
          offset = page.nextOffset;
          splitUntil = page.splitUntil;
        }
        expect(pieces.join().codeUnits, orderedEquals(source.codeUnits));
      } finally {
        job.dispose();
      }
    }
  });
}
