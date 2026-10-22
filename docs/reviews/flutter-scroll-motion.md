# Scroll-linked floating-dock motion

This revision follows the user's confirmation that CI75's explicit **滚动时隐藏**
policy works on their phone. They then requested downward movement and gradual
fade instead of immediate disappearance. It is not a new claim that the original
installation or every accessibility configuration has been tested on a device.

## Cause and behavior

CI75 combined `accessibleNavigation || disableAnimations` for dock animation.
The reported phone had the former enabled and the latter disabled. This revision
separates navigation accessibility from motion preference:

- When **悬浮 Tab 导航** is enabled, scroll hiding is the built-in behavior,
  including when the framework reports accessible navigation. There is no separate
  visibility-policy selector. Legacy Auto/AlwaysVisible preferences are ignored.
  No operating-system accessibility setting is changed.
- Consumed vertical scroll distance continuously controls progress from 0 to 1.
  Translation is `progress × (dock height + bottom safe gap)` and opacity is
  `1 − progress`. Reverse scrolling reverses both immediately.
- The existing actual user-session, active-root/Home-tab, horizontal-carousel,
  route, top-edge and clamped-overscroll filters remain. Programmatic position
  restoration does not become gesture evidence.
- The 28dp hide / 20dp reveal intent thresholds choose an idle endpoint, not when
  visible motion begins. Otherwise the nearest endpoint is used. A remaining
  partial transition settles in 60–180ms, with no disabled half-dock parked idle.
  A new drag interrupts at the currently rendered position, not the prior target.
- Actual `disableAnimations` keeps instantaneous threshold behavior. Enabling it
  during a settle cancels the ticker and reveals immediately. Existing conservative
  page/jelly accessibility-reduced behavior is separate and unchanged.
- Any partially or fully departed dock excludes pointer hits, focus and semantics.
  Fully shown targets retain their dimensions; root content and end clearance do
  not resize while the dock moves. Top, tab/root changes, keyboard and window
  changes reset/reveal as appropriate. A keyboard removes the dock altogether.

## Reference, not copied implementation

PiliPlus was inspected at commit
[`006c0fdd16fd71e6b0ece221b656c0e49e7ccf4c`](https://github.com/bggRGjQaUbCoE/PiliPlus/tree/006c0fdd16fd71e6b0ece221b656c0e49e7ccf4c).
Its sync mode accumulates drag deltas into a 0–52dp offset and translates the
padded bar, rather than simply animating a boolean visibility state:
[common page](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/006c0fdd16fd71e6b0ece221b656c0e49e7ccf4c/lib/pages/common/common_page.dart),
[main view](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/006c0fdd16fd71e6b0ece221b656c0e49e7ccf4c/lib/pages/main/view.dart).
This implementation is independently written using Flutter animation primitives.
No PiliPlus source was copied. Fade, inherited user-fling intent, idle settling,
and explicit hidden interaction/accessibility exclusion are our behavior, not
claims of identical PiliPlus behavior.

## Diagnostics and standalone build

Latest-observed context includes `dockProgress`, `dockOpacity`,
`dockTranslationY` and `dockInteractive`, updated on settle ticks as well as
scroll callbacks. `dockVisible` means progress is below 1, not that the dock is
fully shown or interactive. Normal motion records `hide_progress` /
`reveal_progress`; motion-disabled threshold events keep their old names.
The existing bounded, opt-in, in-memory recorder and explicit copy-only sharing
remain unchanged.

The new standalone test package is `io.github.ktclat.c001apk.diagnostic.motion`,
launcher **c001apk 动效验证**, independent of the original app, CI74 diagnostic
app and CI75 visibility app. Existing data is not read, migrated, overwritten or
removed. No uninstall is required. The normal package remains unchanged.
Fresh settings are independent: enable floating navigation; scroll hiding then
works by default without another policy choice. No persistent signing key is created. Both normal and standalone
builds contain the source change; the official arm64 split build is retained.
Merged-manifest identity, authority isolation and no external-link interception
must be verified on the actual new APK before delivery. APK size alone does not
establish whether the chat attachment channel will accept it.

## Validation scope

`floating_dock_motion_test.dart` covers consumed distance, reversal/clamping,
interrupted settling, small-drag recovery and actual motion-off cancellation.
`navigation_adaptive_test.dart` exercises the real production Home/feed widget
notification chain at the reported 1200×2670 physical test view, DPR3.25,
369.230769×821.538462 logical dp, top padding140 and gesture inset179 physical
pixels, with accessible navigation true and disableAnimations false.

Frame assertions compare consumed list distance, progress, actual dock RenderBox
translation and opacity, and unchanged list padding. The sequence covers full
hide/reveal, first-move touch slop, a consumed move after settle interruption,
real touch ballistic continuation, runtime motion-off, keyboard/window/Home-tab
changes, a held drag continuing after a resize, and system Back from a scrolling
My root. A continued genuine drag reestablishes its cancelled session so release
still settles; old ballistic/programmatic updates do not. Legacy preference compatibility,
accessible on-demand reveal, hidden hit/focus/semantics and existing adaptive regressions
remain covered by the surrounding tests.

Raw PNGs and the synthetic diagnostic report are generated under
`apps/flutter/build/review/motion`; CI uploads them as `c001apk-dock-motion-review`.
These are real Flutter widget-engine renders with synthetic offline feed data,
not screenshots or frame-performance measurements from the user's phone. The
user confirmed CI76 motion is smooth on their phone; the subsequent default-setting
and semantic-action revision still has framework-level validation only. The Linux widget harness
does not exercise the Android-only Apps tab or native accessibility bridge. No
merge acceptance is implied by source, widget or artifact checks.
