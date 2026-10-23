# Icon-link grid validation

## Scope

The production `IconLinkGridCard` keeps five ordered entries per logical page, preserves partial tails, handles empty/update states, adapts rows for narrow windows and large text, and gives pager controls 48dp targets. Display and semantic labels inspect at most 81 Unicode code points and retain at most 80, without splitting UTF-16 surrogate pairs; visual labels use at most two lines. Existing link dispatch is unchanged.

The regression harness exercises the real `itemCard` dispatch and production component in a **synthetic Home-like ListView wrapper**. The surrounding tabs, feed underlay, app bar and navigation are not a full production Home screen. Artwork is original local fixture data, decoded into the production image-provider cache keys. There is no live account, authentication, API or remote-image traffic. This is not a security-parity, real-device, TalkBack or performance claim.

## Running locally and in CI

From `apps/flutter`, with the existing pinned fonts and Flutter 3.24.5 SDK available:

```
flutter test --no-pub test/ui/icon_link_grid_tail_test.dart --reporter expanded
flutter analyze --no-pub --no-fatal-infos lib/components/cards/icon_link_grid_card.dart test/ui/icon_link_grid_tail_test.dart
```

The existing CI fetches/verifies the pinned fonts before running all Flutter tests. Fixtures use repository-relative paths. The SDK Material icon font uses `FLUTTER_ROOT` (set by the Flutter CI setup). The default local test run does not write screenshots; `ICON_GRID_EVIDENCE` is optional. The existing full CI regression step sets it to `build/review/icon-grid`, then separately uploads the resulting PNGs, the whole-suite exit code and frame hashes. It does not repeat the matrix or relax the existing 900-second timeout/failure gate. Empty screenshot output fails the dedicated artifact upload. To opt into review frames, create its `before` and `after` subdirectories first. Every accepted frame checks decoded local 90×90 images before writing it.

## Recorded checks

- The original 17-test final-candidate matrix passed.
- A subsequently added narrow-window test passed separately: at 240dp/font2 it scrolls from the first through the fifth entry, scrolls to and taps page two, scrolls to entry ten, and verifies its original topic destination.
- The exact final 18-test file subsequently passed in one coherent run, with unchanged production/test hashes before and after execution. The earlier 17+1 results remain distinct historical runs.
- Focused analysis of the final two Dart files reported no issues.
- The exact unmodified baseline produced six passes and four expected defect failures: counts 0/1/4 crash in the page-view package's zero-page initialization, and count 6 loses its second page. The baseline is not described as passing. `BEFORE=true` is only a diagnostic mode for that original source, not a normal CI setting.
- Earlier diagnostics, failed candidates and placeholder frames are not accepted visual references.

At 240dp outer width, the wrapper's padding leaves 224dp of card width; the shared column policy therefore chooses one column at font scale 2. The card may be taller than the viewport. The explicit scrolling test verifies that the page indicator and last entry remain usable rather than inferring reachability from a screenshot.

The pre-existing image helper still renders decoded images with square edges despite its radius argument. That global helper behavior is intentionally outside this bounded change. No arbitrary-URL hardening or global router change is claimed.
