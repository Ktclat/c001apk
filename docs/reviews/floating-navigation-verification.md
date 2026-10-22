# Floating navigation verification

Review target: PR #1, original source baseline `a7994ee10b554ed60fb3aa2414c3faebf270a7c2`. The stacked-label / jelly refinement uses published `fd49d0641c359d2a2aa1b89470ce0e25c817c01a` as its before-change baseline.

## Scope and corrections

- Preserve the compact 268 × 62 logical-pixel dock at normal text size. Each destination has an 86 × 52 target in the 390 × 850 test viewport.
- Keep all three labels visible below their icons at every tested size, not only the selected destination. The dock is 66 or 72 pixels tall at tested larger scales; the normal frame and hit targets do not grow.
- Ignore scrolling from inactive root destinations or while the floating dock is not in use. Restore navigation after keyboard/layout/preference transitions and Home subtab changes, including a transition to empty content.
- Keep navigation visible with accessible navigation enabled. Respect reduced-motion settings, and remove hidden navigation from keyboard focus as well as pointer and semantics access.
- Preserve bottom gesture clearance, respect horizontal safe insets, and allow both landscape orientations in Android startup configuration.
- Refine the outer stroke from 0.7 to 1 logical pixel without growing the 268 × 62 frame, 5-pixel padding, 12-pixel bottom margin or hit targets.
- Replace abrupt root selection with a 160 ms `easeOutCubic`, incoming-only 4 → 0 pixel vertical settle. Keep `jumpToPage`, full opacity and a cached `RepaintBoundary` child: no outgoing-page crossfade or horizontal traversal through intermediate destinations. Navigation itself stays fixed. Startup/reselection do not animate; reduced motion, layout and account resets cancel the transition.

- Add a single 240 ms selection-background jelly pulse: X scale 1 → 1.04 → 0.985 → 1, Y scale 1 → 0.94 → 1.025 → 1. Icons, labels, outer frame and hit rectangles remain stationary. Initial mount and same-tab reselection do not pulse; rapid selection restarts toward the latest destination. Reduced-motion / accessible-navigation settings finish immediately.
- Use `NoSplash` only on dock destinations to avoid a second decorative splash competing with the jelly pulse. Preserve native held-press, focus and hover feedback colors. This is a feedback-design choice, not a measured Android performance improvement.

## Reproduction

Use the pinned Flutter 3.24.5 / Dart 3.5 toolchain and the existing development prerequisites. From `apps/flutter`:

```sh
bash tools/fetch_fonts.sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub -r expanded
flutter test --no-pub test/ui/navigation_review_test.dart -r expanded
flutter build apk --debug --no-pub
flutter build apk --profile --target-platform android-arm64 --no-pub
```

The navigation review renders the actual `C001APKAPP`, using synthetic network fixtures and real bundled Noto / Material Icons fonts. It enables real Flutter shadows for screenshots and restores the test setting afterward. Generated images are under `apps/flutter/build/review/fixed/`; they are **not Android device screenshots**. `REVIEW_STAGE` can select another output directory for comparisons.

## Verified in the Flutter test engine

- Normal portrait geometry, all three destination selections, light and dark home.
- Actual drags on a populated 25-item root feed: hide downward, restore upward; the final item and footer can scroll fully above the dock.
- Hidden navigation has no accessible semantics label, keyboard-focusable descendants, or hit-test participation.
- Hidden → keyboard → keyboard closed, and hidden → Home subtab transitions restore visible navigation.
- 320-pixel width at system scales 1.3, 1.5, and 2.0; combined system 2.0 × in-app 1.3 = 2.6 keeps all three Chinese labels visible and targets at least 48 × 48.
- Accessible navigation prevents auto-hide; reduced-motion settings remove dock slide/fade durations.
- 850 × 390 landscape with nonzero left/right and bottom safe insets; the 600-pixel portrait rail breakpoint and return to phone portrait.
- A synthetic signed-in actual-app state shows the publishing FAB completely above the dock.
- Existing regression tests cover destination state and account transitions. Added rapid successive selection, same-tab reselection, and interruption by rail layout, reduced motion and account reset.
- Root-selection keyframes at 0 / 60 / 120 / 180 / 240 ms verify the incoming content settle and full jelly cycle; additional actual Flutter captures sample every 20 ms through 320 ms. Every keyframe checks actual icon pixels, stable icon/label/hit geometry and background bounds, not just widget presence.
- Same-tab held-pointer captures at 200 / 240 ms differ from the unpressed dock in 43,668 / 44,015 RGB channels. Keyboard focus remains visible. Earlier 80 / 120 ms captures were too early relative to the tap-down deadline and the first ink-animation frame; they did not establish missing product feedback.
- A separate English component stress fixture preserves full semantics and tooltips. At 2.6×, all three English labels truncate with ellipses (Home, Following, Profile); this is not English product localization and does not demonstrate full visible English text at that extreme scale.

Full suite result: **210 passed, 5 skipped**. Skips are two opt-in live API probes and three Windows-only login tests; they are not navigation acceptance tests. Static analysis has no errors or warnings under the documented command; 9 existing informational diagnostics remain.

## Navigation work regression measurements

The actual-app fixture was recaptured before this refinement on `fd49d0641c359d2a2aa1b89470ce0e25c817c01a` and after the stacked-label / jelly change. These are deterministic Flutter debug-engine work counts, **not physical-device frame times or FPS**.

- After warming all three roots, 30 switches preserve root `State` identities, the home feed controller and scroll offset. Both versions issue 0 additional requests and rebuild only the floating navigation component 30 times.
- The final 320 ms animation-only interval, measured after initial selection/layout, counts 0 root/feed/card builds and 0 `paintChild` callbacks inside the cached content subtree. This covers the full 240 ms jelly cycle and a post-completion interval. The navigation controller is completed; a subsequent settle checks for outstanding transient callbacks.
- A positive control explicitly invalidates a visible content paragraph and produces 101 counted paint callbacks, demonstrating that the zero-paint observation is not an inactive probe. These are callback counts, not GPU/raster measurements.
- An isolated dock hide notification produces 0 feed/card rebuilds and 0 requests. Real scrolling is tested separately; newly exposed cards may legitimately build while scrolling.

This demonstrates that the added motion does not introduce per-tick feed rebuilds or redraws in the tested scene. It does not establish a device-level performance improvement. Heavy real image feeds, raster-cache/memory behavior and Android frame pacing still need profiling.

## APK builds

Final Debug and ARM64-only Profile builds succeeded against the same frozen app source and passed Android Debug signature verification (v1/v2). Profile uses AOT compilation for subsequent device evaluation; neither APK is a release or proof of smoothness. Package `io.github.ktclat.c001apk`, version `0.1.0+1`, minimum SDK 21 and target SDK 34 are unchanged. Do not use split-per-ABI version-code overrides for this candidate.

- ARM64 Profile: 27,945,412 bytes; SHA-256 `06cd9d51135904d4d0b7148a5d28b05722f456790599e81b9cd2f4a06ee9db2e`.
- Debug: 109,521,124 bytes; SHA-256 `fc082dc3e6eae7b9aff24519a59133eb65d27f3cd2c532dbac54ba5587896f49`.
- The frozen floating-navigation component has SHA-256 `36a34601f149cff64ec7612da553b95f07252a2e50017ac33ff1b52841aafdaf`. No application source changed during either build.

The application source is commit `de90ced97ad0ab384e6cd99c76e78c843ed1c558`. The hashes above refer to fresh Gradle packaging of that source. Earlier valid incremental APKs contained unreferenced ZIP gaps; supported clean packaging reduced those gaps to 132 bytes without changing any decompressed ZIP entry, ABI, AOT code or asset. The earlier hashes remain historical build evidence, not the current delivery candidates.

The debug signing identity can differ from an already-installed app. Do not uninstall an existing installation merely to bypass a signature conflict; local data may be lost.

The initial full build emitted error-prefixed Kotlin metadata compatibility diagnostics despite successful assembly (the final cached incremental build emitted none), for example `fragment-1.7.1-api.jar`: metadata version `1.8.0`, expected `1.6.0`. A task-scoped rebuild identifies the emitter as `:permission_handler_android:extractDebugAnnotations` (and `extractProfileAnnotations` for Profile) using the older Lint annotation-analysis classloader, not app Kotlin compilation. That task continued, extracted three `IntDef` annotations and wrote `annotations.zip`; both targeted extraction and full assembly succeeded. Completeness of its annotation analysis and Android runtime behavior remain unverified; do not silently treat error-prefixed diagnostics as harmless. No dependency/toolchain upgrades were made to suppress them. Building and signature verification do not establish runtime behavior.

## Not run / not established

- The earlier physical-device reference image was not available in this review checkout, so no direct before/after match to it is claimed.
- Actual Android runtime rotation, the Android-only Applications tab, system gesture handling, TalkBack behavior, and phone performance remain **NOT_RUN**. Resizing a Flutter test viewport does not certify them.
- Enabling orientation in source is not proof that every Android page works correctly in landscape.

These results do not establish final device acceptance or permission to merge. Keep the PR unmerged until independent review and the outstanding device checks are satisfied.
