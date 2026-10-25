import 'package:flutter/material.dart';

import 'navigation_tab_scrubber.dart';

/// A root page replaced its content (including a transition to an empty list).
/// Restore navigation without treating a programmatic jump as user scrolling.
class RootNavigationContentChanged extends Notification {
  const RootNavigationContentChanged();
}

/// Scroll clearance for content inside the root navigation. Only scrolling
/// content and floating action buttons use the inset; the page can paint
/// normally beneath the compact navigation dock.
class FloatingNavigationInset extends InheritedWidget {
  const FloatingNavigationInset({
    super.key,
    required this.bottom,
    required super.child,
  });

  final double bottom;

  static double of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<FloatingNavigationInset>()
          ?.bottom ??
      0;

  /// Total trailing scroll clearance, including the system bottom inset once.
  /// Non-overlay routes still need their ordinary system safe-area padding.
  static double scrollPaddingOf(BuildContext context) {
    final overlay = of(context);
    final system = MediaQuery.paddingOf(context).bottom;
    return overlay > system ? overlay : system;
  }

  @override
  bool updateShouldNotify(FloatingNavigationInset oldWidget) =>
      bottom != oldWidget.bottom;
}

/// A genuinely compact floating dock, NOT a full-size NavigationBar inside a
/// pill. NavigationBar adds its own Material layout and safe-area behavior,
/// which made the previous dock taller than the requested height on devices.
class FloatingTabBar extends StatefulWidget {
  const FloatingTabBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.height,
    this.dockWidth = width,
  });

  static const double width = 268;
  static const double _innerPadding = 5;

  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final double height;
  final double dockWidth;

  /// Grow only for larger labels, never to the full screen width. The caller
  /// provides usable width after safe insets and horizontal breathing room.
  static double widthFor(BuildContext context, double availableWidth) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final preferred = scale >= 1.3 ? 320.0 : width;
    return availableWidth.clamp(0.0, preferred);
  }

  /// The entire dock stays smaller than an ordinary Material bottom bar.
  /// Each of the three destinations still has an accessible 48dp hit target.
  static double heightFor(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    if (scale >= 1.8) return 72;
    if (scale >= 1.3) return 66;
    return 62;
  }

  @override
  State<FloatingTabBar> createState() => _FloatingTabBarState();
}

class _FloatingTabBarState extends State<FloatingTabBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _selection = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
  );
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _reduceMotion = media.disableAnimations || media.accessibleNavigation;
    if (_reduceMotion) _selection.value = 1;
  }

  @override
  void didUpdateWidget(FloatingTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      if (_reduceMotion) {
        _selection.value = 1;
      } else {
        // One latest-wins pulse, never a queue or a startup/reselection bounce.
        _selection.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: SizedBox(
        width: widget.dockWidth,
        height: widget.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.height / 2),
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withOpacity(0.14),
                blurRadius: 18,
                spreadRadius: -4,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: NavigationTabScrubber(
            destinations: widget.destinations,
            selectedIndex: widget.selectedIndex,
            onDestinationSelected: widget.onDestinationSelected,
            contentPadding: const EdgeInsets.all(FloatingTabBar._innerPadding),
            child: Material(
              color: colors.surface,
              clipBehavior: Clip.antiAlias,
              shape: StadiumBorder(
                side: BorderSide(
                  color: colors.outlineVariant.withOpacity(0.34),
                  width: 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(FloatingTabBar._innerPadding),
                child: Row(
                  children: [
                    for (var index = 0;
                        index < widget.destinations.length;
                        index++)
                      Expanded(
                        child: _DockDestination(
                          key: ValueKey('floating-tab-$index'),
                          destination: widget.destinations[index],
                          selected: widget.selectedIndex == index,
                          selection: _selection,
                          colorScheme: colors,
                          onPressed: widget.destinations[index].enabled
                              ? () => widget.onDestinationSelected(index)
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DockDestination extends StatelessWidget {
  const _DockDestination({
    super.key,
    required this.destination,
    required this.selected,
    required this.selection,
    required this.colorScheme,
    required this.onPressed,
  });

  final NavigationDestination destination;
  final bool selected;
  final Animation<double> selection;
  final ColorScheme colorScheme;
  final VoidCallback? onPressed;

  static Animation<double> _pulse(
          Animation<double> parent, double stretch, double rebound) =>
      TweenSequence<double>([
        TweenSequenceItem(
            tween: Tween(begin: 1.0, end: stretch)
                .chain(CurveTween(curve: Curves.easeOutCubic)),
            weight: 25),
        TweenSequenceItem(
            tween: Tween(begin: stretch, end: rebound)
                .chain(CurveTween(curve: Curves.easeInOutCubic)),
            weight: 35),
        TweenSequenceItem(
            tween: Tween(begin: rebound, end: 1.0)
                .chain(CurveTween(curve: Curves.easeOutCubic)),
            weight: 40),
      ]).animate(parent);

  @override
  Widget build(BuildContext context) {
    final scaleX = _pulse(selection, 1.04, 0.985);
    final scaleY = _pulse(selection, 0.94, 1.025);
    final foreground = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    return Semantics(
      label: destination.label,
      selected: selected,
      button: true,
      enabled: onPressed != null,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: Tooltip(
          message: destination.label,
          child: Material(
            color: Colors.transparent,
            shape: const StadiumBorder(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (selected)
                  IgnorePointer(
                    child: AnimatedBuilder(
                      animation: selection,
                      // Only the colored indicator deforms. Text, icons,
                      // hit targets and the outer dock never scale or move.
                      child: DecoratedBox(
                        key: ValueKey(
                            'floating-tab-indicator-paint-${destination.label}'),
                        decoration: ShapeDecoration(
                          color: colorScheme.primaryContainer,
                          shape: const StadiumBorder(),
                        ),
                      ),
                      builder: (context, child) => Transform.scale(
                        key: ValueKey(
                            'floating-tab-indicator-${destination.label}'),
                        scaleX: scaleX.value,
                        scaleY: scaleY.value,
                        transformHitTests: false,
                        child: child,
                      ),
                    ),
                  ),
                // Paint ink/focus feedback above the animated background.
                Material(
                  color: Colors.transparent,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    key: ValueKey('floating-tab-hit-${destination.label}'),
                    onTap: onPressed,
                    // The indicator supplies selection motion; retain ink
                    // highlights without a second Sparkle shader animation.
                    splashFactory: NoSplash.splashFactory,
                    customBorder: const StadiumBorder(),
                    child: SizedBox.expand(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconTheme(
                            data: IconThemeData(size: 22, color: foreground),
                            child: selected
                                ? destination.selectedIcon ?? destination.icon
                                : destination.icon,
                          ),
                          const SizedBox(height: 2),
                          Flexible(
                            child: Text(
                              destination.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: TextStyle(
                                color: foreground,
                                fontSize: 12.5,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                height: 1.15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
