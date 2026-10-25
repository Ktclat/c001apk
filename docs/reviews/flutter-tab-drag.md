# Bottom-tab drag selection

Both the standard bottom NavigationBar (the default) and floating dock now
support one continuous horizontal drag across their
destinations. Selection changes immediately as the pointer enters a new tab;
the same held pointer can reverse direction after root/page rebuilds. This is
inside-bar scrubbing, not a new gesture on the page content or vertical rail.
The shared recognizer measures rendered bounds; standard-bar targets exclude
NavigationBar’s exact SafeArea insets, including asymmetric side padding and
bottom gesture space. A gesture starting in safe padding cannot select a tab.

- A tap still selects; tapping Home/Follow again keeps its existing scroll-to-top
  behavior. Drag updates never generate that tap-again action while dwelling on
  the same destination, including multiple updates before a widget rebuild.
- The horizontal recognizer uses normal touch slop and does not turn a vertical
  drag into a selection. Leaving the dock vertically pauses selection; reentry
  resumes. Horizontal overflow clamps to the first/last destination. Release or
  cancellation ends the scrub and retains the last selected page.
- Coordinate mapping respects RTL, resized dock widths and larger labels. A
  width/height/direction/destination-count change cancels the held scrub, so the
  user starts a new gesture against the new geometry. Disabled destinations are
  skipped. Existing focus, semantics, keyboard activation and reduced-motion
  indicator behavior are retained.
- Progressive scroll-hide translation/opacity and layout clearance are unchanged.
  A hidden dock cannot start a gesture; a second finger hiding it also blocks
  selection from a previously held pointer (IgnorePointer alone does not cancel
  an existing hit path).

## Verification

`test/ui/floating_tab_drag_test.dart` exercises the shared component in both
floating and standard layouts, including RTL and asymmetric safe insets.
`navigation_adaptive_test.dart` includes **held dock scrub changes real roots
without reselect or hide regression** using the production app and synthetic
offline feed data: Home → Follow → My → Follow → Home without pointer-up,
preserved feed offset, progressive hide after scrubbing, and both new and
already-held pointer exclusion when hidden. A separate standard-bar production
test verifies the same held-pointer route sequence and safe-area-only rejection. The existing dock-motion tests
continue to cover partial progress, idle settling, reversal and interruption.

Synthetic widget-engine PNGs are written to `build/review/tab-drag` and included
in the existing `c001apk-dock-motion-review` CI artifact. These are not Android
device screenshots, real account data, or device-performance measurements.
