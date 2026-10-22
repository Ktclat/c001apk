import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../components/floating_tab_bar.dart';
import '../../../pages/carousel/carousel_page.dart';
import '../../../pages/home/topic/controller.dart';
import '../../../pages/home/home_page.dart' show TabType;

class HomeTopicPage extends StatefulWidget {
  const HomeTopicPage({super.key, required this.tabType});

  final TabType tabType;

  @override
  State<HomeTopicPage> createState() => _HomeTopicPageState();
}

class _HomeTopicPageState extends State<HomeTopicPage>
    with AutomaticKeepAliveClientMixin {
  late HomeTopicController _homeTopicController;
  late PageController _controller;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller =
        PageController(initialPage: widget.tabType == TabType.TOPIC ? 1 : 0);
    _homeTopicController = Get.put(
      HomeTopicController(tabType: widget.tabType),
      tag: widget.tabType.name,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    Get.delete<HomeTopicController>(
      tag: widget.tabType.name,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _homeTopicController.obx(
      (data) {
        return Row(
          children: [
            Expanded(
              flex: 22,
              child: ListView.builder(
                padding: EdgeInsets.only(
                    bottom: FloatingNavigationInset.scrollPaddingOf(context)),
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                itemCount: widget.tabType == TabType.TOPIC
                    ? data![0].entities!.length
                    : data!.length,
                // IntrinsicHeight adds an expensive measurement pass
                // for every visible topic item.
                itemBuilder: (context, index) => Obx(() {
                  final selected =
                      index == _homeTopicController.currentIndex.value;
                  final colors = Theme.of(context).colorScheme;
                  return InkWell(
                    onTap: () {
                      _homeTopicController.currentIndex.value = index;
                      const RootNavigationContentChanged().dispatch(context);
                      _controller.jumpToPage(index);
                    },
                    child: Ink(
                      decoration: BoxDecoration(
                        color: selected
                            ? colors.onInverseSurface
                            : Colors.transparent,
                        border: Border(
                          left: BorderSide(
                            width: 3,
                            color:
                                selected ? colors.primary : Colors.transparent,
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 4),
                        child: Text(
                          widget.tabType == TabType.TOPIC
                              ? data[0].entities![index].title.toString()
                              : data[index].title.toString(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: selected ? colors.primary : colors.onSurface,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
              flex: 78,
              child: Container(
                color: Theme.of(context).colorScheme.onInverseSurface,
                child: PageView.builder(
                  controller: _controller,
                  scrollDirection: Axis.vertical,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.tabType == TabType.TOPIC
                      ? data[0].entities!.length
                      : data.length,
                  itemBuilder: (context, index) =>
                      NotificationListener<ScrollNotification>(
                    onNotification: (_) =>
                        index != _homeTopicController.currentIndex.value,
                    child: CarouselPage(
                      isInit: false,
                      url: widget.tabType == TabType.TOPIC
                          ? data[0].entities![index].url
                          : data[index].url,
                      title: widget.tabType == TabType.TOPIC
                          ? data[0].entities![index].title
                          : data[index].title,
                      isHomeCard: true,
                    ),
                  ),
                ),
              ),
            )
          ],
        );
      },
      onEmpty: GestureDetector(
        onTap: _homeTopicController.onReload,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(10.0),
          child: const Text('暂无内容'),
        ),
      ),
      onError: (error) => GestureDetector(
        onTap: _homeTopicController.onReload,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(10.0),
          child: Text(error ?? '加载失败，请重试'),
        ),
      ),
    );
  }
}
