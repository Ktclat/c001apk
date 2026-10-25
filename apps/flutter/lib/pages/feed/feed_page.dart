// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:get/get_navigation/src/dialog/dialog_route.dart';
import 'package:share_plus/share_plus.dart';

import '../../components/cards/feed_reply_card.dart';
import '../../components/feed_article_body.dart';
import '../../components/markdown_body.dart';
import '../../components/html_text.dart';
import '../../logic/reading/detail_body_snapshot.dart';
import '../../components/footer.dart';
import '../../components/sliver_pinned_box_adapter.dart';
import '../../components/cards/feed_card.dart';
import '../../logic/model/feed/datum.dart';
import '../../logic/state/loading_state.dart';
import '../../pages/feed/feed_controller.dart';
import '../../pages/feed/reply/reply_dialog.dart' show ReplyType;
import '../../pages/feed/reply/reply_page.dart';
import '../../utils/device_util.dart';
import '../settings/device_identity_page.dart';
import '../../utils/extensions.dart';
import '../../utils/global_data.dart';
import '../../utils/storage_util.dart';
import '../../utils/utils.dart';

enum FeedMenuItem {
  Copy,
  Share,
  Fav,
  Block,
  Source,
  Report;

  String get label => switch (this) {
        FeedMenuItem.Copy => '复制',
        FeedMenuItem.Share => '分享',
        FeedMenuItem.Fav => '收藏',
        FeedMenuItem.Block => '屏蔽',
        FeedMenuItem.Source => '查看原文',
        FeedMenuItem.Report => '举报',
      };
}

enum ReplySortType { def, dateline, hot, author }

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> with TickerProviderStateMixin {
  final String _id = Get.parameters['id'].orEmpty;
  final _refreshKey = GlobalKey<RefreshIndicatorState>();
  AnimationController? _fabAnimationCtr;
  late bool _isFabVisible = true;
  late final _scrollController = ScrollController();
  late final StreamController<bool> _titleStreamC = StreamController<bool>();
  late bool _visibleTitle = false;
  bool _showSource = false;
  double _formattedOffset = 0, _sourceOffset = 0;
  DetailBodySnapshot? _bodyScope;
  double? _pendingScrollTarget;

  DetailBodySnapshot? get _currentBody {
    final snapshot = _feedController.bodySnapshot.value;
    if (snapshot == null ||
        !snapshot.belongsTo(GlobalData().uid, GlobalData().sessionGeneration)) {
      _bodyScope = null;
      _pendingScrollTarget = null;
      _showSource = false;
      return null;
    }
    if (_bodyScope == null || !_bodyScope!.sameBody(snapshot)) {
      _showSource = false;
      _formattedOffset = 0;
      _sourceOffset = 0;
      _pendingScrollTarget = null;
      _bodyScope = snapshot;
    }
    return snapshot;
  }

  bool _ownsBody(DetailBodySnapshot? expected, {bool? sourceMode}) {
    if (!mounted || expected == null || _feedController.ownedFeed == null) {
      return false;
    }
    final current = _feedController.bodySnapshot.value;
    return current != null &&
        expected.sameBody(current) &&
        current.belongsTo(GlobalData().uid, GlobalData().sessionGeneration) &&
        (sourceMode == null || sourceMode == _showSource) &&
        ModalRoute.of(context)?.isActive != false;
  }

  Widget _detailText(String key, String source, HtmlTextRole role,
      {TextStyle? textStyle, TextAlign? textAlign}) {
    final snapshot = _currentBody;
    // A missing/mismatched snapshot is not legacy data. In particular, never
    // revive the old mutable Success body during account persistence's gap.
    if (!_ownsBody(snapshot) || !snapshot!.sources.containsKey(key)) {
      return const SizedBox.shrink();
    }
    final mode = _showSource;
    return FeedText(
      key: ValueKey((snapshot.account, snapshot.generation, _id, key, source)),
      source: snapshot.sources[key]!,
      content: snapshot.documents[key],
      forcePlain: mode,
      role: role,
      textStyle: textStyle,
      textAlign: textAlign,
      sourcePosition: _feedController.sourcePositionFor(key),
      isCurrent: () => _ownsBody(snapshot, sourceMode: mode),
      onPageNavigation: () {
        if (_ownsBody(snapshot, sourceMode: mode)) _pendingScrollTarget = null;
      },
    );
  }

  void _toggleSource() {
    if (_currentBody?.offersSource != true) return;
    final offset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    if (_showSource) {
      _sourceOffset = offset;
    } else {
      _formattedOffset = offset;
    }
    setState(() => _showSource = !_showSource);
    final scope = _bodyScope;
    final raw = _showSource;
    _pendingScrollTarget = raw ? _sourceOffset : _formattedOffset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          (scope == null ||
              _currentBody == null ||
              !scope.sameBody(_currentBody!)) ||
          raw != _showSource) {
        return;
      }
      _restoreScrollPosition();
    });
  }

  void _restoreScrollPosition() {
    // Validate ownership before reading the pending target: the getter clears
    // a previous body's restoration when an async layout arrives after refresh.
    if (_currentBody == null || !_scrollController.hasClients) return;
    final target = _pendingScrollTarget;
    if (target == null) return;
    final maximum = _scrollController.position.maxScrollExtent;
    _scrollController.jumpTo(target.clamp(0.0, maximum));
    if (target <= maximum) _pendingScrollTarget = null;
  }

  @override
  void initState() {
    super.initState();
    // A mounted guest detail may become logged in before an explicit retry.
    _fabAnimationCtr = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fabAnimationCtr?.forward();
    _scrollController.addListener(() {
      final ScrollDirection direction =
          _scrollController.position.userScrollDirection;
      if (direction == ScrollDirection.forward) {
        _showFab();
      } else if (direction == ScrollDirection.reverse) {
        _hideFab();
      }
    });
  }

  void _showFab() {
    if (!_isFabVisible) {
      _isFabVisible = true;
      _fabAnimationCtr?.forward();
    }
  }

  void _hideFab() {
    if (_isFabVisible) {
      _isFabVisible = false;
      _fabAnimationCtr?.reverse();
    }
  }

  @override
  void dispose() {
    _titleStreamC.close();
    _scrollController.removeListener(() {});
    _scrollController.dispose();
    _fabAnimationCtr?.dispose();
    Get.delete<FeedController>(tag: _id + _random);
    super.dispose();
  }

  late final String _random = DeviceUtil.randHexString(8);
  late final _feedController = Get.put(
    FeedController(id: _id, recordHistory: GStorage.recordHistory),
    tag: _id + _random,
  );

  static const List<(ReplySortType, String)> _shirtSizeOptions =
      <(ReplySortType, String)>[
    (ReplySortType.def, '默认'),
    (ReplySortType.dateline, '最新'),
    (ReplySortType.hot, '热门'),
    (ReplySortType.author, '楼主'),
  ];

  Widget _buildFeedContent(LoadingState feedState) {
    switch (feedState) {
      case Empty():
        return GestureDetector(
          onTap: () {
            _feedController.setFeedState(LoadingState.loading());
            _feedController.getFeedData();
          },
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(10.0),
            child: const Text('暂无内容'),
          ),
        );
      case Error():
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(feedState.errMsg, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: () {
                      _feedController.setFeedState(LoadingState.loading());
                      _feedController.getFeedData(verify: true);
                    },
                    child: const Text('重试'),
                  ),
                  if (feedState.canVerify)
                    TextButton(
                      onPressed: () async {
                        final previousDevice = GStorage.xAppDevice;
                        await Get.to(() => const DeviceIdentityPage());
                        if (!mounted || previousDevice == GStorage.xAppDevice) {
                          return;
                        }
                        _feedController.setFeedState(LoadingState.loading());
                        await _feedController.getFeedData();
                      },
                      child: const Text('导入官方设备标识'),
                    ),
                ],
              ),
            ],
          ),
        );
      case Success():
        final snapshot = _currentBody;
        if (!_ownsBody(snapshot)) {
          return _buildFeedContent(LoadingState.error('账号已切换，请重新打开详情'));
        }
        if (_showSource && snapshot != null) {
          final raw = Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('原始文本，仅显示，不执行链接或加载图片。'),
                for (final field in snapshot.rawFields.entries) ...[
                  const SizedBox(height: 16),
                  Text(
                      switch (field.key) {
                        'title' => '原始标题',
                        'message_cover' => '原始封面地址（仅文本）',
                        'message_raw_output' => '原始结构化正文（JSON）',
                        _ => '原始正文',
                      },
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  if (field.value == null)
                    const Text('服务端未提供此字段')
                  else
                    RawSourceText(
                      key: ValueKey((
                        snapshot.account,
                        snapshot.generation,
                        snapshot.feedId,
                        field.key,
                        field.value,
                      )),
                      source: field.value!,
                      style: detailBodyStyle(
                        context,
                        _feedController.articleList.isNullOrEmpty
                            ? HtmlTextRole.feedBody
                            : HtmlTextRole.articleBody,
                      ),
                      position: _feedController.sourcePositionFor(
                        '@raw:${field.key}',
                      ),
                      isCurrent: () => _ownsBody(snapshot, sourceMode: true),
                      onPageNavigation: () {
                        if (_ownsBody(snapshot, sourceMode: true)) {
                          _pendingScrollTarget = null;
                        }
                      },
                    ),
                ],
              ],
            ),
          );
          return _feedController.articleList.isNullOrEmpty
              ? raw
              : SliverToBoxAdapter(child: raw);
        }
        return _feedController.articleList.isNullOrEmpty
            ? FeedCard(
                data: feedState.response!,
                isFeedContent: true,
                detailBody: _detailText(
                  'body',
                  (feedState.response as Datum).message.orEmpty,
                  HtmlTextRole.feedBody,
                ),
                onLike: (id, like) {
                  if (_ownsBody(snapshot) && GlobalData().isLogin) {
                    _feedController.onLike(id, like, isFeed: true);
                  }
                },
              )
            : SliverList.separated(
                itemCount: _feedController.articleList!.length + 2,
                itemBuilder: (context, index) {
                  if (!_ownsBody(snapshot)) return const SizedBox.shrink();
                  if (index == 0) {
                    return header(context, feedState.response!, true);
                  } else if (index == _feedController.articleList!.length + 1) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: bottomInfo(
                        context,
                        feedState.response!,
                        true,
                        null,
                        isFeedArticle: true,
                        () {
                          if (_ownsBody(snapshot) && GlobalData().isLogin) {
                            Datum data = feedState.response;
                            _feedController.onLike(
                              data.id,
                              data.userAction?.like,
                              isFeed: true,
                            );
                          }
                        },
                      ),
                    );
                  } else {
                    return LayoutBuilder(
                      builder: (_, constraints) {
                        if (!_ownsBody(snapshot)) {
                          return const SizedBox.shrink();
                        }
                        return feedArticleBody(
                          constraints.maxWidth,
                          _feedController.articleList![index - 1],
                          _feedController.articleImgList!,
                          detailBody: _detailText(
                            'article:${index - 1}',
                            _feedController
                                .articleList![index - 1].message.orEmpty,
                            HtmlTextRole.articleBody,
                          ),
                          detailTitle: _detailText(
                            'article:${index - 1}:${_feedController.articleList![index - 1].type == 'title' ? 'title' : 'label'}',
                            _feedController
                                .articleList![index - 1].title.orEmpty,
                            _feedController.articleList![index - 1].type ==
                                    'title'
                                ? HtmlTextRole.articleTitle
                                : HtmlTextRole.normal,
                          ),
                          detailDescription: _detailText(
                            'article:${index - 1}:description',
                            _feedController
                                .articleList![index - 1].description.orEmpty,
                            HtmlTextRole.normal,
                            textStyle: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          isCurrent: () => _ownsBody(snapshot, sourceMode: false),
                        );
                      },
                    );
                  }
                },
                separatorBuilder: (_, index) => const SizedBox(height: 12),
              );
    }
    return const CircularProgressIndicator();
  }

  Future<void> _showAccountDetailStatus() async {
    final scope = _currentBody;
    if (!_ownsBody(scope)) return;
    final retry = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('账号信息暂不可用'),
        content: Text(_feedController.accountDetailNotice.value),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重试账号详情'),
          ),
        ],
      ),
    );
    if (retry != true || !_ownsBody(scope)) return;
    await _feedController.getFeedData(verify: true);
    if (!_ownsBody(scope)) return;
    final notice = _feedController.accountDetailNotice.value;
    SmartDialog.showToast(notice.isEmpty ? '账号详情已更新' : notice);
  }

  Widget _buildPinWidget() {
    final scope = _currentBody;
    return SliverPinnedBoxAdapter(
      child: Container(
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: Text('共 ${_feedController.replyNum} 回复'),
                  ),
                  Obx(
                    () => SegmentedButton<ReplySortType>(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: const VisualDensity(
                          horizontal: -4,
                          vertical: -4,
                        ),
                      ),
                      showSelectedIcon: false,
                      selected: <ReplySortType>{
                        _feedController.replySelection.value,
                      },
                      segments:
                          _shirtSizeOptions.map<ButtonSegment<ReplySortType>>((
                        (ReplySortType, String) shirt,
                      ) {
                        return ButtonSegment<ReplySortType>(
                          value: shirt.$1,
                          label: Text(shirt.$2),
                        );
                      }).toList(),
                      onSelectionChanged: (Set<ReplySortType> newSelection) {
                        if (!_ownsBody(scope)) return;
                        _feedController.replySelection.value =
                            newSelection.first;
                        switch (newSelection.first) {
                          case ReplySortType.def:
                            _feedController.listType = 'lastupdate_desc';
                            _feedController.fromFeedAuthor = 0;
                            break;
                          case ReplySortType.dateline:
                            _feedController.listType = 'dateline_desc';
                            _feedController.fromFeedAuthor = 0;
                            break;
                          case ReplySortType.hot:
                            _feedController.listType = 'popular';
                            _feedController.fromFeedAuthor = 0;
                            break;
                          case ReplySortType.author:
                            _feedController.listType = '';
                            _feedController.fromFeedAuthor = 1;
                            break;
                        }
                        _refreshKey.currentState?.show();
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }

  Future<void> _onReply(
    ReplyType type,
    dynamic id,
    dynamic uname,
    dynamic fid,
  ) async {
    final scope = _currentBody;
    if (!_ownsBody(scope) || !GlobalData().isLogin) return;
    Navigator.of(context)
        .push(
      GetDialogRoute(
        pageBuilder: (buildContext, animation, secondaryAnimation) {
          return ReplyPage(type: type, username: uname, id: id);
        },
        transitionDuration: const Duration(milliseconds: 500),
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.linear;

          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    )
        .then((result) {
      if (_ownsBody(scope) && result != null && result['data'] != null) {
        _feedController.updateReply(
          type == ReplyType.reply,
          result['data'] as Datum,
          id,
          fid,
        );
      }
    });

    // dynamic result = await showModalBottomSheet<dynamic>(
    //   context: context,
    //   isScrollControlled: true,
    //   builder: (context) => ReplyDialog(
    //     type: type,
    //     username: uname,
    //     id: id,
    //   ),
    // );
    // if (result != null && result['data'] != null) {
    //   _feedController.updateReply(
    //     type == ReplyType.reply,
    //     result['data'] as Datum,
    //     id,
    //     fid,
    //   );
    // }
  }

  Widget _buildDeferredReplyPrompt(
    LoadingState replyState, {
    bool hasReplies = false,
  }) {
    final scope = _currentBody;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.forum_outlined),
          const SizedBox(height: 12),
          Text(hasReplies ? '评论加载已暂停' : '评论尚未加载'),
          const SizedBox(height: 8),
          Text(
            GStorage.szlmId.trim().isEmpty
                ? '未导入数盟 ID，加载评论可能需要验证码验证。点击下方按钮后再加载。'
                : '评论加载已暂停，请点击下方按钮重新加载。',
            textAlign: TextAlign.center,
          ),
          if (replyState is Error) ...[
            const SizedBox(height: 8),
            Text(replyState.errMsg, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () {
              if (_ownsBody(scope)) _feedController.loadReplies();
            },
            icon: const Icon(Icons.download_outlined),
            label: const Text('加载评论并验证'),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedReply(LoadingState replyState) {
    final scope = _currentBody;
    if (!_ownsBody(scope)) return const SliverToBoxAdapter();
    if (_feedController.repliesDeferred.value && replyState is! Success) {
      return SliverToBoxAdapter(child: _buildDeferredReplyPrompt(replyState));
    }
    switch (replyState) {
      case Empty():
        return SliverToBoxAdapter(
          child: Container(
            height: 80,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(10.0),
            child: const Text('暂无内容'),
          ),
        );
      case Error():
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(replyState.errMsg, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () {
                    if (_ownsBody(scope)) _feedController.loadReplies();
                  },
                  child: const Text('重新加载评论'),
                ),
              ],
            ),
          ),
        );
      case Success():
        List<Datum> dataList = replyState.response;
        return SliverPadding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
          sliver: SliverList.separated(
            itemCount: dataList.length + 1,
            itemBuilder: (_, index) {
              if (!_ownsBody(scope)) return const SizedBox.shrink();
              if (index == dataList.length) {
                if (!_feedController.repliesDeferred.value &&
                    !_feedController.isEnd &&
                    !_feedController.isLoading) {
                  _feedController.setFooterState(LoadingState.loading());
                  _feedController.onGetData(false);
                }
                return Obx(
                  () => _feedController.repliesDeferred.value
                      ? _buildDeferredReplyPrompt(
                          _feedController.footerState.value,
                          hasReplies: true,
                        )
                      : footerWidget(_feedController.footerState.value, () {
                          if (!_ownsBody(scope)) return;
                          _feedController
                            ..isEnd = false
                            ..setFooterState(LoadingState.loading())
                            ..onGetData(false);
                        }),
                );
              } else {
                return FeedReplyCard(
                  data: dataList[index],
                  isTopReply: _feedController.topReply != null &&
                      index == 0 &&
                      _feedController.listType == 'lastupdate_desc',
                  onBlock: (uid, id) {
                    if (_ownsBody(scope)) _feedController.onBlockReply(uid, id);
                  },
                  onReply: (id, uname, fid) {
                    if (_ownsBody(scope) && GlobalData().isLogin) {
                      _onReply(ReplyType.reply, id, uname, fid);
                    }
                  },
                  onDelete: (id, fid) {
                    if (!_ownsBody(scope)) return;
                    _feedController.postLikeDeleteFollow(
                      id,
                      fid,
                      isReply: true,
                    );
                  },
                  onLike: (id, like) {
                    if (!_ownsBody(scope)) return;
                    _feedController.onLike(id, like, isReply: true);
                  },
                );
              }
            },
            separatorBuilder: (_, index) => const Divider(height: 1),
          ),
        );
    }
    return SliverToBoxAdapter(
      child: Container(
        height: 80,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(10.0),
        child: const CircularProgressIndicator(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: Obx(() {
        final scope = _currentBody;
        return _ownsBody(scope) && GlobalData().isLogin
            ? SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 2),
                  end: const Offset(0, 0),
                ).animate(
                  CurvedAnimation(
                    parent: _fabAnimationCtr!,
                    curve: Curves.easeInOut,
                  ),
                ),
                child: FloatingActionButton(
                  heroTag: null,
                  tooltip: '回复',
                  onPressed: () {
                    if (!_ownsBody(scope) || !GlobalData().isLogin) return;
                    _onReply(
                      ReplyType.feed,
                      _feedController.id,
                      _feedController.feedUsername,
                      null,
                    );
                  },
                  child: const Icon(Icons.reply),
                ),
              )
            : const SizedBox();
      }),
      appBar: PreferredSize(
        preferredSize: const Size(double.infinity, 56),
        child: Obx(() {
          final scope = _currentBody;
          final success = _ownsBody(scope) ? _feedController.ownedFeed : null;
          return AppBar(
            titleSpacing: 0,
            title: StreamBuilder(
              stream: _titleStreamC.stream,
              builder: (context, snapshot) {
                return GestureDetector(
                  onTap: () {
                    if (_ownsBody(scope) &&
                        _scrollController.hasClients &&
                        _scrollController.offset != 0) {
                      _scrollController.animToTop();
                    }
                  },
                  child: Container(
                    color: Colors.transparent,
                    width: double.infinity,
                    child: snapshot.data == true &&
                            _ownsBody(scope) &&
                            success != null
                        ? header(
                            context,
                            success.response,
                            true,
                            isHeader: true,
                          )
                        : _ownsBody(scope) && success != null
                            ? Text(
                                _feedController.feedTypeName ?? '动态',
                                textAlign: Platform.isIOS
                                    ? TextAlign.center
                                    : TextAlign.start,
                              )
                            : null,
                  ),
                );
              },
            ),
            actions: success != null
                ? [
                    if (success.isPublic && GlobalData().isLogin)
                      IconButton(
                        tooltip: '账号信息暂不可用',
                        onPressed: _feedController.isLoadingDetail.value
                            ? null
                            : _showAccountDetailStatus,
                        icon: _feedController.isLoadingDetail.value
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.info_outline),
                      ),
                    PopupMenuButton(
                      onSelected: (FeedMenuItem item) {
                        if (!_ownsBody(scope)) return;
                        final current = _feedController.ownedFeed;
                        if (current == null) return;
                        switch (item) {
                          case FeedMenuItem.Copy:
                            Utils.copyText(
                              Utils.getShareUrl(_id, ShareType.feed),
                            );
                            break;
                          case FeedMenuItem.Share:
                            Share.share(
                              Utils.getShareText(
                                _id,
                                ShareType.feed,
                                title: (current.response as Datum).title,
                                message: (current.response as Datum).message,
                              ),
                            );
                            break;
                          case FeedMenuItem.Fav:
                            if (_feedController.isFav) {
                              GStorage.onDeleteFeed(_id, isHistory: false);
                            } else {
                              _feedController.onFav();
                            }
                            _feedController.isFav = !_feedController.isFav;
                            break;
                          case FeedMenuItem.Block:
                            GStorage.onBlock(
                              _feedController.feedUid.toString(),
                              isDelete: _feedController.isBlocked,
                            );
                            _feedController.isBlocked =
                                !_feedController.isBlocked;
                            break;
                          case FeedMenuItem.Source:
                            _toggleSource();
                            break;
                          case FeedMenuItem.Report:
                            if (Utils.isSupportWebview()) {
                              Utils.report(_id, ReportType.Feed);
                            } else {
                              SmartDialog.showToast('当前平台暂不支持此功能');
                            }
                            break;
                        }
                      },
                      itemBuilder: (BuildContext context) => !_ownsBody(scope)
                          ? <PopupMenuEntry<FeedMenuItem>>[]
                          : FeedMenuItem.values
                              .where(
                                (item) =>
                                    item != FeedMenuItem.Source ||
                                    _currentBody?.offersSource == true,
                              )
                              .map(
                                (item) => PopupMenuItem<FeedMenuItem>(
                                  value: item,
                                  child: item == FeedMenuItem.Fav
                                      ? Text(
                                          _feedController.isFav ? '取消收藏' : '收藏')
                                      : item == FeedMenuItem.Block
                                          ? Text(
                                              _feedController.isBlocked
                                                  ? '取消屏蔽'
                                                  : '屏蔽',
                                            )
                                          : item == FeedMenuItem.Source
                                              ? Text(_showSource
                                                  ? '格式化显示'
                                                  : '查看原文')
                                              : Text(item.label),
                                ),
                              )
                              .toList(),
                    ),
                  ]
                : null,
          );
        }),
      ),
      body: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          if (_pendingScrollTarget != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _restoreScrollPosition();
            });
          }
          return false;
        },
        child: Obx(() {
          // Subscribe here, not only inside the later lazy article builder.
          final scope = _currentBody;
          final currentState = _feedController.feedState.value;
          final visibleState = currentState is Success && !_ownsBody(scope)
              ? LoadingState.error('账号已切换，请重新打开详情')
              : currentState;
          return visibleState is Success
              ? RefreshIndicator(
                  notificationPredicate: (notification) {
                    if (notification is ScrollStartNotification &&
                        notification.dragDetails != null) {
                      _pendingScrollTarget = null;
                    }
                    final double offset = notification.metrics.pixels;
                    if (offset > 50 && !_visibleTitle) {
                      _visibleTitle = true;
                      _titleStreamC.add(true);
                    } else if (offset <= 50 && _visibleTitle) {
                      _visibleTitle = false;
                      _titleStreamC.add(false);
                    }
                    return notification.depth == 0;
                  },
                  key: _refreshKey,
                  onRefresh: () async {
                    if (!_ownsBody(scope)) return;
                    _feedController.onReset();
                    await _feedController.onGetData();
                  },
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: [
                      _feedController.articleList.isNullOrEmpty
                          ? SliverToBoxAdapter(
                              child: _buildFeedContent(visibleState),
                            )
                          : _buildFeedContent(visibleState),
                      _buildPinWidget(),
                      _buildFeedReply(_feedController.loadingState.value),
                    ],
                  ),
                )
              : Center(
                  child: _buildFeedContent(visibleState),
                );
        }),
      ),
    );
  }
}
