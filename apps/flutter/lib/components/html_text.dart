import 'package:c001apk_flutter/components/network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:get/get.dart';

import '../utils/emoji_util.dart';
import '../utils/extensions.dart';
import '../utils/storage_util.dart';
import '../utils/utils.dart';

enum HtmlTextRole {
  normal,
  feedBody,
  feedTitle,
  articleBody,
  articleTitle,
  replyBody,
}

/// Render simple Markdown bold and normalize excessive empty paragraphs.
/// HTML links and rich inline content remain intact.
String normalizePostMarkup(String text) => text
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll(RegExp(r'\n(?:[ \t]*\n){2,}'), '\n\n')
    .replaceAllMapped(
      RegExp(r'\*\*([^*<>\n]+)\*\*'),
      (match) => '<strong>' + match.group(1)! + '</strong>',
    )
    .replaceAll('\n', '<br/>');

Color? _bodyInk(HtmlTextRole role) {
  if (role == HtmlTextRole.normal) return null;
  final context = Get.context;
  if (context == null || !context.mounted) return null;
  return Theme.of(context).colorScheme.onSurface.withOpacity(0.92);
}

Widget htmlText(
  String html, {
  double fontSize = 15,
  bool isBold = false,
  HtmlTextRole role = HtmlTextRole.normal,
  List<String>? picArr,
  Function? onClick,
  Function? onShowTotalReply,
  Function? onViewFan,
}) {
  // Paragraphs must be normalized even when custom emojis are disabled.
  // The old renderer could show literal **Markdown markers** in news posts.
  var formatted = normalizePostMarkup(html);
  if (GStorage.showEmoji) {
    formatted = formatted.replaceAllMapped(
      RegExp(r'\[[^\]]+\]'),
      (match) {
        final marker = match.group(0) ?? '';
        final src = EmojiUtil.emojiMap[marker];
        return src == null || src.isEmpty ? marker : '<img src="$src">';
      },
    );
  }

  return _renderHtmlText(formatted,
      fontSize: fontSize,
      isBold: isBold,
      role: role,
      picArr: picArr,
      onClick: onClick,
      onShowTotalReply: onShowTotalReply,
      onViewFan: onViewFan);
}

/// Detail-only sanitized, post-expansion and budget-checked HTML. No additional
/// normalization or emoji expansion may happen after the caller's layout gate.
Widget preparedDetailHtmlText(String formatted,
        {required HtmlTextRole role, bool Function()? isCurrent}) =>
    _renderHtmlText(formatted, role: role, isCurrent: isCurrent);

Widget _renderHtmlText(String formatted,
    {double fontSize = 15,
    bool isBold = false,
    HtmlTextRole role = HtmlTextRole.normal,
    List<String>? picArr,
    Function? onClick,
    Function? onShowTotalReply,
    Function? onViewFan,
    bool Function()? isCurrent}) {
  final reading = GStorage.readingPreset;

  return HtmlWidget(
    formatted,
    onTapUrl: (url) {
      if (isCurrent?.call() == false) return true;
      if (url.isEmpty) {
        if (onClick != null) {
          onClick();
        }
      } else if (url.contains('/feed/replyList')) {
        if (onShowTotalReply != null) {
          onShowTotalReply();
        }
      } else if (url.contains('image.coolapk.com')) {
        Map<dynamic, dynamic> arguments = {
          "imgList": !picArr.isNullOrEmpty ? picArr : [url],
        };
        Get.toNamed('/imageview', arguments: arguments);
      } else if (url == '/contacts/fans') {
        if (onViewFan != null) {
          onViewFan();
        }
      } else {
        Utils.onOpenLink(url, null);
      }
      return true;
    },
    textStyle: TextStyle(
      // HtmlWidget receives its own root text style. Match the font choice
      // used by Material widgets so feeds, articles and replies stay aligned.
      fontFamily: GStorage.fontChoice.familyForPlatform(defaultTargetPlatform),
      fontFamilyFallback: const ['sans-serif'],
      locale: const Locale('zh', 'CN'),
      color: _bodyInk(role),
      letterSpacing: 0,
      fontSize: switch (role) {
        HtmlTextRole.feedBody => reading.bodySize,
        HtmlTextRole.feedTitle => reading.titleSize,
        HtmlTextRole.articleBody => reading.articleBodySize,
        HtmlTextRole.articleTitle => reading.articleTitleSize,
        HtmlTextRole.replyBody => reading.replySize,
        HtmlTextRole.normal => fontSize,
      },
      height: switch (role) {
        HtmlTextRole.feedBody => reading.bodyHeight,
        HtmlTextRole.feedTitle => reading.titleHeight,
        HtmlTextRole.articleBody => reading.bodyHeight,
        HtmlTextRole.articleTitle => reading.titleHeight,
        HtmlTextRole.replyBody => reading.bodyHeight,
        HtmlTextRole.normal => 1.5,
      },
      fontWeight: switch (role) {
        HtmlTextRole.feedBody => FontWeight.w400,
        HtmlTextRole.feedTitle => reading.titleWeight,
        HtmlTextRole.articleBody => FontWeight.w400,
        HtmlTextRole.articleTitle => reading.titleWeight,
        HtmlTextRole.replyBody => FontWeight.w400,
        HtmlTextRole.normal => isBold ? FontWeight.bold : FontWeight.w400,
      },
    ),
    customStylesBuilder: (element) {
      switch (element.localName) {
        case 'a':
          return {'text-decoration': 'none'};
        case 'strong':
        case 'b':
          // Avoid excessively dark synthetic bold for Markdown emphasis.
          return {'font-weight': '500'};
      }
      return null;
    },
    customWidgetBuilder: (element) {
      if (isCurrent?.call() == false) return const SizedBox.shrink();
      switch (element.localName) {
        case 'img':
          {
            double size =
                MediaQuery.of(Get.context!).textScaler.scale(fontSize);
            String src = element.attributes['src'] ?? '';
            return InlineCustomWidget(
              alignment: PlaceholderAlignment.middle,
              child: src.endsWith('icon')
                  ? Icon(
                      size: size * 1.3,
                      Icons.photo_outlined,
                      color: Theme.of(Get.context!).colorScheme.primary,
                    )
                  : src.endsWith('png')
                      ? Image.asset(
                          'assets/emojis/$src',
                          width: size * 1.3,
                          height: size * 1.3,
                        )
                      : src.startsWith('http')
                          ? networkImage(
                              src,
                              width: size * 1.3,
                              height: size * 1.3,
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(Get.context!)
                                      .colorScheme
                                      .primary,
                                ),
                                borderRadius:
                                    const BorderRadius.all(Radius.circular(4)),
                              ),
                              child: Text(
                                src,
                                style: TextStyle(
                                  height: 1,
                                  fontWeight: FontWeight.bold,
                                  fontSize: fontSize - 4,
                                  color: Theme.of(Get.context!)
                                      .colorScheme
                                      .primary,
                                ),
                                strutStyle: StrutStyle(
                                  height: 1,
                                  leading: 0,
                                  fontWeight: FontWeight.bold,
                                  fontSize: fontSize - 4,
                                ),
                              ),
                            ),
            );
          }
      }
      return null;
    },
  );
}
