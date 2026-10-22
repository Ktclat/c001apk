import 'package:c001apk_flutter/components/floating_dock_motion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'dock progress follows consumed distance and reverses immediately',
      (tester) async {
    final motion = FloatingDockMotion(vsync: tester);
    addTearDown(motion.dispose);
    motion.configure(extent: 100, motionDisabled: false);
    motion.beginUserScroll();
    motion.consume(10);
    expect(motion.value, closeTo(.1, .0001));
    motion.consume(20);
    expect(motion.value, closeTo(.3, .0001));
    motion.consume(-10);
    expect(motion.value, closeTo(.2, .0001));
    expect(motion.isAnimating, false);
    motion.consume(200);
    expect(motion.value, 1);
    motion.consume(0);
    expect(motion.value, 1);
    motion.consume(-200);
    expect(motion.value, 0);
  });

  testWidgets('new drag interrupts settle at its current visual progress',
      (tester) async {
    final motion = FloatingDockMotion(vsync: tester);
    addTearDown(motion.dispose);
    motion.configure(extent: 100, motionDisabled: false);
    motion.beginUserScroll();
    motion.consume(30);
    motion.endUserScroll();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final interrupted = motion.value;
    expect(interrupted, greaterThan(.3));
    expect(interrupted, lessThan(1));
    motion.beginUserScroll();
    expect(motion.value, interrupted);
    motion.consume(-25);
    expect(motion.value, closeTo(interrupted - .25, .0001));
    motion.endUserScroll();
    await tester.pumpAndSettle();
    expect(motion.value, 0);
  });

  testWidgets(
      'tiny movement settles shown rather than parking partially hidden',
      (tester) async {
    final motion = FloatingDockMotion(vsync: tester);
    addTearDown(motion.dispose);
    motion.beginUserScroll();
    motion.consume(10);
    motion.endUserScroll();
    await tester.pumpAndSettle();
    expect(motion.fullyShown, true);
  });

  testWidgets('actual motion-off preference preserves instant thresholds',
      (tester) async {
    final motion = FloatingDockMotion(vsync: tester);
    addTearDown(motion.dispose);
    motion.configure(extent: 100, motionDisabled: true);
    motion.beginUserScroll();
    motion.consume(15);
    expect(motion.value, 0);
    motion.consume(15);
    expect(motion.value, 1);
    motion.consume(-10);
    expect(motion.value, 1);
    motion.consume(-10);
    expect(motion.value, 0);
    motion.endUserScroll();
    expect(motion.isAnimating, false);
  });

  testWidgets('motion preference and layout changes cancel in-flight settle',
      (tester) async {
    final motion = FloatingDockMotion(vsync: tester);
    addTearDown(motion.dispose);
    motion.consume(30);
    motion.endUserScroll();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(motion.isAnimating, true);
    motion.configure(extent: 74, motionDisabled: true);
    expect(motion.isAnimating, false);
    expect(motion.value, 0);
    motion.configure(extent: 100, motionDisabled: false);
    motion.consume(40);
    motion.endUserScroll();
    motion.reveal();
    await tester.pumpAndSettle();
    expect(motion.value, 0);
  });
}
