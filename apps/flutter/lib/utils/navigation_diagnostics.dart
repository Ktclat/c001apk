import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class NavigationBuildIdentity {
  static const diagnostic = bool.fromEnvironment('APP_DIAGNOSTIC');
  static const checkout = String.fromEnvironment('APP_BUILD_SHA',
      defaultValue: 'unidentified-local');
  static const source = String.fromEnvironment('APP_SOURCE_SHA',
      defaultValue: 'unidentified-local');
  static const run =
      String.fromEnvironment('APP_BUILD_RUN', defaultValue: 'local');
  static String get mode => kReleaseMode
      ? 'release'
      : kProfileMode
          ? 'profile'
          : 'debug';
  static String get label =>
      '${diagnostic ? '显隐验证版 · ' : ''}${source != 'unidentified-local' && source.length > 12 ? source.substring(0, 12) : source} · $mode · CI $run';
}

/// Opt-in, bounded, process-local diagnostics. Never records content, account
/// identifiers, URLs, device identifiers or wall-clock timestamps. No I/O.
class NavigationDiagnostics {
  static final instance = NavigationDiagnostics();
  static const maxEvents = 60;
  bool recording = false;
  final Map<String, Object?> environment = {};
  final Map<String, int> counts = {};
  final List<Map<String, Object?>> events = [];
  int sequence = 0;

  void start() {
    counts.clear();
    events.clear();
    environment.remove('lastFeedPointer');
    environment.remove('lastFeedPosition');
    sequence = 0;
    recording = true;
  }

  void clear() {
    recording = false;
    counts.clear();
    events.clear();
    environment.remove('lastFeedPointer');
    environment.remove('lastFeedPosition');
    sequence = 0;
  }

  void rootConfiguration(
    MediaQueryData media,
    Size window, {
    required bool floatingSetting,
    required String policy,
    required String? policySuppression,
    required bool floatingActive,
    required bool rail,
    required int selectedRoot,
    required bool visible,
  }) {
    List<double> edge(EdgeInsets e) => [e.left, e.top, e.right, e.bottom];
    environment.addAll({
      'runtimeOS': Platform.operatingSystem,
      'rootWindowDp': [window.width, window.height],
      'mediaSizeDp': [media.size.width, media.size.height],
      'devicePixelRatio': media.devicePixelRatio,
      'viewPaddingLTRB': edge(media.viewPadding),
      'gestureInsetsLTRB': edge(media.systemGestureInsets),
      'viewInsetsLTRB': edge(media.viewInsets),
      'label12_5Scaled': media.textScaler.scale(12.5),
      'accessibleNavigation': media.accessibleNavigation,
      'disableAnimations': media.disableAnimations,
      'floatingSetting': floatingSetting,
      'floatingNavigationPolicy': policy,
      'policySuppressionReason': policySuppression,
      'floatingActive': floatingActive,
      'classicRail': rail,
      'selectedRoot': selectedRoot,
      'dockVisible': visible,
    });
  }

  void feedPointer(String tab, String event, String kind, double? dy) {
    if (!recording) return;
    final key = 'feed.$tab.pointer.$event';
    counts[key] = (counts[key] ?? 0) + 1;
    environment['lastFeedPointer'] = {
      'tab': tab,
      'event': event,
      'kind': kind,
      if (dy != null) 'deltaY': dy
    };
  }

  void feedPosition(String tab, ScrollPosition position) {
    if (!recording) return;
    final key = 'feed.$tab.positionChanged';
    counts[key] = (counts[key] ?? 0) + 1;
    environment['lastFeedPosition'] = {
      'tab': tab,
      'pixels': position.pixels,
      'minExtent': position.minScrollExtent,
      'maxExtent': position.maxScrollExtent,
      'userScrollDirection': position.userScrollDirection.name,
      'isScrolling': position.isScrollingNotifier.value
    };
  }

  void reveal(String reason) {
    dockVisibilityChanged(true);
    if (!recording) return;
    final key = 'reveal.$reason';
    counts[key] = (counts[key] ?? 0) + 1;
    events.add({
      'sequence': ++sequence,
      'stage': 'lifecycle',
      'decision': reason,
      'dockVisible': true
    });
    if (events.length > maxEvents) events.removeAt(0);
  }

  void dockVisibilityChanged(bool visible) {
    if (environment['dockVisible'] != visible) {
      environment['dockVisible'] = visible;
    }
  }

  void rootSelection(int index) => environment['selectedRoot'] = index;

  void homeSelection(int index, String type, int tabCount) {
    if (environment['selectedHomeIndex'] == index &&
        environment['selectedHomeTab'] == type &&
        environment['homeTabCount'] == tabCount) return;
    environment['selectedHomeIndex'] = index;
    environment['selectedHomeTab'] = type;
    environment['homeTabCount'] = tabCount;
  }

  void homeNotification(
      ScrollNotification n, int index, int selected, String type) {
    if (!recording) return;
    _event('home', n, index == selected ? 'forwarded' : 'inactive_home_tab', {
      'homeIndex': index,
      'selectedHomeIndex': selected,
      'homeTab': type,
    });
  }

  void rootNotification(
    ScrollNotification n,
    String decision, {
    required int page,
    required int selected,
    required bool userSession,
    required bool tickerEnabled,
    required bool? currentRoute,
    required bool visible,
    required double accumulated,
    double? consumed,
  }) {
    if (!recording) return;
    environment['dockVisible'] = visible;
    _event('root', n, decision, {
      'rootPage': page,
      'selectedRoot': selected,
      'userSession': userSession,
      'tickerEnabled': tickerEnabled,
      'currentRoute': currentRoute,
      'dockVisible': visible,
      'accumulatedDp': accumulated,
      if (consumed != null) 'consumedDp': consumed,
    });
  }

  void _event(String stage, ScrollNotification n, String decision,
      Map<String, Object?> details) {
    final vertical = n.metrics.axis == Axis.vertical;
    counts[stage] = (counts[stage] ?? 0) + 1;
    final key = '$stage.${vertical ? 'vertical' : 'horizontal'}.$decision';
    counts[key] = (counts[key] ?? 0) + 1;
    events.add({
      'sequence': ++sequence,
      'stage': stage,
      'event': n.runtimeType.toString(),
      'axis': n.metrics.axis.name,
      'depth': n.depth,
      'decision': decision,
      'pixels': n.metrics.pixels,
      'minExtent': n.metrics.minScrollExtent,
      'maxExtent': n.metrics.maxScrollExtent,
      if (n is ScrollUpdateNotification) 'rawDelta': n.scrollDelta,
      if (n is ScrollUpdateNotification)
        'hasDragDetails': n.dragDetails != null,
      if (n is ScrollStartNotification) 'hasDragDetails': n.dragDetails != null,
      if (n is UserScrollNotification) 'userDirection': n.direction.name,
      ...details,
    });
    if (events.length > maxEvents) events.removeAt(0);
  }

  Object? _jsonSafe(Object? value) {
    if (value is double && !value.isFinite) return value.toString();
    if (value is List) return value.map(_jsonSafe).toList();
    if (value is Map) {
      return value
          .map((key, value) => MapEntry(key.toString(), _jsonSafe(value)));
    }
    return value;
  }

  String report() => const JsonEncoder.withIndent('  ').convert(_jsonSafe({
        'schema': 1,
        'build': {
          'source': NavigationBuildIdentity.source,
          'checkout': NavigationBuildIdentity.checkout,
          'run': NavigationBuildIdentity.run,
          'mode': NavigationBuildIdentity.mode,
          'standaloneDiagnostic': NavigationBuildIdentity.diagnostic
        },
        'recording': recording,
        'scope':
            'Local scroll signals only; not proof of a physical touch or successful device behavior.',
        'environmentScope':
            'Latest observed root configuration, not a frozen stop-time snapshot.',
        'environment': environment,
        'countsSinceStart': counts,
        'lastEvents': events,
      }));
}
