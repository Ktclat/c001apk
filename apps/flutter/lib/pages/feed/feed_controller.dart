import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';

import '../../logic/accounts/account_store.dart';
import '../../logic/reading/detail_body_snapshot.dart';
import '../../logic/reading/detail_parse_job.dart';
import '../../logic/reading/markdown_content.dart';
import '../../logic/model/fav_history/fav_history.dart';
import '../../logic/model/feed/datum.dart';
import '../../logic/model/feed/user_action.dart';
import '../../logic/model/feed_article/feed_article.dart';
import '../../logic/network/network_repo.dart';
import '../../logic/network/api_failure.dart';
import '../../logic/state/loading_state.dart';
import '../../pages/common/common_controller.dart';
import '../../pages/feed/feed_page.dart' show ReplySortType;
import '../../utils/extensions.dart';
import '../../utils/storage_util.dart';
import '../../utils/global_data.dart';

class FeedController extends CommonController {
  FeedController({required this.id, required this.recordHistory});
  final String id;
  final bool recordHistory;

  String listType = 'lastupdate_desc';
  final int _discussMode = 1;
  final String _feedType = 'feed';
  final int _blockStatus = 0;
  int fromFeedAuthor = 0;

  String? feedTypeName;
  int? feedUid;
  String? feedUsername;
  int? replyNum;

  List<FeedArticle>? articleList;
  List<String>? articleImgList;

  Datum? topReply;
  Datum? _replyMe;

  Rx<LoadingState> feedState = LoadingState.loading().obs;
  final accountDetailNotice = ''.obs;
  final isLoadingDetail = false.obs;
  bool isFav = false;
  bool isBlocked = false;

  final bodySnapshot = Rx<DetailBodySnapshot?>(null);
  final _sourcePositions = <String, RawSourcePosition>{};
  RawSourcePosition sourcePositionFor(String key) =>
      _sourcePositions.putIfAbsent(key, RawSourcePosition.new);
  final _bodyJob = DetailParseJob<Map<String, MarkdownContent>>();

  /// GlobalData changes before AccountStore's asynchronous persistence/notifier.
  /// Every action must consult the actual current owner, not only that notifier.
  Success? get ownedFeed {
    final snapshot = bodySnapshot.value;
    final state = feedState.value;
    return !isClosed &&
            state is Success &&
            snapshot != null &&
            snapshot.belongsTo(GlobalData().uid, GlobalData().sessionGeneration)
        ? state
        : null;
  }

  void _accountChanged() {
    _bodyJob.cancel();
    _sourcePositions.clear();
    bodySnapshot.value = null;
    articleList = null;
    articleImgList = null;
    topReply = null;
    _replyMe = null;
    feedTypeName = null;
    feedUid = null;
    feedUsername = null;
    replyNum = null;
    isFav = false;
    isBlocked = false;
    accountDetailNotice.value = '';
    feedState.value = LoadingState.error('账号已切换，请重新打开详情');
    loadingState.value = LoadingState.empty();
    footerState.value = LoadingState.empty();
  }

  void _prepareBody(Datum data, List<FeedArticle> articles,
      {required bool structured}) {
    final global = GlobalData();
    final snapshot = DetailBodySnapshot(
      account: global.uid,
      generation: global.sessionGeneration,
      feedId: id,
      originalBody:
          structured ? data.messageRawOutput.orEmpty : data.message.orEmpty,
      rawFields: !structured
          ? {'message': data.message}
          : {
              'title': data.title,
              'message_cover': data.messageCover,
              'message_raw_output': data.messageRawOutput,
            },
      sources: articles.isEmpty
          ? {'body': data.message.orEmpty}
          : {
              for (var i = 0; i < articles.length; i++) ...{
                if (articles[i].type == 'text')
                  'article:$i': articles[i].message.orEmpty,
                if (articles[i].type == 'title')
                  'article:$i:title': articles[i].title.orEmpty,
                if (articles[i].type == 'shareUrl')
                  'article:$i:label': articles[i].title.orEmpty,
                if (articles[i].type == 'image' &&
                    articles[i].description != null)
                  'article:$i:description': articles[i].description!,
              },
            },
    );
    if (bodySnapshot.value?.sameBody(snapshot) == true) return;
    _sourcePositions.clear();
    bodySnapshot.value = snapshot;
    unawaited(
      _bodyJob.run(parseDetailBodies, snapshot.sources).then((result) {
        if (isClosed ||
            !identical(bodySnapshot.value, snapshot) ||
            !snapshot.belongsTo(
              GlobalData().uid,
              GlobalData().sessionGeneration,
            )) {
          return;
        }
        bodySnapshot.value = snapshot.prepared(
          result ??
              {
                for (final entry in snapshot.sources.entries)
                  entry.key: MarkdownContent.fallback(
                    entry.value,
                    '排版超时或暂不可用，已保留完整原文',
                  ),
              },
        );
      }),
    );
  }

  Rx<ReplySortType> replySelection = ReplySortType.def.obs;

  final repliesDeferred = GStorage.szlmId.trim().isEmpty.obs;
  String _replyDeviceId = GStorage.szlmId.trim();

  void _syncReplyIdentity() {
    final current = GStorage.szlmId.trim();
    if (current != _replyDeviceId) {
      _replyDeviceId = current;
      repliesDeferred.value = current.isEmpty;
    }
  }

  @override
  Future<void> onGetData([bool isRefresh = true]) async {
    // All automatic paths (detail, refresh, sort and pagination) share this
    // gate. Only the comment section's explicit action opts into verification.
    _syncReplyIdentity();
    if (repliesDeferred.value || isLoading) return;
    final generation = GlobalData().sessionGeneration;
    final device = GStorage.xAppDevice;
    await super.onGetData(isRefresh);
    if (isClosed) return;
    if (generation != GlobalData().sessionGeneration ||
        device != GStorage.xAppDevice) {
      _syncReplyIdentity();
      repliesDeferred.value = true;
      loadingState.value = LoadingState.error('账号或设备已切换，请重新加载评论');
      footerState.value = LoadingState.empty();
      super.onReset();
      footerState.value = LoadingState.empty();
      return;
    }
    final result = isRefresh ? loadingState.value : footerState.value;
    if (result is Error && GStorage.szlmId.trim().isEmpty) {
      repliesDeferred.value = true;
    }
  }

  @override
  void onReset() {
    _syncReplyIdentity();
    if (repliesDeferred.value) return;
    super.onReset();
  }

  Future<void> loadReplies() async {
    if (isLoading) return;
    _syncReplyIdentity();
    final previous = loadingState.value;
    final device = GStorage.xAppDevice;
    final generation = GlobalData().sessionGeneration;
    repliesDeferred.value = false;
    onReset();
    if (previous is! Success) setLoadingState(LoadingState.loading());
    await onGetData();
    if (!isClosed &&
        generation == GlobalData().sessionGeneration &&
        device == GStorage.xAppDevice &&
        previous is Success &&
        loadingState.value is Error) {
      // A cancelled/rejected retry must not discard already readable comments.
      footerState.value = loadingState.value;
      loadingState.value = previous;
    }
  }

  void setFeedState(LoadingState feedState) {
    this.feedState.value = feedState;
  }

  @override
  Future<LoadingState> customGetData() {
    return NetworkRepo.getFeedReply(
      id: id,
      listType: listType,
      page: page,
      firstItem: firstItem,
      lastItem: lastItem,
      discussMode: _discussMode,
      feedType: _feedType,
      blockStatus: _blockStatus,
      fromFeedAuthor: fromFeedAuthor,
    );
  }

  Future<void> getFeedData({bool verify = false}) async {
    if (isLoadingDetail.value) return;
    final previous = feedState.value;
    final owner = (GlobalData().uid, GlobalData().sessionGeneration);
    isLoadingDetail.value = true;
    try {
      await _loadFeedData(verify: verify);
      if (isClosed ||
          owner != (GlobalData().uid, GlobalData().sessionGeneration)) {
        return;
      }
      final result = feedState.value;
      if (verify && result is! Success) {
        accountDetailNotice.value =
            result is Error ? result.errMsg : '账号详情暂不可用，请稍后重试';
        if (previous is Success) feedState.value = previous;
      } else if (result is Success) {
        accountDetailNotice.value =
            result.isPublic ? '正文可正常阅读，当前账号的点赞状态暂不可用。' : '';
      }
    } finally {
      isLoadingDetail.value = false;
    }
  }

  Future<void> _loadFeedData({required bool verify}) async {
    final owner = (GlobalData().uid, GlobalData().sessionGeneration);
    LoadingState<dynamic> response = await NetworkRepo.getFeedDetail(
      id: id,
      verify: verify,
    );
    if (isClosed) return;
    if (owner != (GlobalData().uid, GlobalData().sessionGeneration)) {
      _accountChanged();
      return;
    }
    if (response is Success) {
      Datum data = (response.response as Datum);
      List<FeedArticle> nextArticles = [];
      var structured = false;
      List<String> nextImages = [];
      try {
        if (!data.messageRawOutput.isNullOrEmpty &&
            data.messageRawOutput != 'null') {
          List<dynamic> jsonList = jsonDecode(data.messageRawOutput!);
          structured = jsonList.isNotEmpty;
          nextArticles = jsonList
              .map((json) => FeedArticle.fromJson(json))
              .where(
                (item) => ['text', 'image', 'shareUrl'].contains(item.type),
              )
              .toList();
        }
      } catch (error) {
        feedState.value = LoadingState.error(
          ApiFailure.fromError(error).message,
        );
        return;
      }
      // A public normal feed also has a summary title. Only attach article
      // decoration when there is structured body content to render.
      if (nextArticles.isNotEmpty) {
        if (!data.title.isNullOrEmpty) {
          nextArticles.insert(0, FeedArticle(type: 'title', title: data.title));
        }
        if (!data.messageCover.isNullOrEmpty) {
          nextArticles.insert(
            0,
            FeedArticle(type: 'image', url: data.messageCover),
          );
        }
        nextImages = nextArticles
            .where((item) => item.type == 'image')
            .map((item) => item.url.orEmpty)
            .toList();
      }
      _prepareBody(data, nextArticles, structured: structured);
      articleList = nextArticles;
      articleImgList = nextImages;
      topReply = data.topReplyRows?.firstOrNull;
      _replyMe = data.replyMeRows?.firstOrNull;
      feedUsername = data.userInfo?.username;
      feedUid = data.uid;
      feedTypeName = data.feedTypeName;
      replyNum = data.replynum;
      onGetData();

      isFav = GStorage.checkFav(id);
      isBlocked = GStorage.checkUser(feedUid.toString());
      // todo: check
      if (recordHistory && !GStorage.checkHistory(id)) {
        GStorage.historyFeed.put(id, getFeed(data));
      }
    }
    feedState.value = response;
  }

  void onFav() {
    final current = ownedFeed;
    if (current == null) return;
    Datum data = current.response;
    GStorage.favFeed.put(id, getFeed(data));
  }

  FavHistoryItem getFeed(Datum data) {
    return FavHistoryItem(
      id: data.id.toString(),
      uid: data.uid.toString(),
      username: data.userInfo?.username,
      userAvatar: data.userInfo?.userAvatar,
      message: (data.message ?? '').length <= 150
          ? data.message
          : data.message!.substring(0, 150),
      device: data.deviceTitle,
      dateline: data.dateline.toString(),
      time: DateTime.now().microsecondsSinceEpoch,
    );
  }

  @override
  void onInit() {
    super.onInit();
    AccountStore.changes.addListener(_accountChanged);
    getFeedData();
  }

  @override
  void onClose() {
    AccountStore.changes.removeListener(_accountChanged);
    _bodyJob.dispose();
    _sourcePositions.clear();
    bodySnapshot.value = null;
    super.onClose();
  }

  void onBlockReply(dynamic uid, dynamic id) {
    if (ownedFeed == null || loadingState.value is! Success) return;
    List<Datum> replyList = (loadingState.value as Success).response;
    if (id != null) {
      replyList = replyList.map((reply) {
        if (reply.id == id) {
          return reply
            ..replyRows =
                reply.replyRows!.where((reply) => reply.uid != uid).toList();
        } else {
          return reply;
        }
      }).toList();
    } else {
      replyList = replyList.where((reply) => reply.uid != uid).toList();
    }
    loadingState.value = LoadingState.success(replyList);
  }

  @override
  List<Datum>? handleResponse(List<Datum> dataList) {
    List<Datum> filterList = dataList;
    if (page == 1 && listType == 'lastupdate_desc') {
      filterList = [
            if (topReply != null) topReply!,
            if (_replyMe != null) _replyMe!
          ] +
          filterList;
    }
    List<String> userBlackList = GStorage.blackList.get(
      BlackListBoxKey.userBlackList,
      defaultValue: <String>[],
    );
    return filterList
        .map(
          (data) => data
            ..replyRows = !data.replyRows.isNullOrEmpty
                ? data.replyRows!
                    .where(
                      (reply) => !userBlackList.contains(reply.uid.toString()),
                    )
                    .toList()
                : null,
        )
        .toList();
  }

  void updateReply(bool isReply, Datum data, dynamic id, dynamic fid) {
    List<Datum> replyList = loadingState.value is Success
        ? (loadingState.value as Success).response
        : [];
    if (isReply) {
      replyList = replyList.map((reply) {
        if (reply.id == (fid ?? id)) {
          return reply..replyRows = (reply.replyRows ?? []) + [data];
        } else {
          return reply;
        }
      }).toList();
    } else {
      replyList.insert(topReply == null ? 0 : 1, data);
    }
    loadingState.value = LoadingState.success(replyList);
  }

  @override
  Future<void> onLike(
    dynamic id,
    dynamic like, {
    bool isFeed = false,
    bool isReply = false,
    bool Function()? isCurrent,
  }) async {
    final expected = bodySnapshot.value;
    if (ownedFeed == null || expected == null) return;
    bool current() {
      final actual = bodySnapshot.value;
      return ownedFeed != null &&
          actual != null &&
          expected.sameBody(actual) &&
          (isCurrent?.call() ?? true);
    }

    await super
        .onLike(id, like, isFeed: isFeed, isReply: isReply, isCurrent: current);
  }

  @override
  bool handleLike(dynamic like, dynamic likenum) {
    final current = ownedFeed;
    if (current == null) return true; // Consume, do not mutate reply state.
    Datum data = current.response;
    final isPublic = current.isPublic;
    feedState.value = Success(
      data
        ..likenum = likenum
        ..userAction = UserAction(like: like == 1 ? 0 : 1),
      isPublic: isPublic,
    );
    return true;
  }
}
