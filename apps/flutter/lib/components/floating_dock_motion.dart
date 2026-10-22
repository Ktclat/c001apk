import 'package:flutter/animation.dart';

/// Scroll-linked motion, independent of the system's navigation-accessibility
/// flag. The owner decides whether scrolling may hide the dock at all.
class FloatingDockMotion extends AnimationController {
  FloatingDockMotion({required super.vsync})
      : super(duration: const Duration(milliseconds: 180));

  double travelExtent = 74;
  double signedTravel = 0;
  bool reduceMotion = false;

  bool get fullyShown => value == 0;

  bool configure({required double extent, required bool motionDisabled}) {
    assert(extent > 0);
    if (travelExtent == extent && reduceMotion == motionDisabled) return false;
    travelExtent = extent;
    reduceMotion = motionDisabled;
    reveal();
    return true;
  }

  void reveal() {
    signedTravel = 0;
    stop(); // Also cancels an interrupted settle.
    if (value != 0) value = 0;
  }

  void beginUserScroll() {
    stop(); // Continue from the current visual position, not the settle target.
    signedTravel = 0;
  }

  String consume(double delta) {
    if (delta == 0) return 'no_consumed_distance';
    stop();
    if (signedTravel.sign != delta.sign) signedTravel = 0;
    signedTravel = (signedTravel + delta).clamp(-80.0, 80.0);
    if (reduceMotion) {
      if (signedTravel >= 28) {
        if (value != 1) value = 1;
        return 'hide_threshold';
      }
      if (signedTravel <= -20) {
        if (value != 0) value = 0;
        return 'reveal_threshold';
      }
      return 'below_threshold';
    }
    final next = (value + delta / travelExtent).clamp(0.0, 1.0);
    if (next != value) value = next;
    return delta > 0 ? 'hide_progress' : 'reveal_progress';
  }

  void endUserScroll() {
    if (reduceMotion || value == 0 || value == 1) return;
    // Preserve clear directional intent while avoiding a half-clipped,
    // non-interactive navigation bar parked at rest after a tiny movement.
    final target = signedTravel >= 28
        ? 1.0
        : signedTravel <= -20
            ? 0.0
            : value >= .5
                ? 1.0
                : 0.0;
    animateTo(target,
        duration: Duration(
            milliseconds:
                (180 * (target - value).abs()).round().clamp(60, 180)),
        curve: Curves.easeOutCubic);
  }
}
