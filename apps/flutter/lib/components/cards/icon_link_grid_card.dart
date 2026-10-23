import 'package:c001apk_flutter/components/network_image.dart';
import 'package:expandable_page_view/expandable_page_view.dart';
import 'package:flutter/material.dart';

import '../../logic/model/feed/entity.dart';
import '../../utils/extensions.dart';
import '../../utils/utils.dart';

class IconLinkGridCard extends StatefulWidget {
  const IconLinkGridCard({super.key, required this.dataList});

  final List<Entity> dataList;

  @override
  State<IconLinkGridCard> createState() => _IconLinkGridCardState();
}

class _IconLinkGridCardState extends State<IconLinkGridCard> {
  int get _page => (widget.dataList.length + 4) ~/ 5;
  int _currentPage = 0;
  final PageController _controller = PageController();

  @override
  void didUpdateWidget(covariant IconLinkGridCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final lastPage = _page == 0 ? 0 : _page - 1;
    if (_currentPage > lastPage) {
      _currentPage = lastPage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) {
          _controller.jumpToPage(_currentPage);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.dataList.isEmpty) return const SizedBox.shrink();
    return Material(
      clipBehavior: Clip.hardEdge,
      color: Theme.of(context).colorScheme.onInverseSurface,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExpandablePageView.builder(
            controller: _controller,
            itemCount: _page,
            pageSnapping: true,
            onPageChanged: (index) {
              // The page-view package also reports a clamped page during
              // didUpdateWidget. The parent has already applied that clamp.
              if (_currentPage != index) {
                setState(() => _currentPage = index);
              }
            },
            itemBuilder: (context, page) {
              return LayoutBuilder(builder: (context, constraints) {
                final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
                final cellBudget = 60 * (scale < 1 ? 1 : scale);
                final columns =
                    (constraints.maxWidth / cellBudget).floor().clamp(1, 5);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate((5 + columns - 1) ~/ columns, (row) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(columns, (column) {
                        final slot = row * columns + column;
                        final index = page * 5 + slot;
                        return slot < 5 && index < widget.dataList.length
                            ? _iconLinkGridCardItem(widget.dataList[index])
                            : const Expanded(child: SizedBox.shrink());
                      }),
                    );
                  }),
                );
              });
            },
          ),
          if (_page > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_page, (index) {
                  return Semantics(
                    label: '第 ${index + 1} 页，共 $_page 页',
                    selected: _currentPage == index,
                    button: true,
                    child: InkWell(
                      onTap: () {
                        _controller.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 255),
                          curve: Curves.ease,
                        );
                      },
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: Container(
                            width: _currentPage == index ? 10 : 7,
                            height: 5,
                            decoration: BoxDecoration(
                              borderRadius:
                                  const BorderRadius.all(Radius.circular(12)),
                              color: _currentPage == index
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withAlpha(128),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _iconLinkGridCardItem(Entity data) {
    // Bound shaping and accessibility work without splitting UTF-16 pairs.
    // Only inspect one code point beyond the display limit.
    final titleRunes =
        data.title.orEmpty.runes.take(81).toList(growable: false);
    final titleTruncated = titleRunes.length > 80;
    final title = String.fromCharCodes(titleRunes.take(80));
    return Expanded(
      flex: 1,
      child: InkWell(
        onTap: () => Utils.onOpenLink(data.url.orEmpty, data.title),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                networkImage(
                  data.pic.orEmpty,
                  height: 30,
                  width: 30,
                  borderRadius: BorderRadius.circular(8),
                ),
                Text(
                  titleTruncated ? '$title…' : title,
                  semanticsLabel: titleTruncated ? '$title，标题过长，已缩略' : title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
