> Historical CI75 policy review. Superseded by the user-requested single default behavior in `flutter-default-scroll-hide.md`; the selector described below no longer exists.

# Explicit floating-navigation visibility policy

A real CI74 Home → 动态 diagnostic trace established that feed pointers and
vertical notifications reached the root, but every root event was suppressed by
`accessibleNavigation`. That identifies the cause in that diagnostic run; it
does not prove which service set the flag or the state of an earlier installation.
It is not a reason to change or disable system accessibility.

## App-level choices

Settings → 外观与字体 → 悬浮导航隐藏方式 offers:

- **自动（兼顾无障碍）**: unchanged safe default. Follow scroll intent unless the
  system reports accessible navigation, in which case keep the dock visible.
- **滚动时隐藏**: explicit user choice to use scroll-hide even when the system
  reports accessible navigation. Increasing consumed offset28dp hides; reverse
  movement20dp, top, Home/root selection and lifecycle changes reveal it.
- **始终显示**: never hide because of scrolling.

These choices only affect enabled floating navigation. All retain keyboard-hide,
fixed48dp-or-larger targets, hidden pointer/semantics/focus exclusion and existing
scroll-content clearance. Accessibility and reduced-motion flags still make
transitions instantaneous. Programmatic jumps do not acquire user intent.
Changing policy clears the previous scroll session and reveals navigation.
Unknown/missing persisted values safely fall back to Automatic. No OS setting,
accessibility-service state, permission, account or credential is modified.

The local opt-in report now includes `floatingNavigationPolicy` and
`policySuppressionReason`, while keeping the raw system flag visible.

## Independent validation app

The new bounded test package is `io.github.ktclat.c001apk.diagnostic.visibility`,
launcher label `c001apk 显隐验证`. The original production package and CI74's
`.diagnostic` package are unchanged and need not be uninstalled. This app has its
own fresh settings/data, no account import or migration, no shared UID, no backup,
no external deep-link filters and package-scoped provider authorities. Plugin
manifest entries may add permissions beyond the handwritten network permissions;
the recorder itself does not read external storage or transmit reports.

CI continues to use the existing ephemeral signing arrangement. Different CI
certificates must not be advertised as in-place updates; no persistent key is
created here. Production package selection remains unchanged by default.

The additional arm64-only profile artifact uses Flutter's official
`--split-per-abi --target-platform android-arm64` build. Its compiled manifest,
exact ABI and size below50,000,000 bytes are gated before upload. There is no APK
stripping, repacking or resigning. Actual APK signature, identity and delivery
remain post-build checks; source tests are not installation evidence.

## Verification scope

Regression uses the reported1200×2670 physical test surface, DPR3.25,
369.230769×821.538462 logical window, top padding140 physical pixels and top
gesture inset179 physical pixels, with accessibleNavigation=true. It exercises
production Home with synthetic offline data, not the user's Android runtime.
It distinguishes default protection from explicit touch/ballistic hide, reversal,
top/programmatic behavior, Home switching, policy transitions and hidden targets.
A separate test closes and reopens Hive to check persisted choice. Picker captures
cover the reported window and a480×240 logical/font2 short window.

No physical Xiaomi success, TalkBack usability or hardware-frame performance is
claimed. Independent source/render review and actual CI APK gates remain required.
