# Flutter Home feed scroll diagnostics

This diagnostics component adds observation, not itself a claim that the reported physical-device
failure is fixed. The reported route is Home → 动态. Previous Flutter engine
widget tests used offline synthetic feed data on Linux, not the user's phone.

## Confirmed implementation differences

- `悬浮 Tab 导航` defaults to off. Classic navigation does not auto-hide.
- With floating mode enabled, consumed list movement directly moves/fades
  the dock;28 logical pixels establishes hide intent for idle settling. This normally means pushing the finger upward to browse later posts.
  Moving back by 20 logical pixels reveals it; reaching the top reveals it.
  The old settings wording “下滑收起、上滑出现” was ambiguous about finger direction
  and is replaced with an explicit description.
- Enabled floating navigation always scroll-hides by default. `accessibleNavigation`
  is recorded but is not a blanket visibility guard. `disableAnimations` still
  controls actual motion. Legacy visibility-policy values are ignored, not deleted.
  The compatibility report field `floatingNavigationPolicy` is always `hideOnScroll`,
  not a selectable setting. Never ask users to disable needed accessibility.
- Only the selected root and selected Home tab may control the dock. Non-current
  routes and disabled ticker subtrees are ignored. Horizontal carousels,
  programmatic updates without a user session, and unconsumed overscroll cannot
  hide it. Genuine user scrolls include their ballistic tail.
- Android prepends the Apps tab consistently to both Home arrays. The initial
  selection is looked up by FEED identity; no Android-only fixed-index mismatch
  was found in this path.

## Local opt-in workflow

Settings → About → 构建与悬浮导航诊断:

1. Start a new recording, then return to Home → 动态.
2. Push the list upward to browse later posts, then optionally reverse direction.
3. Return to diagnostics and stop/view the recording.
4. Copy the report only if the user chooses to share it. No automatic transmission.

The recorder is off by default, bounded to the last 60 events plus aggregate
counters, kept only in process memory, and clearable. It records no feed text,
account credentials, account IDs, device identifiers, URLs, or wall-clock times.
Environment fields are explicitly labeled latest-observed context rather than a
frozen stop-time snapshot. Opening the diagnostic screen itself must not be mistaken
for an active Home route: the report retains the last root layout and observations of each scroll.

Pointer-kind/move counters, actual feed controller position changes, Home-tab
notification forwarding, and root notification decisions are separate evidence.
A position change is not labeled as a physical gesture. A no-dragDetails update
may be either ballistic or programmatic; the report preserves user-session and
raw notification markers rather than guessing. A synthetic test can also create
pointer events, so a report does not independently prove physical-device testing.

Interpretation examples:

- Feed position changes, but no Home/root notification: inspect propagation.
- Home events rejected as inactive: compare selected Home identity and indices.
- Root reports `accessible_navigation`: intentional protection, not a lost event.
- Root reports `no_user_session`: update did not inherit observed user intent.
- Root reaches `hide_progress` with `dockProgress: 1` (or `hide_threshold` when
  motion is disabled), then a reveal lifecycle event: inspect the reset reason
  instead of assuming the hide threshold never ran.
- No consumed distance: the list may already be at an edge or not scrollable.

## Build identity and installation safety

About displays source SHA, build mode, and CI run number. The copied report also
includes the actual checkout SHA because pull-request CI can build a merge ref.
Local builds without injected metadata explicitly say `unidentified-local`.
The workflow passes metadata to debug and profile builds; package version
`0.1.0(1)` alone still cannot distinguish revisions in Android's app-info screen.

Existing CI72 and CI73 profile APKs have the same package/version but different
Android debug signing certificates. Do not promise an in-place update, and do
not tell users to uninstall an existing app without addressing local-data loss.
This revision does not change signing, install an APK, or bypass Android checks.

## Validation scope

Focused tests exercise the actual production Home feed with synthetic data:
recording stays off until requested; pointer/position/Home/root markers appear;
programmatic jumps are not labeled user scrolls; accessibility protects the dock;
reduced animation alone still allows hiding; ring memory is bounded; report copy
requires an explicit tap; clearing removes scroll events. Physical-device
behavior remains a separate acceptance gate.

## Standalone diagnostic APK

CI74 produced `c001apk-android-diagnostic-profile`, labeled `c001apk 诊断`,
package `io.github.ktclat.c001apk.diagnostic`, version suffix `-diag`.
The subsequent visibility-policy validation build uses the distinct
`io.github.ktclat.c001apk.diagnostic.visibility` package, labeled `c001apk 显隐验证`,
with artifact `c001apk-android-visibility-profile` (plus an arm64-only artifact),
so neither existing app needs to be removed. These are separate test apps, not
updates to the original production package or to one another.
Normal debug/profile/release package selection remains unchanged by default.
No persistent key is generated. The diagnostic package uses its own Android
sandbox, disables backup, has no shared UID, omits external deep links, requests
only network permissions in its app manifest, and has no account/data migration.
It still runs the real Home feed path; no synthetic feed is shipped.

Its fresh settings and anonymous session are NOT the original app's state.
Enable floating navigation in its own appearance settings before reproducing.
Do not import an account, uninstall the original app, or disable accessibility.
If the public feed fails to load, record that limitation instead of substituting
fixture data. The Home app bar is labeled 诊断 and offers a diagnostic shortcut.
Production update checks are disabled in this standalone package, so it does not
offer an ordinary-package APK as its own update.

The source contract is checked by `python3 tools/test_diagnostic_identity.py`.
After compilation, CI calls `tools/verify_apk_identity.py` with Android `aapt`
to reject an APK with the wrong package, launcher label, version suffix, shared
UID, enabled backup, external VIEW/BROWSABLE/autoVerify filters, or provider
authorities outside its own package before its diagnostic artifact is uploaded. This source
review does not substitute for validating the built APK and coinstallation.

## Local verification snapshot (2026-10-22)

- Normal full suite: 225 passed, 5 skipped.
- Standalone `APP_DIAGNOSTIC=true` focused diagnostics: 2 passed.
- A subsequent style-only edit added braces around the existing conditional
  assignment in `dockVisibilityChanged`. Normal focused diagnostics were rerun:
  2 passed. Final analysis has 9 pre-existing informational findings, none in
  changed files. CI will rerun the full suite on the published source snapshot.
- Three Python packaging-contract tests passed; the validator also correctly
  rejects the existing normal CI73 APK as the wrong diagnostic package.
- Normal and standalone diagnostics UI were rendered with real bundled fonts.
  These are Linux Flutter widget-engine captures, not Android device evidence.
- Positive compiled diagnostic APK identity, installation/coexistence, actual
  Android Home notifications, and the user's Xiaomi behavior remain unverified.
