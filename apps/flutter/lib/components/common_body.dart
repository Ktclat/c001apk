import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../components/footer.dart';
import '../components/floating_tab_bar.dart';
import '../components/item_card.dart';
import '../logic/model/feed/datum.dart';
import '../logic/state/loading_state.dart';
import '../pages/common/common_controller.dart';

Widget _bodyState(String text, Function() onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(10.0),
      child: Text(text),
    ),
  );
}

Widget commonBody(
  CommonController commonController, {
  Widget? leading,
  Widget Function(Datum)? itemBuilder,
  bool isHomeCard = false,
  bool isReply2Reply = false,
  dynamic uid,
}) {
  return Obx(() {
    final body = buildBody(
      commonController,
      leading: leading,
      itemBuilder: itemBuilder,
      isHomeCard: isHomeCard,
      isReply2Reply: isReply2Reply,
      uid: uid,
    );
    if (commonController.loadingState.value is Success) {
      return RefreshIndicator(
        key: commonController.refreshKey,
        onRefresh: () async {
          commonController.onReset();
          await commonController.onGetData();
        },
        child: body,
      );
    }
    if (leading == null) {
      // Center short states in the usable area, not behind the overlay. Larger
      // errors remain scrollable so their retry target can always be reached.
      return LayoutBuilder(builder: (context, constraints) {
        final clearance = FloatingNavigationInset.scrollPaddingOf(context);
        final usableHeight =
            constraints.hasBoundedHeight && constraints.maxHeight > clearance
                ? constraints.maxHeight - clearance
                : 0.0;
        return SingleChildScrollView(
          padding: EdgeInsets.only(bottom: clearance),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: usableHeight),
            child: Center(child: body),
          ),
        );
      });
    }
    // Headers must scroll with empty/error/loading content too, especially in
    // short windows with large text. A fixed leading Column can consume the
    // entire usable viewport above the floating navigation.
    return Builder(
        builder: (context) => ListView(
              padding: EdgeInsets.fromLTRB(10, 10, 10,
                  10 + FloatingNavigationInset.scrollPaddingOf(context)),
              children: [
                leading,
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: body)
              ],
            ));
  });
}

Widget buildBody(
  CommonController commonController, {
  Widget? leading,
  Widget Function(Datum)? itemBuilder,
  bool isHomeCard = false,
  bool isReply2Reply = false,
  dynamic uid,
  Function(
    dynamic id,
    dynamic uname,
    dynamic fid,
  )? onReply,
}) {
  switch (commonController.loadingState.value) {
    case Empty():
      return _bodyState(
        '暂无内容',
        () {
          commonController.isEnd = false;
          commonController.setLoadingState(LoadingState.loading());
          commonController.onGetData(true);
        },
      );
    case Error():
      return _bodyState(
        (commonController.loadingState.value as Error).errMsg,
        () {
          commonController.isEnd = false;
          commonController.setLoadingState(LoadingState.loading());
          commonController.onGetData(true);
        },
      );
    case Success():
      var dataList = (commonController.loadingState.value as Success).response
          as List<Datum>;
      return Builder(
        builder: (context) => ListView.separated(
          controller: commonController.scrollController,
          physics: AlwaysScrollableScrollPhysics(
            parent: isReply2Reply
                ? const ClampingScrollPhysics()
                : const BouncingScrollPhysics(),
          ),
          padding: EdgeInsets.only(
              left: isReply2Reply ? 0 : 10,
              top: isReply2Reply ? 0 : 10,
              right: isReply2Reply ? 0 : 10,
              bottom: (isReply2Reply ? 0 : 10) +
                  FloatingNavigationInset.scrollPaddingOf(context)),
          itemCount: dataList.length + 1 + (leading == null ? 0 : 1),
          itemBuilder: (_, index) {
            if (leading != null) {
              if (index == 0) return leading;
              index--;
            }
            if (index == dataList.length) {
              if (!commonController.isEnd && !commonController.isLoading) {
                commonController.setFooterState(LoadingState.loading());
                commonController.onGetData(false);
              }
              return Obx(
                  () => footerWidget(commonController.footerState.value, () {
                        commonController.isEnd = false;
                        commonController.setFooterState(LoadingState.loading());
                        commonController.onGetData(false);
                      }));
            } else {
              if (itemBuilder != null) return itemBuilder(dataList[index]);
              return itemCard(
                dataList[index],
                isHomeCard: isHomeCard,
                isReply2Reply: isReply2Reply,
                isTopReply: isReply2Reply && index == 0,
                uid: uid,
                onBlock: commonController.onBlock,
                onReply: onReply,
                onDelete: commonController.postLikeDeleteFollow,
                onDeleteNoti: (id) => commonController.postLikeDeleteFollow(
                  id,
                  null,
                  isNoti: true,
                ),
                onLike: commonController.onLike,
                onPM: commonController.onPM,
              );
            }
          },
          separatorBuilder: (_, index) => isReply2Reply
              ? const Divider(height: 1)
              : const SizedBox(height: 10),
        ),
      );
  }
  return Container(
    height: 80,
    alignment: Alignment.center,
    padding: const EdgeInsets.all(10.0),
    child: const CircularProgressIndicator(),
  );
}
