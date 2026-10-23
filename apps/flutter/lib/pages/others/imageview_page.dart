import 'dart:async';

import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

import '../../components/retryable_media_image.dart';
import '../../utils/download_util.dart';
import '../../utils/utils.dart';

class ImageViewPage extends StatefulWidget {
  const ImageViewPage({super.key, this.imageProviderBuilder});

  /// Optional image source for deterministic offline image-stream tests.
  /// Normal routes always use the cached network provider below.
  final MediaImageProviderBuilder? imageProviderBuilder;

  @override
  State<ImageViewPage> createState() => _ImageViewPageState();
}

class _ImageViewPageState extends State<ImageViewPage> {
  late int _initialPage;
  final _currentPageStream = StreamController<int>();
  late List<String> _imgList;
  late final List<MediaImageAttempt> _attempts;
  late final _pageController = PageController(initialPage: _initialPage);

  @override
  void dispose() {
    for (final attempt in _attempts) {
      attempt.dispose();
    }
    _currentPageStream.close();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final arguments = Get.arguments as Map?;
    _imgList = List<String>.unmodifiable(arguments?['imgList'] ?? <String>[]);
    _attempts = List.generate(
      _imgList.length,
      (index) => MediaImageAttempt(_imgList[index], index,
          providerBuilder: widget.imageProviderBuilder),
    );
    final int initialPage = arguments?['initialPage'] ?? 0;
    _initialPage =
        _imgList.isEmpty ? 0 : initialPage.clamp(0, _imgList.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder(
          initialData: _initialPage,
          stream: _currentPageStream.stream,
          builder: (_, snapshot) => Text(
              '${_imgList.isEmpty ? 0 : snapshot.data! + 1}/${_imgList.length}'),
        ),
      ),
      body: _imgList.isEmpty
          ? const Center(child: Text('没有可查看的图片'))
          : Stack(
              alignment: Alignment.center,
              children: [
                GestureDetector(
                  onLongPress: () {
                    showDialog(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            clipBehavior: Clip.hardEdge,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 12),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  title: const Text(
                                    '保存图片',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                  onTap: () {
                                    DownloadUtils.downloadImg(
                                        [_imgList[_initialPage]]);
                                    Get.back();
                                  },
                                ),
                                if (_imgList.length != 1)
                                  ListTile(
                                    title: const Text(
                                      '保存全部图片',
                                      style: TextStyle(fontSize: 14),
                                    ),
                                    onTap: () {
                                      DownloadUtils.downloadImg(_imgList);
                                      Get.back();
                                    },
                                  ),
                                ListTile(
                                  title: const Text(
                                    '分享',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                  onTap: () {
                                    Utils.onShareImg(_imgList[_initialPage]);
                                    Get.back();
                                  },
                                ),
                                ListTile(
                                  title: const Text(
                                    '复制',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                  onTap: () {
                                    Utils.copyText(_imgList[_initialPage]);
                                    Get.back();
                                  },
                                ),
                                if (Utils.isDesktop)
                                  ListTile(
                                    title: const Text(
                                      '在浏览器中打开',
                                      style: TextStyle(fontSize: 14),
                                    ),
                                    onTap: () {
                                      Utils.launchURL(_imgList[_initialPage]);
                                      Get.back();
                                    },
                                  ),
                              ],
                            ),
                          );
                        });
                  },
                  // PhotoViewGallery 0.15 fixes each PhotoView key to its page
                  // index. Its image wrapper also keeps its error on provider
                  // changes. Use the same public paging scope, with a retry key
                  // inside each page, so retry only remounts the failed image.
                  child: PhotoViewGestureDetectorScope(
                    axis: Axis.horizontal,
                    child: PageView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      controller: _pageController,
                      itemCount: _imgList.length,
                      itemBuilder: (context, index) => ClipRect(
                        child: RetryableMediaImage(
                          key: ValueKey(index),
                          url: _imgList[index],
                          index: index,
                          isGallery: true,
                          heroTag: (this, index),
                          attempt: _attempts[index],
                        ),
                      ),
                      onPageChanged: (index) {
                        _initialPage = index;
                        _currentPageStream.add(index);
                      },
                    ),
                  ),
                ),
                if (Utils.isDesktop && _imgList.length != 1)
                  Positioned(
                    left: 0,
                    child: IconButton(
                      onPressed: () {
                        _pageController.animateToPage(
                          _pageController.page!.round() - 1,
                          duration: const Duration(milliseconds: 255),
                          curve: Curves.ease,
                        );
                      },
                      icon: Icon(
                        Icons.arrow_back,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6),
                      ),
                      style: IconButton.styleFrom(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surface
                              .withOpacity(0.5)),
                    ),
                  ),
                if (Utils.isDesktop && _imgList.length != 1)
                  Positioned(
                    right: 0,
                    child: IconButton(
                      onPressed: () {
                        _pageController.animateToPage(
                          _pageController.page!.round() + 1,
                          duration: const Duration(milliseconds: 255),
                          curve: Curves.ease,
                        );
                      },
                      icon: Icon(
                        Icons.arrow_forward,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6),
                      ),
                      style: IconButton.styleFrom(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surface
                              .withOpacity(0.5)),
                    ),
                  ),
              ],
            ),
    );
  }
}
