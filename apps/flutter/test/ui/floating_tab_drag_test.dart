import 'dart:ui' show SemanticsAction, Tristate;

import 'package:c001apk_flutter/components/floating_tab_bar.dart';
import 'package:c001apk_flutter/components/navigation_tab_scrubber.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _DockHarness extends StatefulWidget {
  const _DockHarness({
    super.key,
    this.direction = TextDirection.ltr,
    this.width = 268,
    this.scale = 1,
    this.reduceMotion = false,
    this.ignore = false,
    this.disabledMiddle = false,
    this.standard = false,
    this.padding = EdgeInsets.zero,
  });

  final TextDirection direction;
  final double width;
  final double scale;
  final bool reduceMotion;
  final bool ignore;
  final bool disabledMiddle;
  final bool standard;
  final EdgeInsets padding;

  @override
  State<_DockHarness> createState() => _DockHarnessState();
}

class _DockHarnessState extends State<_DockHarness> {
  int selected = 0;
  final calls = <int>[];

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            padding: widget.padding,
            viewPadding: widget.padding,
            textScaler: TextScaler.linear(widget.scale),
            disableAnimations: widget.reduceMotion,
            accessibleNavigation: widget.reduceMotion,
          ),
          child: Directionality(
            textDirection: widget.direction,
            child: Scaffold(
              body: Center(
                child: IgnorePointer(
                  ignoring: widget.ignore,
                  child: Builder(builder: (context) {
                    final destinations = [
                      const NavigationDestination(
                          key: ValueKey('standard-tab-Home'),
                          icon: Icon(Icons.home_outlined),
                          label: 'Home'),
                      NavigationDestination(
                          key: const ValueKey('standard-tab-Follow'),
                          enabled: !widget.disabledMiddle,
                          icon: const Icon(Icons.favorite_outline),
                          label: 'Follow'),
                      const NavigationDestination(
                          key: ValueKey('standard-tab-My'),
                          icon: Icon(Icons.person_outline),
                          label: 'My'),
                    ];
                    void select(int value) => setState(() {
                          calls.add(value);
                          selected = value;
                        });
                    if (widget.standard) {
                      return SizedBox(
                        width: widget.width,
                        child: NavigationTabScrubber(
                          destinations: destinations,
                          selectedIndex: selected,
                          onDestinationSelected: select,
                          contentPadding: MediaQuery.paddingOf(context),
                          child: NavigationBar(
                            destinations: destinations,
                            selectedIndex: selected,
                            onDestinationSelected: select,
                          ),
                        ),
                      );
                    }
                    return FloatingTabBar(
                      dockWidth: widget.width,
                      height: FloatingTabBar.heightFor(context),
                      destinations: destinations,
                      selectedIndex: selected,
                      onDestinationSelected: select,
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      );
}

Finder hit(String label) => find.byKey(ValueKey('floating-tab-hit-$label'));
_DockHarnessState _state(WidgetTester tester) =>
    tester.state<_DockHarnessState>(find.byType(_DockHarness));

void main() {
  testWidgets('one held drag selects every tab and reverses across rebuilds',
      (tester) async {
    await tester.pumpWidget(const _DockHarness());
    final home = tester.getCenter(hit('Home'));
    final follow = tester.getCenter(hit('Follow'));
    final my = tester.getCenter(hit('My'));
    final gesture = await tester.startGesture(home);
    await gesture.moveTo(follow);
    await tester.pump();
    expect(_state(tester).calls, [1]);
    await gesture.moveTo(my);
    await tester.pump();
    expect(_state(tester).calls, [1, 2]);
    await gesture.moveBy(const Offset(5, 0));
    await gesture.moveBy(const Offset(-5, 0));
    await tester.pump();
    expect(_state(tester).calls, [1, 2],
        reason: 'No repeated reselect actions');
    await gesture.moveTo(follow);
    await tester.pump();
    await gesture.moveTo(home);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_state(tester).calls, [1, 2, 1, 0]);
    expect(_state(tester).selected, 0);
  });

  testWidgets('rapid reversal before rebuild uses the latest gesture selection',
      (tester) async {
    await tester.pumpWidget(const _DockHarness());
    final home = tester.getCenter(hit('Home'));
    final gesture = await tester.startGesture(home);
    await gesture.moveTo(tester.getCenter(hit('Follow')));
    await gesture.moveTo(home);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_state(tester).calls, [1, 0]);
  });

  testWidgets('tap and tap-again behavior is retained without drag duplicates',
      (tester) async {
    await tester.pumpWidget(const _DockHarness());
    await tester.tap(hit('Home'));
    await tester.tap(hit('My'));
    await tester.pumpAndSettle();
    await tester.tap(hit('My'));
    await tester.pumpAndSettle();
    expect(_state(tester).calls, [0, 2, 2]);
    final gesture = await tester.startGesture(tester.getCenter(hit('My')));
    await gesture.moveBy(const Offset(-23, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_state(tester).calls, [0, 2, 2]);
  });

  testWidgets('vertical and below-slop gestures do not select another tab',
      (tester) async {
    await tester.pumpWidget(const _DockHarness());
    final home = tester.getCenter(hit('Home'));
    var gesture = await tester.startGesture(home);
    await gesture.moveBy(const Offset(3, -100));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_state(tester).calls, isEmpty);
    // A small movement is still an ordinary tap on its original target.
    gesture = await tester.startGesture(home);
    await gesture.moveBy(const Offset(2, 2));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_state(tester).calls, [0]);
  });

  testWidgets('vertical exit pauses scrub; reentry and edge clamping work',
      (tester) async {
    await tester.pumpWidget(const _DockHarness());
    final gesture = await tester.startGesture(tester.getCenter(hit('Home')));
    final follow = tester.getCenter(hit('Follow'));
    final my = tester.getCenter(hit('My'));
    await gesture.moveTo(follow);
    await tester.pump();
    await gesture.moveTo(my + const Offset(0, -100));
    await tester.pump();
    expect(_state(tester).calls, [1]);
    await gesture.moveTo(my);
    await tester.pump();
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump();
    expect(_state(tester).calls, [1, 2]);
    await gesture.cancel();
    await tester.pumpAndSettle();
    await tester.tap(hit('Home'));
    await tester.pumpAndSettle();
    expect(_state(tester).calls, [1, 2, 0]);
  });

  for (final direction in TextDirection.values) {
    testWidgets('scrub uses local coordinates in $direction and large text',
        (tester) async {
      await tester
          .pumpWidget(_DockHarness(direction: direction, width: 320, scale: 2));
      final gesture = await tester.startGesture(tester.getCenter(hit('Home')));
      await gesture.moveTo(tester.getCenter(hit('Follow')));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(hit('My')));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_state(tester).calls, [1, 2]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('resize cancels a held scrub until a new gesture',
      (tester) async {
    const key = ValueKey('harness');
    await tester.pumpWidget(const _DockHarness(key: key));
    final gesture = await tester.startGesture(tester.getCenter(hit('Home')));
    await gesture.moveTo(tester.getCenter(hit('Follow')));
    await tester.pump();
    await tester.pumpWidget(const _DockHarness(key: key, width: 320));
    await gesture.moveTo(tester.getCenter(hit('My')));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_state(tester).calls, [1]);
    await tester.dragFrom(
        tester.getCenter(hit('Follow')), const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(_state(tester).calls, [1, 2]);
  });

  testWidgets(
      'resize or direction change before drag recognition cancels selection',
      (tester) async {
    const key = ValueKey('harness');
    await tester.pumpWidget(const _DockHarness(key: key));
    var gesture = await tester.startGesture(tester.getCenter(hit('Home')));
    await tester.pumpWidget(const _DockHarness(key: key, width: 320));
    await gesture.moveTo(tester.getCenter(hit('My')));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_state(tester).calls, isEmpty);
    gesture = await tester.startGesture(tester.getCenter(hit('Home')));
    await tester.pumpWidget(
        const _DockHarness(key: key, width: 320, direction: TextDirection.rtl));
    await gesture.moveTo(tester.getCenter(hit('Follow')));
    await gesture.moveTo(tester.getCenter(hit('My')));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_state(tester).calls, isEmpty);
    gesture = await tester.startGesture(tester.getCenter(hit('Home')));
    await tester.pumpWidget(const SizedBox());
    await gesture.moveBy(const Offset(100, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('hidden dock cannot begin scrubbing or tapping', (tester) async {
    await tester.pumpWidget(const _DockHarness(ignore: true));
    final gesture = await tester.startGesture(tester.getCenter(hit('Home')));
    await gesture.moveTo(tester.getCenter(hit('My')));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_state(tester).calls, isEmpty);
  });

  testWidgets('disabled target is skipped by scrub and tap', (tester) async {
    await tester.pumpWidget(const _DockHarness(disabledMiddle: true));
    await tester.tap(hit('Follow'));
    final gesture = await tester.startGesture(tester.getCenter(hit('Home')));
    await gesture.moveTo(tester.getCenter(hit('Follow')));
    await tester.pump();
    expect(_state(tester).calls, isEmpty);
    await gesture.moveTo(tester.getCenter(hit('My')));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_state(tester).calls, [2]);
  });

  for (final direction in TextDirection.values) {
    testWidgets('standard bar scrubs actual safe-area targets in $direction',
        (tester) async {
      await tester.pumpWidget(_DockHarness(
        standard: true,
        direction: direction,
        width: 350,
        padding: const EdgeInsets.fromLTRB(48, 8, 12, 32),
      ));
      Offset target(String label) =>
          tester.getCenter(find.byKey(ValueKey('standard-tab-$label')));
      final bar = tester.getRect(find.byType(NavigationBar));
      final gesture = await tester.startGesture(target('Home'));
      await gesture.moveTo(target('Follow'));
      await tester.pump();
      await gesture.moveTo(target('My'));
      await tester.pump();
      await gesture.moveTo(target('Follow'));
      await tester.pump();
      await gesture.moveTo(target('Home'));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_state(tester).calls, [1, 2, 1, 0]);
      expect(tester.getRect(find.byType(NavigationBar)), bar);
      for (final start in [
        Offset(bar.left + 60, bar.bottom - 5),
        Offset(bar.left + 60, bar.top + 2),
        Offset(bar.left + 5, bar.center.dy),
      ]) {
        final outside = await tester.startGesture(start);
        await outside.moveTo(target('My'));
        await outside.up();
        await tester.pumpAndSettle();
        expect(_state(tester).calls, [1, 2, 1, 0],
            reason: 'SafeArea-only starts must not become scrubbing');
      }
      await tester.tap(find.byKey(const ValueKey('standard-tab-My')));
      await tester.pumpAndSettle();
      expect(_state(tester).calls, [1, 2, 1, 0, 2]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('semantics and keyboard targets survive reduced-motion scrubbing',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(const _DockHarness(reduceMotion: true));
      await tester.dragFrom(
          tester.getCenter(hit('Home')), const Offset(170, 0));
      await tester.pumpAndSettle();
      expect(_state(tester).selected, 2);
      final node = tester.getSemantics(find.bySemanticsLabel('My'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(
          node.getSemanticsData().flagsCollection.isSelected, Tristate.isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_state(tester).calls.last, 0);
      expect(find.bySemanticsLabel('Home'), findsOneWidget);
      expect(find.bySemanticsLabel('Follow'), findsOneWidget);
      expect(find.bySemanticsLabel('My'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });
}
