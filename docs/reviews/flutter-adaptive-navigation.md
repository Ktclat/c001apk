# Adaptive floating navigation: source and engine review

This revision follows the Xiaomi 15 / other-window-size feedback. It extends PR #1 head `79958360d94fc81c3ce2bfcffb6d4cf7d579c099`; it does not establish a physical-device acceptance result.

## Behavior contract

- The floating-navigation preference means a bottom overlay in portrait, landscape, and wide windows. It no longer silently becomes a rail. Explicit classic navigation retains its previous rail behavior.
- Layout uses the actual logical window and safe insets, not a phone-model lookup. The capsule prefers 268dp, or 320dp at text scale ≥1.3, constrained by usable width with 16dp side gutters. Destination hit regions stay fixed and at least 48dp in the tested range.
- The existing 22dp icons, 12.5sp labels, 2dp icon/label gap, 62/66/72dp height tiers, border and decorative jelly animation remain. Only decoration animates; click regions do not scale.
- Bottom placement uses the larger of view padding and bottom system gesture inset, plus 12dp breathing room (8dp below 600dp window height). Side cutouts protect both navigation and root content. The keyboard removes bottom navigation.
- Increasing consumed vertical content offset hides after 28dp; reversing reveals after 20dp. This usually means a finger swiping upward to read later content. Pulling down at the top does not hide the bar. User-started ballistic/wheel behavior from the previous revision is preserved; programmatic scrolling is not indiscriminately treated as user intent.
- A window-size change, root selection, Home-tab change, Follow source change, or Topic category selection resets navigation intent. A category that becomes empty must not leave navigation hidden. Inactive retained Home/Topic pages cannot control active chrome.
- While hidden, pointer interaction, accessibility semantics and focus are excluded immediately. Reduced motion and accessible navigation keep their existing behavior.

## Scroll clearance and short windows

The root page continues painting behind the overlay. Only the end of scrollable content gets clearance; it remains stable while the dock is hidden. `FloatingNavigationInset.scrollPaddingOf` owns the bottom system inset once. This removes the previous common feed list's duplicate inset and provides a system-safe fallback outside floating mode.

My's profile/login header now belongs to its `CustomScrollView`. Local Follow's manage header and warning likewise belong to the content list. Empty/error/loading states with a leading header are one scrollable surface rather than a fixed header consuming the available height. States without a header are centered within the area above the overlay, with scroll recovery for oversized messages; they are no longer centered behind the capsule. Actual short-window Topic tests check empty text, loading indicator, error/retry visibility, an oversized error scrolled to its final retry line, and a working retry to empty. The sidebar's last category is also scrolled above the dock before selection, rather than relying on a tap inside the simulated bottom gesture area.

A real production-route test exposed the Local Follow problem under the new landscape-overlay policy: at 480×240dp, text scale 2 and bottom inset 24dp, the former fixed header put the list top at 175dp while the usable area above the dock ended at 120dp. No full action could fit. The revised list starts at 56dp and scrolls the header away.

Another before/after regression uses the actual Home → Topic → vertical category PageView → CarouselPage list. A touch scroll hid the dock, but selecting an empty category left it hidden. Explicit content-identity notification now reveals it without confusing the programmatic category jump with a user fling.

## Synthetic render matrix

`test/ui/navigation_adaptive_test.dart` mounts `C001APKAPP` with real production pages, bundled Noto fonts and the SDK Material icon font. Network responses, account records and feed content are offline synthetic fixtures. PNGs are rasterized by the Flutter engine, with production shadows enabled during capture.

| Case | Logical window | Raster scale | Text scale | Insets (left, top, right, bottom), dp |
|---|---|---|---|---|
| Xiaomi-aspect, hypothetical density | 400×890 | 3 | 1 | 0,32,0,24 |
| Compact, large text | 320×640 | 2 | 2 | 0,24,0,48 |
| Phone / extra gesture inset | 360×800 | 2 | 1 | 0,24,0,24; gesture bottom40 |
| Phone | 393×852 | 2 | 1.3 | 0,24,0,24 |
| Phone, large text | 412×915 | 2 | 2 | 0,24,0,48 |
| Wide phone | 480×900 | 2 | 1 | 0,0,0,0 |
| Landscape cutouts | 890×400 | 2 | 1 | 44,0,24,24 |
| Short window, large text | 480×240 | 2 | 2 | 24,0,0,24 |
| Tablet | 600×960 | 2 | 1.3 | 0,24,0,24 |

The Xiaomi-aspect frame is 1200×2670 pixels, matching the [official physical display specification](https://www.mi.com/tw/product/xiaomi-15/specs/). Density3 and these logical insets are explicitly hypothetical. They do not identify the user's runtime density, display-size setting, app window or gesture configuration. A resized/cropped earlier screenshot is not evidence of those values.

Each matrix case checks real Home touch hide/reveal, safe capsule/48dp targets, hidden hit/focus/semantics exclusion, and Home/My final actions with the dock deliberately kept visible. Scrollable My cases also verify whole-header movement and touch hide/reveal. Final actionable rectangles must intersect the usable viewport, remain above the dock, and be hit-testable. Merely placing an item fully above the viewport does not pass.

Variable-height lists refine their maximum extent after layout/pagination. The tests settle the end, then position the last actual action in the usable band. This separately proves reachability rather than assuming an estimated max offset or an entire oversized card fits in a short viewport. Local Follow and Topic receive the same actual-route checks at 400×890 and at 480×240 with text scale2/bottom24. A signed-in synthetic Follow case checks source-to-empty reset and explicit classic/overlay switching.

## Validation and evidence

Final local validation on 2026-10-22: **223 tests passed, 5 skipped**. `flutter analyze --no-fatal-infos` exited successfully with 9 pre-existing informational findings and no errors or warnings. The complete suite includes the updated localization expectation for explicit floating mode and per-test preference cleanup. Exact source/frame hashes accompany the evidence manifest. Captures were regenerated into a clean output directory; earlier intermediate rail frames are not mixed into final evidence.

Reproduce from `apps/flutter` with an official Flutter3.24.5 SDK, writable isolated HOME/PUB_CACHE, bundled fonts, and the following safe environment: `BOT=true CI=true FLUTTER_SUPPRESS_ANALYTICS=true`. Set `FLUTTER_ROOT` and prepend its `bin` to PATH. Run:

```
flutter analyze --no-fatal-infos
flutter test --reporter expanded
```

The existing `navigation_scroll_regression_test.dart` still exercises short touch-fling, wheel, inactive Home tab, embedded horizontal carousel, top reset, programmatic interior jump, overscroll and reduced motion. The existing `navigation_review_test.dart` retains fixed-hitbox animation, semantics, keyboard, account and render-work checks, with expectations updated for the explicit overlay policy.

## Remaining acceptance limits

- These are software-rendered widget-engine frames, not Xiaomi/Android screenshots or hardware performance traces.
- The Android-only installed-app Home tab is not entered by Linux-host `Platform.isAndroid`; its production padding call is updated, but this matrix must not be represented as an Android installed-app end-to-end run.
- Actual Xiaomi15 density/window/insets, physical touch/gesture-navigation behavior, TalkBack interaction and GPU frame pacing remain unverified. No merge or overall product-completion claim follows from this evidence.
