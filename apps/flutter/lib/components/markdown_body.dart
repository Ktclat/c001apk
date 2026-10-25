import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../logic/reading/detail_parse_job.dart';
import '../logic/reading/detail_body_snapshot.dart';
import '../logic/reading/markdown_content.dart';
import '../utils/storage_util.dart';
import '../utils/utils.dart';
import 'html_text.dart';

TextStyle detailBodyStyle(BuildContext context, HtmlTextRole role) {
  final reading = GStorage.readingPreset;
  return TextStyle(
    fontFamily: GStorage.fontChoice.familyForPlatform(defaultTargetPlatform),
    fontFamilyFallback: const ['sans-serif'],
    locale: const Locale('zh', 'CN'),
    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .92),
    letterSpacing: 0,
    fontSize: role == HtmlTextRole.articleBody
        ? reading.articleBodySize
        : reading.bodySize,
    height: reading.bodyHeight,
    fontWeight: FontWeight.w400,
  );
}

/// Detail-only: comment, chat, forward cards and feed previews are unchanged.
class FeedText extends StatefulWidget {
  const FeedText({
    super.key,
    required this.source,
    this.content,
    this.forcePlain = false,
    this.role = HtmlTextRole.feedBody,
    this.sourcePosition,
    this.isCurrent,
    this.onPageNavigation,
    this.textStyle,
    this.textAlign,
  });
  final String source;
  final MarkdownContent? content;
  final bool forcePlain;
  final HtmlTextRole role;
  final RawSourcePosition? sourcePosition;
  final TextStyle? textStyle;
  final TextAlign? textAlign;
  final bool Function()? isCurrent;
  final VoidCallback? onPageNavigation;
  @override
  State<FeedText> createState() => _FeedTextState();
}

class _FeedTextState extends State<FeedText> {
  RawSourcePosition _rawPosition = RawSourcePosition();
  @override
  void didUpdateWidget(FeedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) _rawPosition = RawSourcePosition();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isCurrent?.call() == false) return const SizedBox.shrink();
    final source = widget.source;
    final isCurrent = widget.isCurrent;
    final forcePlain = widget.forcePlain;
    final role = widget.role;
    var prepared = widget.content?.source == source ? widget.content : null;
    final html = GStorage.showEmoji ? prepared?.emojiHtml : prepared?.html;
    // Final caller-side gate sees exactly what reaches the eager renderer.
    // Legacy rendering below performs no normalization/emoji expansion.
    if (prepared != null &&
        prepared.kind != DetailTextKind.fallback &&
        DetailRenderBudget.reason(html ?? '') != null) {
      prepared = MarkdownContent.fallback(source, DetailRenderBudget.notice);
    }
    final style = detailBodyStyle(context, role).merge(widget.textStyle);
    if (forcePlain ||
        prepared == null ||
        prepared.kind == DetailTextKind.fallback) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!forcePlain)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                prepared?.notice ?? '正在准备排版，暂显示原文',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          RawSourceText(
            source: source,
            style: style,
            position: widget.sourcePosition ?? _rawPosition,
            isCurrent: widget.isCurrent,
            onPageNavigation: widget.onPageNavigation,
          ),
        ],
      );
    }
    if (prepared.kind == DetailTextKind.literal) {
      // Structured labels/captions were Text, not HTML. Preserve both literal
      // characters and inherited styles rather than reinterpreting entities.
      return Text(source, style: widget.textStyle, textAlign: widget.textAlign);
    }
    if (prepared.kind == DetailTextKind.plain ||
        prepared.kind == DetailTextKind.html) {
      return preparedDetailHtmlText(html!,
          role: role, isCurrent: widget.isCurrent);
    }
    final colors = Theme.of(context).colorScheme;
    String cssColor(Color color) =>
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    return HtmlWidget(
      html!,
      buildAsync: true,
      textStyle: style,
      rebuildTriggers: [
        colors,
        MediaQuery.textScalerOf(context),
        GStorage.fontChoice,
        GStorage.readingPreset,
      ],
      customStylesBuilder: (element) => switch (element.localName) {
        'a' => {'text-decoration': 'none'},
        'strong' || 'b' => {'font-weight': '500'},
        'p' => {'margin': '0 0 10px 0'},
        'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6' => {
            'margin': '14px 0 8px 0',
            'line-height': '1.4',
            'font-weight': '500',
          },
        'blockquote' => {
            'margin': '8px 0',
            'padding-left': '12px',
            'border-left': '3px solid ${cssColor(colors.outlineVariant)}',
          },
        'code' => {
            'font-family': 'monospace',
            'background-color': cssColor(colors.surfaceContainerHighest),
          },
        _ => null,
      },
      customWidgetBuilder: (element) {
        if (element.localName == 'img') return const SizedBox.shrink();
        if (element.localName != 'pre') return null;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              element.text,
              style: style.copyWith(
                fontFamily: 'monospace',
                fontFamilyFallback: [
                  if (style.fontFamily != null) style.fontFamily!,
                  ...?style.fontFamilyFallback,
                ],
              ),
            ),
          ),
        );
      },
      onTapUrl: (url) {
        if (isCurrent?.call() == false) return true;
        if (MarkdownContent.allowsUrl(url)) Utils.onOpenLink(url, null, true);
        return true;
      },
      onErrorBuilder: (_, __, ___) => RawSourceText(
        source: source,
        style: style,
        position: widget.sourcePosition ?? _rawPosition,
        isCurrent: widget.isCurrent,
        onPageNavigation: widget.onPageNavigation,
      ),
    );
  }
}

/// Raw is selectable literal text, never HtmlWidget, link routing or media.
/// Paginated so a rejected huge body does not become one huge main-isolate
/// paragraph. Normal boundaries preserve graphemes; an overlong single
/// cluster is explicitly labeled and split only at code-point boundaries.
class RawSourceText extends StatefulWidget {
  const RawSourceText({
    super.key,
    required this.source,
    required this.style,
    this.position,
    this.onPageNavigation,
    this.isCurrent,
  });
  final String source;
  final TextStyle style;
  final RawSourcePosition? position;
  final VoidCallback? onPageNavigation;
  final bool Function()? isCurrent;
  @override
  State<RawSourceText> createState() => _RawSourceTextState();
}

class _RawSourceTextState extends State<RawSourceText> {
  final _job = DetailParseJob<SourcePage>();
  late RawSourcePosition _position = widget.position ?? RawSourcePosition();
  List<int> get _offsets => _position.offsets;
  int get _index => _position.index;
  set _index(int value) => _position.index = value;
  SourcePage? _page;
  var _request = 0;
  bool _failed = false;
  bool _navigateToStart = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RawSourceText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.position != widget.position) {
      _position = widget.position ?? RawSourcePosition();
      _offsets
        ..clear()
        ..add(0);
      _position.splitEnds
        ..clear()
        ..add(0);
      _index = 0;
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.isCurrent?.call() == false) {
      _job.cancel();
      return;
    }
    final request = ++_request;
    _page = null;
    _failed = false;
    if (widget.source.length <= 4000) {
      _page = SourcePage(widget.source, widget.source.length);
      return;
    }
    final page = await _job.run(prepareSourcePage, (
      widget.source,
      _offsets[_index],
      _position.splitEnds[_index],
    ));
    if (!mounted || request != _request || widget.isCurrent?.call() == false) {
      return;
    }
    setState(() {
      _page = page;
      _failed = page == null;
    });
    if (page != null && _navigateToStart) {
      _navigateToStart = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            request == _request &&
            identical(_page, page) &&
            widget.isCurrent?.call() != false &&
            ModalRoute.of(context)?.isCurrent != false) {
          Scrollable.ensureVisible(
            context,
            alignment: 0,
            duration: Duration.zero,
          );
        }
      });
    }
  }

  void _move(int index) {
    if (!mounted || widget.isCurrent?.call() == false) return;
    widget.onPageNavigation?.call();
    setState(() {
      _navigateToStart = true;
      _index = index;
      _load();
    });
  }

  @override
  void dispose() {
    _job.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isCurrent?.call() == false) return const SizedBox.shrink();
    final page = _page;
    final isCurrent = widget.isCurrent;
    final request = _request;
    final index = _index;
    final position = _position;
    // Every callback belongs to exactly this rendered page/load generation.
    // _load clears _page and increments _request synchronously, so a rapid
    // repeated tap cannot consume the old page's nextOffset twice.
    bool canAct() =>
        mounted &&
        isCurrent?.call() != false &&
        request == _request &&
        index == _index &&
        identical(position, _position) &&
        identical(page, _page);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (page != null) SelectableText(page.text, style: widget.style),
        if (page?.notice != null) Text(page!.notice!),
        if (page == null)
          _failed
              ? TextButton(
                  onPressed: () {
                    if (!canAct()) return;
                    setState(() {
                      _load();
                    });
                  },
                  child: const Text('原文分段暂不可用，重试'),
                )
              : const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('正在准备原文分段…'),
                ),
        if (widget.source.length > 4000)
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: index > 0
                    ? () {
                        if (!canAct()) return;
                        _move(index - 1);
                      }
                    : null,
                child: const Text('上一段'),
              ),
              Text('原文第 ${_index + 1} 段'),
              TextButton(
                onPressed:
                    page != null && page.nextOffset < widget.source.length
                        ? () {
                            if (!canAct()) return;
                            if (_offsets.length == index + 1) {
                              _offsets.add(page.nextOffset);
                              _position.splitEnds.add(page.splitUntil);
                            }
                            _move(index + 1);
                          }
                        : null,
                child: const Text('下一段'),
              ),
            ],
          ),
      ],
    );
  }
}
