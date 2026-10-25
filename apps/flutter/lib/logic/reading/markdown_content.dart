import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as md;

import '../../utils/emoji_util.dart';

/// Display-only, immutable output. No cache, networking, or source mutation.
enum DetailTextKind { plain, html, markdown, literal, fallback }

class MarkdownContent {
  const MarkdownContent._(this.source, this.kind,
      {this.html = '', this.emojiHtml = '', this.notice});
  final String source;
  final DetailTextKind kind;
  final String html;
  final String emojiHtml;
  final String? notice;
  bool get offersSource =>
      kind == DetailTextKind.markdown || kind == DetailTextKind.fallback;

  static MarkdownContent fallback(String source, String notice) =>
      MarkdownContent._(source, DetailTextKind.fallback, notice: notice);

  /// Run only in [DetailParseJob]'s disposable isolate, never during build.
  static MarkdownContent parse(String source) {
    final rejected = preflight(source);
    if (rejected != null) return fallback(source, rejected);
    try {
      final input = source
          .replaceAll('<!--break-->', '')
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n');
      final nodes = _parseNodes(input);
      final check = _inspect(nodes);
      if (check.$1 != null) return fallback(source, check.$1!);
      final hasHtml = _hasHtmlOutsideCode(nodes);
      if (hasHtml) {
        // Preserve pure legacy HTML capabilities, but mixed new Markdown/HTML
        // stays inert. Encoded tags are DOM text, never decoded then reparsed.
        final pureLegacy = !_hasMarkdownOutsideHtml(input);
        final legacy =
            _safeHtml(_legacyMarkup(input), legacyImages: pureLegacy);
        if (legacy == null) {
          return fallback(source, '包含暂不支持的 HTML，已保留完整原文');
        }
        return _prepared(source,
            pureLegacy ? DetailTextKind.html : DetailTextKind.markdown, legacy,
            decorateEmoji: pureLegacy);
      }
      if (!check.$2) {
        final plain = _safeHtml(_legacyMarkup(input), legacyImages: true);
        return plain == null
            ? fallback(source, '包含暂不支持的 HTML，已保留完整原文')
            : _prepared(source, DetailTextKind.plain, plain,
                decorateEmoji: true);
      }
      final rendered = _safeHtml(md.renderToHtml(nodes), generated: true);
      return rendered == null
          ? fallback(source, '包含暂不支持的格式，已保留完整原文')
          : _prepared(source, DetailTextKind.markdown, rendered);
    } on FormatException {
      return fallback(source, '正文格式无法解析，已保留完整原文');
    }
  }

  static List<md.Node> _parseNodes(String input) => md.Document(
        encodeHtml: true,
        withDefaultBlockSyntaxes: false,
        // Deliberately no InlineHtml, table, footnote or executable extension.
        extensionSet: md.ExtensionSet(
          const [
            md.EmptyBlockSyntax(),
            md.FencedCodeBlockSyntax(),
            md.UnorderedListWithCheckboxSyntax(),
            md.OrderedListWithCheckboxSyntax(),
            md.SetextHeaderSyntax(),
            md.HeaderSyntax(),
            md.CodeBlockSyntax(),
            md.BlockquoteSyntax(),
            md.HorizontalRuleSyntax(),
            md.UnorderedListSyntax(),
            md.OrderedListSyntax(),
            md.LinkReferenceDefinitionSyntax(),
            md.ParagraphSyntax(),
          ],
          [md.StrikethroughSyntax()],
        ),
      ).parse(input);

  /// Existing structured titles retain legacy HTML, not new Markdown syntax.
  static MarkdownContent legacy(String source) {
    final rejected = preflight(source);
    if (rejected != null) return fallback(source, rejected);
    final html = _safeHtml(
        _legacyMarkup(source
            .replaceAll('<!--break-->', '')
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n')),
        legacyImages: true);
    return html == null
        ? fallback(source, '包含暂不支持的 HTML，已保留完整原文')
        : _prepared(source, DetailTextKind.html, html, decorateEmoji: true);
  }

  /// Share titles/captions were literal Text, so entities/Markdown stay literal.
  static MarkdownContent literal(String source) {
    final rejected = preflight(source);
    if (rejected != null) return fallback(source, rejected);
    final html = const HtmlEscape(HtmlEscapeMode.element)
        .convert(source)
        .replaceAll('\r\n', '\n')
        .replaceAll('\n', '<br>');
    return _prepared(source, DetailTextKind.literal, html);
  }

  static MarkdownContent _prepared(
      String source, DetailTextKind kind, String html,
      {bool decorateEmoji = false}) {
    if (DetailRenderBudget.reason(html) != null) {
      return fallback(source, DetailRenderBudget.notice);
    }
    final decorated = decorateEmoji ? _decorateEmoji(html) : html;
    if (DetailRenderBudget.reason(decorated) != null) {
      return fallback(source, DetailRenderBudget.notice);
    }
    return MarkdownContent._(source, kind, html: html, emojiHtml: decorated);
  }

  // Only text nodes are decorated, after HTML sanitization. A serialized entity
  // stays a text node, so &lt;img&gt; cannot become a newly active image.
  static String _decorateEmoji(String value) {
    final fragment = html_parser.parseFragment(value);
    final pending = <dom.Node>[fragment];
    final pattern = RegExp(r'\[[^\]\r\n]{1,32}\]');
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      if (node is dom.Text) {
        final parts = <dom.Node>[];
        var offset = 0;
        for (final match in pattern.allMatches(node.data)) {
          final src = EmojiUtil.emojiMap[match[0]];
          if (src == null || src.isEmpty) continue;
          parts.add(dom.Text(node.data.substring(offset, match.start)));
          parts.add(dom.Element.tag('img')..attributes['src'] = src);
          offset = match.end;
        }
        if (parts.isNotEmpty) {
          parts.add(dom.Text(node.data.substring(offset)));
          final parent = node.parentNode!;
          parent.nodes.insertAll(parent.nodes.indexOf(node), parts);
          node.remove();
        }
      } else if (node is! dom.Element ||
          !const {'code', 'pre'}.contains(node.localName)) {
        pending.addAll(node.nodes);
      }
    }
    return fragment.outerHtml;
  }

  static bool _hasMarkdownOutsideHtml(String input) {
    final fragment = html_parser.parseFragment(input);
    // Preserve legacy HTML descendants and the existing simple **bold** rule.
    // Parse root text with neutral placeholders for elements so new Markdown
    // across inline HTML (e.g. *one <span>two</span> three*) is not missed.
    final outside = fragment.nodes
        .map((node) => node is dom.Text ? node.data : '\uFFFC')
        .join()
        .replaceAllMapped(RegExp(r'\*\*([^*<>\n]+)\*\*'), (match) => match[1]!);
    // DOM entity decoding can join short encoded pieces into a parser-hostile
    // token; reapply preflight to this exact second-parser input as well.
    if (preflight(outside) != null) return true;
    final check = _inspect(_parseNodes(outside));
    return check.$1 != null || check.$2;
  }

  static const maxSourceUnits = 65536;
  static const maxNodes = 2048;
  static const maxDepth = 24;

  /// Linear, BEFORE library recursion/regex/table allocation. Conservative
  /// limits intentionally also reject punctuation-heavy code/literal text.
  static String? preflight(String source) {
    const budget = '正文较长或结构复杂，已保留完整原文';
    if (source.length > maxSourceUnits) return budget;
    var lines = 0, lineUnits = 0, paragraphUnits = 0;
    var totalDelimiters = 0, lineDelimiters = 0, paragraphDelimiters = 0;
    var brackets = 0, quotes = 0, indent = 0;
    var leading = true, blank = true;
    var lineStart = 0, asciiToken = 0;
    for (var i = 0; i <= source.length; i++) {
      final c = i == source.length ? 10 : source.codeUnitAt(i);
      if ((c >= 65 && c <= 90) ||
          (c >= 97 && c <= 122) ||
          (c >= 48 && c <= 57)) {
        if (++asciiToken > 512) return budget;
      } else {
        asciiToken = 0;
      }
      if (c == 10 || c == 13) {
        final line = source.substring(lineStart, i);
        if (_containerDepth(line) > 16) return budget;
        // A table delimiter row is rejected before TableSyntax could expand
        // columns x rows. Tables are intentionally not registered above.
        if (line.contains('|') &&
            RegExp(r'^[ \t|:\-]+$').hasMatch(line) &&
            line.contains('-')) {
          return '表格暂不支持排版，已保留完整原文';
        }
        if (++lines > 1024) return budget;
        if (blank) {
          paragraphUnits = 0;
          paragraphDelimiters = 0;
        }
        if (c == 13 &&
            i + 1 < source.length &&
            source.codeUnitAt(i + 1) == 10) {
          i++;
        }
        lineStart = i + 1;
        lineUnits = 0;
        lineDelimiters = 0;
        quotes = 0;
        indent = 0;
        leading = true;
        blank = true;
        continue;
      }
      if (++lineUnits > 8192 || ++paragraphUnits > 16384) return budget;
      if (c != 32 && c != 9) blank = false;
      if (leading) {
        if (c == 32 || c == 9) {
          indent += c == 9 ? 4 : 1;
          if (indent > 48) return budget;
        } else if (c == 62) {
          if (++quotes > 16) return budget;
        } else {
          leading = false;
        }
      }
      if (c == 91 || c == 40) {
        if (++brackets > 16) return budget;
      } else if (c == 93 || c == 41) {
        if (brackets > 0) brackets--;
      }
      if (const {
        42,
        95,
        96,
        126,
        91,
        93,
        40,
        41,
        60,
        62,
        124,
        92,
      }.contains(c)) {
        if (++totalDelimiters > 4096 ||
            ++lineDelimiters > 128 ||
            ++paragraphDelimiters > 64) {
          return budget;
        }
      }
      // Unsupported extensions must not look like successfully rendered text.
      if (c == 91 && i + 1 < source.length && source.codeUnitAt(i + 1) == 94) {
        return '脚注暂不支持排版，已保留完整原文';
      }
    }
    return null;
  }

  static int _containerDepth(String line) {
    var position = 0, depth = 0;
    while (position < line.length) {
      while (position < line.length &&
          (line.codeUnitAt(position) == 32 || line.codeUnitAt(position) == 9)) {
        position++;
      }
      if (position == line.length) break;
      final start = position;
      final c = line.codeUnitAt(position);
      if (c == 62) {
        position++;
      } else if (c == 45 || c == 43 || c == 42) {
        position++;
        if (position == line.length ||
            !const {32, 9}.contains(line.codeUnitAt(position))) {
          break;
        }
      } else if (c >= 48 && c <= 57) {
        while (position < line.length &&
            position - start < 9 &&
            line.codeUnitAt(position) >= 48 &&
            line.codeUnitAt(position) <= 57) {
          position++;
        }
        if (position == line.length ||
            !const {46, 41}.contains(line.codeUnitAt(position))) {
          break;
        }
        position++;
        if (position == line.length ||
            !const {32, 9}.contains(line.codeUnitAt(position))) {
          break;
        }
      } else {
        break;
      }
      if (++depth > 16) return depth;
    }
    return depth;
  }

  static (String?, bool) _inspect(List<md.Node> nodes) {
    final pending = <(md.Node, int)>[for (final node in nodes) (node, 0)];
    var count = 0, listItems = 0;
    var markdown = false;
    while (pending.isNotEmpty) {
      final (node, depth) = pending.removeLast();
      if (++count > maxNodes || depth > maxDepth) {
        return ('正文结构复杂，已保留完整原文', false);
      }
      if (node is! md.Element) continue;
      if (const {
        'h1',
        'h2',
        'h3',
        'h4',
        'h5',
        'h6',
        'pre',
        'strong',
        'em',
        'del',
        'code',
        'img',
        'input',
        'blockquote',
        'hr',
      }.contains(node.tag)) {
        markdown = true;
      }
      if (node.tag == 'a') markdown = true;
      if (node.tag == 'li') listItems++;
      for (final child in node.children ?? <md.Node>[]) {
        pending.add((child, depth + 1));
      }
    }
    return (null, markdown || listItems >= 2);
  }

  // Match existing htmlText's display-only newline/simple-bold conventions,
  // then sanitize. Never feed this transformed text back into the model.
  static String _legacyMarkup(String value) => value
      .replaceAll(RegExp(r'\n(?:[ \t]*\n){2,}'), '\n\n')
      .replaceAllMapped(
        RegExp(r'\*\*([^*<>\n]+)\*\*'),
        (match) => '<strong>${match[1]}</strong>',
      )
      .replaceAll('\n', '<br/>');

  static bool _hasHtmlOutsideCode(List<md.Node> nodes) {
    final pending = <md.Node>[...nodes];
    final tag = RegExp(r'&lt;/?[a-zA-Z!]');
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      if (node is md.Text && tag.hasMatch(node.textContent)) return true;
      if (node is md.Element && node.tag != 'code' && node.tag != 'pre') {
        pending.addAll(node.children ?? const <md.Node>[]);
      }
    }
    return false;
  }

  static String? _safeHtml(String value,
      {bool generated = false, bool legacyImages = false}) {
    if (!generated &&
        '<'.allMatches(value).length > '>'.allMatches(value).length) {
      return null;
    }
    final fragment = html_parser.parseFragment(value);
    final pending = <(dom.Node, int, bool)>[(fragment, 0, false)];
    var count = 0;
    const allowed = {
      'p',
      'span',
      'div',
      'br',
      'a',
      'strong',
      'b',
      'em',
      'i',
      'u',
      's',
      'del',
      'code',
      'pre',
      'blockquote',
      'ul',
      'ol',
      'li',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'hr',
      'img',
      'input',
    };
    while (pending.isNotEmpty) {
      final (node, depth, inCode) = pending.removeLast();
      if (++count > maxNodes || depth > maxDepth) return null;
      if (node is dom.Comment) return null;
      if (node is dom.Element) {
        if (!allowed.contains(node.localName)) return null;
        if (node.localName == 'img') {
          if (legacyImages) {
            final src = node.attributes['src'] ?? '';
            final uri = Uri.tryParse(src);
            final remote = uri != null &&
                const {'http', 'https'}.contains(uri.scheme) &&
                allowsUrl(src);
            final local = EmojiUtil.emojiMap.values.contains(src) ||
                (src.length <= 128 &&
                    src.endsWith('icon') &&
                    !src.contains('/') &&
                    !src.contains('\\'));
            if (remote || local) {
              node.attributes.removeWhere((key, _) => key != 'src');
            } else {
              // Preserve non-fetching legacy source labels, never asset paths,
              // credentials, malformed schemes, event handlers or remote CSS.
              node.replaceWith(dom.Text(src));
            }
            continue;
          }
          // New Markdown/mixed HTML media is always a non-fetching placeholder.
          node.replaceWith(
            dom.Text(
              '图片未加载：${node.attributes['alt'] ?? ''}'
              ' (${node.attributes['src'] ?? ''})',
            ),
          );
          continue;
        }
        if (node.localName == 'input') {
          if (!generated || node.attributes['type'] != 'checkbox') return null;
          node.replaceWith(
            // ASCII markers remain readable with every supported app font;
            // the bundled CJK font has no U+2610/U+2611 checkbox glyphs.
            dom.Text(node.attributes.containsKey('checked') ? '[x] ' : '[ ] '),
          );
          continue;
        }
        if (node.localName == 'a' &&
            !allowsUrl(node.attributes['href'] ?? '')) {
          // Keep visible label; never send unsafe destinations to the router.
          node.attributes.remove('href');
        }
        node.attributes.removeWhere(
          (key, _) => !const {'href', 'start', 'title'}.contains(key),
        );
      }
      if (generated &&
          node is dom.Text &&
          !inCode &&
          node.data.contains('\n')) {
        final parent = node.parentNode;
        if (parent is dom.Element &&
            const {
              'p',
              'li',
              'strong',
              'em',
              'del',
              'a',
            }.contains(parent.localName)) {
          final parts = node.data.split('\n');
          final index = parent.nodes.indexOf(node);
          parent.nodes.insertAll(index, [
            for (var i = 0; i < parts.length; i++) ...[
              if (i > 0) dom.Element.tag('br'),
              dom.Text(parts[i]),
            ],
          ]);
          node.remove();
        }
      }
      final code = inCode ||
          (node is dom.Element &&
              const {'code', 'pre'}.contains(node.localName));
      for (final child in node.nodes) {
        pending.add((child, depth + 1, code));
      }
    }
    final output = fragment.outerHtml;
    return output.length <= 131072 ? output : null;
  }

  static bool allowsUrl(String value) {
    if (value.isEmpty ||
        value.length > 2048 ||
        RegExp(r'[\x00-\x20\x7f\\]').hasMatch(value) ||
        RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(value)) {
      return false;
    }
    final uri = Uri.tryParse(value);
    if (uri == null || uri.userInfo.isNotEmpty || value.startsWith('//')) {
      return false;
    }
    try {
      final decoded = Uri.decodeComponent(uri.path);
      Uri.decodeComponent(uri.query);
      if (RegExp(r'[\x00-\x1f\x7f\\]').hasMatch(decoded)) return false;
    } on FormatException {
      return false;
    }
    if (value.startsWith('#')) return false; // Anchor navigation is deferred.
    if (!uri.hasScheme) return value.startsWith('/');
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return uri.host.isNotEmpty;
    }
    if (uri.scheme != 'coolmarket' || uri.hasPort) return false;
    const hosts = {
      'coolapk.com',
      'www.coolapk.com',
      'm.coolapk.com',
      'com.coolapk.market',
    };
    final path = hosts.contains(uri.host)
        ? uri.pathSegments
        : [uri.host, ...uri.pathSegments];
    return path.length >= 2 &&
        const {
          'feed',
          'event',
          'u',
          'apk',
          'game',
          't',
          'product',
        }.contains(path.first) &&
        path[1].isNotEmpty;
  }
}

/// Final eager-widget layout budget, independent of the larger parser budget.
/// Checked AFTER newline, sanitizer and optional local-emoji expansion, and
/// rechecked at FeedText's rendering boundary. Exceeding it keeps exact source.
class DetailRenderBudget {
  static const maxHtmlUnits = 16000;
  static const maxTextUnits = 4000;
  static const maxBlockUnits = 2000;
  static const maxCodeUnits = 2000;
  static const maxNodes = 128;
  static const maxDepth = 12;
  static const maxImages = 24;
  static const notice = '正文排版超出显示上限，已保留完整原文';
  static String? reason(String html) {
    if (html.length > maxHtmlUnits) return notice;
    final root = html_parser.parseFragment(html);
    final pending = <(dom.Node, int)>[(root, 0)];
    var count = 0, text = 0, images = 0;
    const blocks = {
      'p',
      'div',
      'blockquote',
      'li',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6'
    };
    while (pending.isNotEmpty) {
      final (node, depth) = pending.removeLast();
      if (++count > maxNodes || depth > maxDepth) return notice;
      if (node is dom.Text) {
        text += node.data.length;
        if (text > maxTextUnits || node.data.length > maxBlockUnits) {
          return notice;
        }
      }
      if (node is dom.Element) {
        if (node.localName == 'img' && ++images > maxImages) return notice;
        if (const {'pre', 'code'}.contains(node.localName) &&
            node.text.length > maxCodeUnits) {
          return notice;
        }
        if (blocks.contains(node.localName) &&
            node.text.length > maxBlockUnits) {
          return notice;
        }
      }
      // Bound root/inline runs too, including text split by links/emphasis.
      var inlineUnits = 0;
      for (final child in node.nodes) {
        if (child is dom.Element &&
            (blocks.contains(child.localName) ||
                const {'pre', 'ul', 'ol', 'hr'}.contains(child.localName))) {
          inlineUnits = 0;
        } else {
          inlineUnits += child.text?.length ?? 0;
          if (inlineUnits > maxBlockUnits) return notice;
        }
        pending.add((child, depth + 1));
      }
    }
    return null;
  }
}
