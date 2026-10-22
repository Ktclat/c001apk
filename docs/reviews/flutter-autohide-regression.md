# Floating navigation scroll regression

## Verified cause

The PR's original handler counted only `ScrollUpdateNotification` events with
non-null `dragDetails`. Ordinary long touch drags already worked. Short touch
flings whose drag phase did not reach 28 logical pixels could continue scrolling
hundreds of pixels without hiding the dock, because ballistic updates have no
`dragDetails`. Pointer-wheel scrolling also had no qualifying updates.

The regression test uses the real `C001APKAPP`, `MainPage`, `HomePage`,
`HomeFeedPage`, `commonBody`, `RefreshIndicator` and `ListView.separated`, with
synthetic offline feed data. It sends actual touch pointer events and a real
`PointerScrollEvent`; it does not manually dispatch scroll notifications.

The short-fling test fails against the original `3f04795` MainPage handler:
expected hidden opacity 0, actual 1 after the content passes 28 pixels. The same
sequence passes with the fix. The wheel regression likewise failed before the
fix and passes afterward.

## Fix boundaries

- Track user scroll activity across drag and ballistic updates, and wheel events.
- Preserve the 28px hide / 20px show hysteresis and dock-only ValueNotifier update.
- Reveal on return to top; ignore out-of-content bounce distance.
- Only depth-zero horizontal PageMetrics (Home subtab changes) reset the dock.
  Nested feed carousels must not reveal it.
- Stop inactive, kept-alive Home tab notifications before they reach root chrome.
  Descendant refresh indicators and active tab observers still receive events.
- Reset session tracking when root page, Home tab, layout mode or account changes.
- Preserve compact dock dimensions, decorative jelly, stable hit areas, reduced
  motion and accessible-navigation behavior. No FloatingTabBar rendering changes.

## Reproduce and interpret

Use Flutter 3.24.5 with the existing pinned fonts installed. In sandboxed CI use
`BOT=true CI=true FLUTTER_SUPPRESS_ANALYTICS=true`, writable HOME/config and
PUB_CACHE; these supported flags prevent the SDK's optional metadata detection.
Run `flutter test test/ui/navigation_scroll_regression_test.dart` and
`flutter test test/ui/navigation_review_test.dart` from `apps/flutter`.

Frames are emitted to `build/review/autohide-*.png`; the adjacent text file records
actual feed offset and target opacity. They are real Flutter-engine rasterized
frames of production widget wiring, with deliberately synthetic offline content.
They are not Android-device/emulator screenshots or hardware frame-time evidence.
Do not claim real-device gesture navigation, TalkBack usability, or performance
acceptance from these tests. Independent review remains required before merge.
