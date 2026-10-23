# Reply emoticon editing and bounded layout verification

## Behavior and scope

The shared `insertEmote` helper is used by the active `ReplyPage` and the legacy `ReplyDialog` handlers. Valid forward/reverse UTF-16 selections replace the normalized selected range. Invalid endpoints append safely. A collapsed caret inside a grapheme advances to its end without deleting adjacent text; a noncollapsed partial range expands outward. Successful insertion clears composing and collapses the selection after the complete catalog token.

The former programmatic callback bypassed `TextField.maxLength`. This change **adds** atomic rejection when the proposed result exceeds 500 graphemes. It does not truncate a token or an existing draft. Rejection preserves the full original editing value and publish-enabled state, with a local Chinese explanation. An emoji-action-only 32,768 UTF-16-unit bound prevents scanning abnormally large programmatic drafts. A valid full selection, in either direction, may still replace an oversized draft with a bounded token; other oversized actions are rejected unchanged. The count stops after 501 graphemes. Ordinary keyboard editing and the send protocol are not changed.

Both callbacks ignore events while publishing, on a covered route, after account-generation changes, or after disposal. Emoji mode's `readOnly` flag is not an edit lock. Successful updates derive publish availability from the resulting text instead of unconditionally enabling it. The network, CAPTCHA implementation, image-picker callback, dependencies, global `EmotePanel`, catalog and original art remain unchanged. Native and Flutter share the selection/grapheme contract, not an identical length policy: native continues to retain drafts over 500 and disables sending.

The active toolbar adapts into two rows rather than overflowing accessibility text. Its three icon controls retain 22dp icons within distinct minimum-48dp hit regions; the two text controls also have minimum-48dp regions. On short windows, a bounded, independently scrollable editor and the existing scrollable emoji grid share available height. Emoji tabs, font size, art and controls are not scaled down to conceal overflow. The legacy UI is not reworked.

## Baseline and focused validation

Baseline source is main commit `e7db2976dd3e712476f02284c31413d52b3e754a`, tree `9bca1df34f72eb750a9968ef60c2445a17deffea`, independently reconstructed and tree-checked before changes. Baseline tests compile against the original production code without importing the new helper. The coherent baseline run reproduced incorrect selected-range insertion and the invalid-selection RangeError. It had five passing reproduction/flow tests and three genuine layout failures: 18px landscape vertical overflow, 15px right overflow at 1.6× text, and 55px right overflow at 2×. Ten original before/after frames show a visible decoded production emoji panel.

The final coherent focused run passed **42 of 42 tests**: 26 helper tests, 13 active-page tests and three legacy-handler tests. Limited analysis of all seven changed Dart files reported **No issues found**. Production, tests and original source assets were SHA-256 checked before and after execution. The final run produced **11 original PNG captures and 11 JSON sidecars**. This does not replace the separate full-suite/remote-CI gate.

Coverage comprises 26 helper tests plus 16 production-component tests: forward/reverse and invalid selections; caret/neighbour preservation; Chinese, surrogate emoji, combining, ZWJ and flag boundaries; repeated insertion; composing; 500-limit atomic rejection, replacement recovery, existing oversized drafts and resource bounds; real bundled-art taps; local image-draft preservation; keyboard/emoji round trips; current hit-region edge taps; a long landscape draft with real scrolling; covered-route/account/disposal callbacks; and a gated offline publish with no second request from emoji taps.

The three legacy tests build the real `ReplyDialog` State/TextField/EmotePanel handlers inside an explicitly non-rendering child boundary, without laying out its pre-existing unbounded UI. Only that legacy child is build-only; the surrounding application and actual toast overlay receive normal layout. The child is not painted, hit-tested or traversed for semantics. Fixture focus is disabled and settled before installing draft values. Those are handler proofs, not usable legacy-dialog or screenshot proofs. Active-page checks use the actual `ReplyPage` in a `GetDialogRoute`, hosted by an offline `GetMaterialApp`, not the full Home/Main application. API calls terminate at an in-memory adapter; image picking returns a local original fixture. No live account, HTTP endpoint, publication, device installation, OS gesture, IME keyboard geometry or TalkBack behavior is claimed.

Earlier failed runs remain diagnostic evidence. The initial baseline compile/import and animation/finder failures are not product evidence. Candidate fixture repairs retained assertions: awaiting the library's real asynchronous toast overlay, clearing its queued timers, remeasuring toolbar coordinates after keyboard switching, settling build-only focus notifications before assigning composing text, and separating that unlaid legacy child from its normally laid-out toast overlay. No failure screenshot is relabeled as a passing result.

## Viewport evidence

The exact supplied fixture uses physical 1200×2670, DPR 3.25, top padding/viewPadding 140px, top system-gesture inset 179px, and all bottom/IME insets zero. Additional fixtures use 360×780dp, 844×390dp landscape, and 390×844dp at 1.6× and 2× text. The long-draft landscape frame shows the currently scrolled tail, not a claim that the entire draft fits on one screen.

Captures require a hit-testable real token and visibly decoded original art. Each original PNG has a JSON sidecar containing actual route/editor MediaQuery values, UTF-16 selection/composing, decoded art count, and actual `RenderParagraph` label font sizes, scaled sizes, paint and semantic bounds. Requested scale is not substituted for the rendered label measurement. Local run manifests bind production source, tests, locked dependencies, original fonts/art and frames, with before/after hash verification.

## Reproduction and CI proposal

From `apps/flutter`, with the pinned Flutter 3.24.5 SDK, cached dependencies and verified existing fonts:

```
BOT=true CI=true flutter test --no-pub test/ui/insert_emote_test.dart test/ui/emote_selection_test.dart --reporter expanded
BOT=true CI=true flutter analyze --no-pub --no-fatal-infos lib/pages/feed/reply/insert_emote.dart lib/pages/feed/reply/reply_page.dart lib/pages/feed/reply/reply_dialog.dart lib/pages/feed/reply/toolbar_icon_button.dart test/ui/insert_emote_test.dart test/ui/emote_selection_test.dart test/ui/emote_test_support.dart
```

Local screenshots are optional through `EMOTICON_EVIDENCE`; local execution uses an isolated HOME/XDG configuration and the existing shared SDK/cache. The Flutter runner uses its normal local engine-control protocol.

The separately reviewed CI proposal adds `EMOTICON_EVIDENCE` to the existing single 900-second full regression step, without duplicating the suite. The independent always-uploaded artifact records PNG/JSON hashes, original source/art/lock hashes, checkout commit, actual whole-suite exit and metadata-recording exit. Metadata is emitted only when PNGs exist. Nine shell-only cases verify exit preservation for 0, 7 and 124 with empty output, missing metadata inputs and normal metadata inputs. This is configuration validation, not a claim that remote CI or a new APK has passed.
