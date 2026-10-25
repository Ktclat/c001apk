import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../components/html_text.dart';
import '../components/imageview.dart';
import '../logic/model/feed_article/feed_article.dart';
import '../utils/extensions.dart';
import '../utils/utils.dart';

Widget feedArticleBody(
  double maxWidth,
  FeedArticle data,
  List<String> picArr, {
  Widget? detailBody,
  Widget? detailTitle,
  Widget? detailDescription,
  bool Function()? isCurrent,
}) {
  switch (data.type) {
    case 'title':
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: detailTitle ??
            htmlText(
              data.title.orEmpty,
              role: HtmlTextRole.articleTitle,
            ),
      );
    case 'text':
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GestureDetector(
          onLongPress: () {
            if (isCurrent?.call() == false) return;
            Get.toNamed('/copy', parameters: {'text': data.message.orEmpty});
            HapticFeedback.mediumImpact();
          },
          child: detailBody ??
              htmlText(
                data.message.orEmpty,
                role: HtmlTextRole.articleBody,
              ),
        ),
      );
    case 'image':
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            image(
              maxWidth - 32,
              picArr,
              isFeedArticle: true,
              articleImg: data.url.orEmpty,
              isCurrent: isCurrent,
            ),
            if (!data.description.isNullOrEmpty) ...[
              const SizedBox(height: 4),
              detailDescription ??
                  Text(
                    data.description!,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(Get.context!).colorScheme.outline,
                    ),
                    textAlign: TextAlign.center,
                  ),
            ]
          ],
        ),
      );
    case 'shareUrl':
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: InkWell(
          onTap: () {
            if (isCurrent?.call() == false) return;
            Utils.onOpenLink(data.url.orEmpty);
          },
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          child: Ink(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              color: Theme.of(Get.context!).colorScheme.onInverseSurface,
            ),
            padding: const EdgeInsets.all(10),
            child: detailTitle ?? Text(data.title.orEmpty),
          ),
        ),
      );
  }
  return const SizedBox();
}
