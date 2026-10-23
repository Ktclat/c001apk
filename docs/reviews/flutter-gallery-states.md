# Ordinary gallery states and navigation verification

## Scope and behavior

This bounded change covers ordinary media thumbnails and the full-screen `ImageViewPage`. Global avatar/app-icon image helpers, article thumbnails, download/share implementations, authentication, permission handling, and dependency versions are unchanged.

- Unknown or nonpositive download totals show indeterminate progress. Valid progress is clamped to 0–1.
- Loading, decoded success, and failure are distinct. A thumbnail remains one “view original” target, not a second retry control. Only the viewer provides the 48dp “重试本图” action.
- Failure replaces the image resolver with a terminal error subtree. Navigating into the viewer and back does not silently retry failed thumbnails. Revisited failed viewer pages stay failed until explicit retry.
- Retry is single-flight for the selected ordinal. A corrupt file is removed only for that image's existing disk key; URL and headers are preserved. Retry does not blindly evict a different ordinal’s current memory entry. Disk-removal failure stays visible and can be retried.
- A local memory-cache namespace and completer-identity cleanup prevent an abandoned cached-provider failure or delayed retry from evicting a newer ordinary-gallery resolution. Weak references and ephemeral error listeners do not keep historical decoded pages alive. Successful images still reuse the normal bounded memory cache. The dependency's existing unwrapped-key eviction behavior is not changed globally.
- Ordinary grid taps pass the actual ordinal, including duplicate URLs. Viewer hero identity is route/ordinal based. Existing page count, zoom/pan, Back, and action-menu behavior remain available. The original page lifecycle is retained, rather than keeping every visited bitmap alive.
- Normal four-image/two-row and nine-image geometry is preserved. Extremely wide single ordinary images gain a stable minimum-48dp hit region without stretching the source image. Article sizing and semantics are unchanged.

## Offline verification

The final focused file contains **25 tests**, and all 25 passed in one coherent run. Production, tests and original fixtures were SHA-256 checked before and after that run. Focused analysis of the final five Dart files reported no issues. The previous three responsive failures were test-owned `SemanticsHandle` cleanup occurring after Flutter's end-of-test check; moving cleanup into the test body's `finally` block did not weaken any assertions.

Coverage includes null/zero/normal/over-total progress; real PNG decoding; repeated failure without an automatic loop; explicit retry success and single-flight behavior; cache-removal failure; a genuinely corrupt file through the installed `CacheManager` with a local file service; another disk key remaining unchanged; stale completion/error ownership; successful page disposal and fresh pending/error on revisit; same-URL ordinal independence; delayed cleanup during another ordinal or route; error after a cached first frame; successful cache reuse and no permanent listener; duplicate third-image entry through real `FeedCard` and `FeedReplyCard`; positive source scroll position and repeated Back/re-entry; more-than-nine ordering; empty/clamped arguments; and zoom/pan/action-menu regressions.

The entry chain is the real card → ordinary image component → Get named route → production `ImageViewPage`, hosted by an offline `ListView`/`GetMaterialApp`. It is **not** a full Home/Main-root integration, physical Android-device, OS-gesture, TalkBack, live-network, or performance test. Android platform behavior is selected only by the fixture, without changing production platform detection.

The original main-tree Android-branch baseline deliberately retained two failures: null-total progress throws, and a third duplicate URL opens the first ordinal. Separate diagnostic failures established that an old provider could evict a fresh pending stream, and that a failed thumbnail's still-mounted `Image` could re-resolve on route/TickerMode changes. Those failed runs are historical evidence, not passing gates.

## Viewports and screenshots

The final run produced **33 original PNG captures**. Success captures require an actually decoded original local PNG with the expected dimensions, never a placeholder. The fixtures are original geometric RGB data (160×100, 100×160, and 1000×1), plus deliberately invalid image bytes.

The matrix checks 240dp and 320dp widths at text scale 2, landscape 800×360dp at scale 1.6, and minimum-48dp gallery targets. It also reproduces the supplied window geometry through generic test-window/MediaQuery configuration: physical 1200×2670, DPR 3.25, logical 369.230769×821.538462dp, top view padding 140px/43.076923dp, top gesture inset 179px/55.076923dp, and bottom insets zero. Eight Feed/Reply grid-error, viewer-error, decoded-success and Back captures are exactly 1200×2670. These are rendered widget-engine frames, not photographs or screenshots from the user's phone.

## Reproduction and CI evidence

From `apps/flutter`, using the pinned Flutter 3.24.5 SDK/cache and existing verified fonts:

```
flutter test --no-pub test/ui/gallery_states_test.dart --reporter expanded
flutter analyze --no-pub --no-fatal-infos lib/components/imageview.dart lib/components/retryable_media_image.dart lib/pages/others/imageview_page.dart test/ui/gallery_states_test.dart test/ui/gallery_test_support.dart
```

Local screenshots are optional via `GALLERY_EVIDENCE`. No fixture image service opens an HTTP socket or calls an application API; the Flutter test runner itself uses its normal local engine-control protocol.

The CI proposal adds `GALLERY_EVIDENCE=build/review/gallery` to the existing full regression step. It preserves the single `timeout 900s flutter test --no-pub --reporter expanded` command and existing icon-grid artifact. The separate gallery artifact contains PNGs and, only when PNGs exist, the whole-suite exit code, frame hashes, source/fixture/lock hashes, source commit, and test command. Empty screenshots do not acquire metadata that could masquerade as a successful artifact. The exit handler preserves the original test exit even when metadata recording fails; local shell checks covered exits 0, 7 and 124 with normal output, metadata-command failures, and empty output. This describes reviewed CI configuration, not a claim that a new remote CI run has already passed.
