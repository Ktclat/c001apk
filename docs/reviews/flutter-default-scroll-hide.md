# Default floating-navigation scroll hiding

The user confirmed CI76 motion was smooth on the physical phone, then requested
scroll hiding as the default without a separate visibility-policy option.

## Current behavior

- Keep the existing floating-navigation switch (off by default). Enabling it means
  scroll-linked downward movement/fade automatically, with reverse/top/tab/root
  recovery. Classic navigation is unchanged.
- Remove the Auto / Hide / AlwaysVisible selector and its enum/storage API. Old
  `floatingNavigationPolicy` values are left untouched but never read by behavior.
  Thus existing Auto/AlwaysVisible installs do not remain silently suppressed;
  unrelated preferences and user data are not deleted or migrated.
- Do not treat `accessibleNavigation` as a blanket hide suppression or a motion-off
  preference. Actual `disableAnimations` remains respected. No OS setting changes.
- A labeled, focusable root semantics node, **页面导航**, provides the custom action
  **显示底部导航**. Its child semantics remain independent. The action reveals the
  dock and cancels inherited old fling intent; a subsequent genuine user gesture
  can hide again. This is not another visual option or settings selector.
- Partial/hidden dock targets remain excluded from pointer hit testing, keyboard
  focus and accessibility semantics. Fully restored navigation retains48dp targets.
  Existing layout clearance, motion math and interrupted-session fixes remain.

## Verification limits

Tests exercise actual production Home touch/ballistic notifications at the user's
reported logical window/DPR and accessibleNavigation=true, without selecting any
hide policy. They also exercise all legacy values across recreated roots, storage
reopen, real settings navigation and a compact large-text settings screen.
The custom reveal action is invoked through the real SemanticsOwner from a
scroll-hidden dock; this proves framework wiring, not physical TalkBack usability.
CI76's physical motion confirmation does not by itself validate this later semantic
change. No merge or APK delivery acceptance is implied by widget tests.
