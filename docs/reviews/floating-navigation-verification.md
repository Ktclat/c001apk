# Floating navigation verification

Review target: PR #1, source baseline `a7994ee10b554ed60fb3aa2414c3faebf270a7c2`.

## Scope and corrections

- Preserve the compact 268 × 62 logical-pixel dock at normal text size. Each destination has an 86 × 52 target in the 390 × 850 test viewport.
- Stack the selected icon and visible label at enlarged text sizes instead of removing the label. The dock is 66 or 72 pixels tall at tested larger scales.
- Ignore scrolling from inactive root destinations or while the floating dock is not in use. Restore navigation after keyboard/layout/preference transitions and Home subtab changes, including a transition to empty content.
- Keep navigation visible with accessible navigation enabled. Respect reduced-motion settings, and remove hidden navigation from keyboard focus as well as pointer and semantics access.
- Preserve bottom gesture clearance, respect horizontal safe insets, and allow both landscape orientations in Android startup configuration.
- Refine the outer stroke from 0.7 to 1 logical pixel without growing the 268 × 62 frame, 5-pixel padding, 12-pixel bottom margin or hit targets.
- Replace abrupt root selection with a 160 ms `easeOutCubic`, incoming-only 4 → 0 pixel vertical settle. Keep `jumpToPage`, full opacity and a cached `RepaintBoundary` child: no outgoing-page crossfade or horizontal traversal through intermediate destinations. Navigation itself stays fixed. Startup/reselection do not animate; reduced motion, layout and account resets cancel the transition.

## Reproduction

Use the pinned Flutter 3.24.5 / Dart 3.5 toolchain and the existing development prerequisites. From `apps/flutter`:

```sh
bash tools/fetch_fonts.sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub -r expanded
flutter test --no-pub test/ui/navigation_review_test.dart -r expanded
flutter build apk --debug --no-pub
```

The navigation review renders the actual `C001APKAPP`, using synthetic network fixtures and real bundled Noto / Material Icons fonts. It enables real Flutter shadows for screenshots and restores the test setting afterward. Generated images are under `apps/flutter/build/review/fixed/`; they are **not Android device screenshots**. `REVIEW_STAGE` can select another output directory for comparisons.

## Verified in the Flutter test engine

- Normal portrait geometry, all three destination selections, light and dark home.
- Actual drags on a populated 25-item root feed: hide downward, restore upward; the final item and footer can scroll fully above the dock.
- Hidden navigation has no accessible semantics label, keyboard-focusable descendants, or hit-test participation.
- Hidden → keyboard → keyboard closed, and hidden → Home subtab transitions restore visible navigation.
- 320-pixel width at system scales 1.3, 1.5, and 2.0; combined system 2.0 × in-app 1.3 = 2.6 keeps the selected label visible and targets at least 48 × 48.
- Accessible navigation prevents auto-hide; reduced-motion settings remove dock slide/fade durations.
- 850 × 390 landscape with nonzero left/right and bottom safe insets; the 600-pixel portrait rail breakpoint and return to phone portrait.
- A synthetic signed-in actual-app state shows the publishing FAB completely above the dock.
- Existing regression tests cover destination state and account transitions. Added rapid successive selection, same-tab reselection, and interruption by rail layout, reduced motion and account reset.
- Root-selection screenshots at 0 / 80 / 160 ms show content offsets 4 / approximately 0.5 / 0 pixels. Every captured icon region is checked against actual image pixels, not just widget presence.

Full suite result: **209 passed, 5 skipped**. Skips are two opt-in live API probes and three Windows-only login tests; they are not navigation acceptance tests. Static analysis has no errors or warnings under the documented command; existing informational diagnostics remain.

## Navigation work regression measurements

The same instrumented actual-app fixture was run before and after the motion refinement, against the pre-motion local checkpoint `5ff303db2b3ea516ff45c03638166416fd2e2fde` and the refined source. These are deterministic Flutter debug-engine work counts, **not physical-device frame times or FPS**.

- After warming all three roots, 30 switches preserve root `State` identities, the home feed controller and scroll offset. Both versions issue 0 additional requests and rebuild only the floating navigation component 30 times.
- The 192 ms animation-only interval, measured after initial selection/layout, rebuilds 0 root/feed/card widgets. The refined transition paints 0 render objects inside the cached content subtree during that interval.
- An isolated dock hide notification produces 0 feed/card rebuilds and 0 requests. Real scrolling is tested separately; newly exposed cards may legitimately build while scrolling.

This demonstrates that the added motion does not introduce per-tick feed rebuilds or redraws in the tested scene. It does not establish a device-level performance improvement. Heavy real image feeds, raster-cache/memory behavior and Android frame pacing still need profiling.

## Debug APK build

`flutter build apk --debug --no-pub` completed successfully. The APK has a verified Android Debug signature (v1/v2), package `io.github.ktclat.c001apk`, version `0.1.0+1`, minimum SDK 21 and target SDK 34. SHA-256: `1b5bffbc8c5e94bd25177dc7209a7313244d53f153f033c70cd642f4989eba75`.

The initial full build emitted error-prefixed Kotlin metadata compatibility diagnostics despite successful assembly (the final cached incremental build emitted none), for example `fragment-1.7.1-api.jar`: metadata version `1.8.0`, expected `1.6.0`. A task-scoped rebuild identifies the emitter as `:permission_handler_android:extractDebugAnnotations` using the older Lint annotation-analysis classloader, not app Kotlin compilation. That task continued, extracted three `IntDef` annotations and wrote `annotations.zip`; both targeted extraction and full assembly succeeded. Completeness of its annotation analysis and Android runtime behavior remain unverified; do not silently treat error-prefixed diagnostics as harmless. No dependency/toolchain upgrades were made to suppress them. Building and signature verification do not establish runtime behavior.

## Not run / not established

- The earlier physical-device reference image was not available in this review checkout, so no direct before/after match to it is claimed.
- Actual Android runtime rotation, the Android-only Applications tab, system gesture handling, TalkBack behavior, and phone performance remain **NOT_RUN**. Resizing a Flutter test viewport does not certify them.
- Enabling orientation in source is not proof that every Android page works correctly in landscape.

These results do not establish final device acceptance or permission to merge. Keep the PR unmerged until independent review and the outstanding device checks are satisfied.
