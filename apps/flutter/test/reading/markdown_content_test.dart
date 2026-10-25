import 'package:c001apk_flutter/logic/reading/markdown_content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'bounded detail Markdown has semantic structure without changing source',
    () {
      const source = '# 中文标题\r\n\r\n**重点** 和 *强调* ~~过时~~ `代码`\r\n\r\n'
          '> 引用\r\n\r\n- 第一项\r\n- 第二项\r\n\r\n- [x] 已完成\r\n\r\n'
          '```dart\r\n<b>不是 HTML</b>\r\n```\r\n<!--break-->';
      final result = MarkdownContent.parse(source);
      expect(result.source, source);
      expect(result.kind, DetailTextKind.markdown);
      for (final tag in [
        'h1',
        'strong',
        'em',
        'del',
        'code',
        'blockquote',
        'ul',
      ]) {
        expect(result.html, contains('<$tag'));
      }
      expect(result.html, contains('[x]'));
      expect(MarkdownContent.parse('- [ ] 待完成').html, contains('[ ]'));
      expect(result.html, contains('&lt;b&gt;'));
      expect(result.html, isNot(contains('<!--break-->')));
    },
  );

  test('ordinary topic, underscore name and lone list are not opted in', () {
    for (final source in ['#一加13#', 'POCO_X3_GT', '- 一个普通条目', '普通正文\n下一行']) {
      expect(
        MarkdownContent.parse(source).kind,
        DetailTextKind.plain,
        reason: source,
      );
    }
  });

  test('safe legacy HTML keeps structure; mixed markup is not flattened', () {
    const source = '<p>原有 <strong>粗体</strong><br>下一行 '
        '<a class="feed-link-uname" href="/u/12">用户</a> **原始 Markdown**</p>';
    final result = MarkdownContent.parse(source);
    expect(result.kind, DetailTextKind.html);
    expect(result.html, contains('<strong>粗体</strong>'));
    expect(result.html, contains('href="/u/12"'));
    expect(result.html, contains('<strong>原始 Markdown</strong>'));
    expect(result.source, source);
  });

  test(
    'unsupported HTML and comments fall back to exact non-executing source',
    () {
      for (final source in [
        '<script>alert(1)</script>',
        '# 标题\n\n<iframe src="https://x.test"></iframe>',
        '<!-- not break -->\n# 标题',
      ]) {
        final result = MarkdownContent.parse(source);
        expect(result.kind, DetailTextKind.fallback, reason: source);
        expect(result.html, isEmpty);
        expect(result.source, source);
        expect(result.notice, isNotEmpty);
      }
    },
  );

  test(
      'images are inert placeholders, including official-looking/HTTP destinations',
      () {
    for (final url in [
      'https://image.coolapk.com/a.jpg',
      'http://image.coolapk.com/a.jpg',
      'https://127.0.0.1/private',
      'data:image/svg+xml,test',
      'https://evil.test/a.jpg',
    ]) {
      final result = MarkdownContent.parse('![中文替代文本]($url)');
      expect(result.kind, DetailTextKind.markdown);
      expect(result.html, contains('图片未加载'));
      expect(result.html, contains('中文替代文本'));
      expect(result.html, isNot(contains('<img')));
    }
    for (final source in [
      '# 新 Markdown\n\n<img src="https://evil.test/a.jpg" onerror="x">',
      '# 新 Markdown\n\n<img src="https://evil.test/x"\n>',
      '<img src="https://evil.test/x"',
    ]) {
      expect(MarkdownContent.parse(source).html, isNot(contains('<img')));
    }
  });

  test(
    'link routing only sees vetted URLs and never event handlers or styling',
    () {
      for (final url in [
        '/feed/123',
        '/u/12',
        'coolmarket://feed/123',
        'coolmarket://www.coolapk.com/feed/123',
        'https://www.coolapk.com/feed/123',
        'https://example.com',
      ]) {
        expect(MarkdownContent.allowsUrl(url), isTrue, reason: url);
      }
      for (final url in [
        'javascript:alert(1)',
        'data:text/html,x',
        'file:///tmp/x',
        '//evil.test',
        'https://user:pass@example.com',
        '/feed/%00',
        '/feed/%ZZ',
        'https://good.test\\@evil.test',
        '#heading',
        'mailto:x@example.com',
      ]) {
        expect(MarkdownContent.allowsUrl(url), isFalse, reason: url);
      }
      final html = MarkdownContent.parse(
        '<a href="javascript:alert(1)" onclick="x" style="x">原文</a>',
      ).html;
      expect(html, contains('原文'));
      expect(html, isNot(contains('href')));
      expect(html, isNot(contains('onclick')));
      expect(html, isNot(contains('style')));
    },
  );

  test('tables are rejected before table allocation, with full source retained',
      () {
    final source = '${List.filled(2000, 'a').join('|')}\n'
        '${List.filled(2000, '-').join('|')}\n${List.filled(10000, 'a').join('\n')}';
    expect(MarkdownContent.preflight(source), isNotNull);
    // Only the preflight runs on this adversarial vector, never the library.
    const small = '| 名称 | 数值 |\n| --- | --- |\n| 中文 | 123 |';
    final result = MarkdownContent.parse(small);
    expect(result.kind, DetailTextKind.fallback);
    expect(result.source, small);
  });

  test(
    'linear preflight rejects recursion before library AST postprocessing',
    () {
      final vectors = <String>[
        '${List.filled(10000, '*x\n').join()}end',
        '${List.filled(500, '*x\r\n').join()}end',
        '${List.filled(4000, '- ').join()}tail',
        '${List.filled(4000, '> ').join()}tail',
        '${List.filled(200, '[').join()}x',
        '${List.filled(5000, '\n').join()}end',
        'a' * 65537,
        'z' * 8192,
        ' ' * 100 + '- indented',
      ];
      for (final source in vectors) {
        expect(MarkdownContent.preflight(source), isNotNull);
        final result = MarkdownContent.parse(source);
        expect(result.kind, DetailTextKind.fallback);
        expect(result.source, source);
      }
    },
  );

  test(
    'code HTML stays literal; long supported source and Unicode stay exact',
    () {
      const source = '```html\n<script>你好👩🏽‍💻é🇨🇳</script>\n```';
      final result = MarkdownContent.parse(source);
      expect(result.kind, DetailTextKind.markdown);
      expect(result.html, isNot(contains('<script>')));
      expect(result.source, source);
      final long = List.filled(100, '**中文段落** 👩🏽‍💻\n\n').join();
      expect(MarkdownContent.parse(long).kind, DetailTextKind.fallback);
      expect(MarkdownContent.parse(long).source, long);
      expect(MarkdownContent.parse(long).notice, DetailRenderBudget.notice);
    },
  );
  test(
    'safe legacy HTML retains existing newlines and simple bold semantics',
    () {
      const source = '第一行\n<a href="/u/12">用户</a>\n最后一行 **重点**';
      final result = MarkdownContent.parse(source);
      expect(result.kind, DetailTextKind.html);
      expect(result.html, contains('第一行<br>'));
      expect(result.html, contains('</a><br>最后一行'));
      expect(result.html, contains('<strong>重点</strong>'));
      expect(result.source, source);
    },
  );
  test('legacy simple bold keeps media while new mixed Markdown never fetches',
      () {
    const image = '<img src="https://fixture.invalid/legacy.gif">';
    final legacy = MarkdownContent.parse('$image 旧正文 **重点**');
    expect(legacy.kind, DetailTextKind.html);
    expect(legacy.html, contains('<img'));
    expect(legacy.html, contains('<strong>重点</strong>'));
    for (final markup in [
      '_强调_',
      '*强调*',
      '~~旧内容~~',
      '__重点__',
      '# 标题',
      '标题\n===',
      '[链接](/u/12)',
      '*第一 <span>第二</span> 第三*',
      '第一\n\n- 一\n- 二',
    ]) {
      final result = MarkdownContent.parse('$markup\n\n$image');
      expect(result.kind, DetailTextKind.markdown, reason: markup);
      expect(result.html, isNot(contains('<img')), reason: markup);
      expect(result.html, contains('图片未加载'), reason: markup);
    }
  });

  test('structured labels remain literal and bounded without emoji expansion',
      () {
    const source = '<b>**标签**</b> &amp; [微笑]';
    final literal = MarkdownContent.literal(source);
    expect(literal.kind, DetailTextKind.literal);
    expect(literal.source, source);
    expect(literal.html, contains('&lt;b&gt;**标签**&lt;/b&gt; &amp;amp;'));
    expect(literal.emojiHtml, literal.html);
    expect(MarkdownContent.literal('中' * 2001).kind, DetailTextKind.fallback);
  });
  test('decoded legacy root text is preflighted before mixed Markdown parsing',
      () {
    final source =
        '${'&#65;' * 513}<img src="https://fixture.invalid/legacy.gif">';
    expect(MarkdownContent.preflight(source), isNull);
    final content = MarkdownContent.parse(source);
    expect(content.kind, DetailTextKind.markdown);
    expect(content.html, isNot(contains('<img')));
    expect(content.source, source);
  });
}
