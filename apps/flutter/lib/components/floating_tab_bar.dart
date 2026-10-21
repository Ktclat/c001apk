import 'package:flutter/material.dart';

/// Communicates the floating dock's scroll clearance to the root pages.
/// The root PageView itself stays full-bleed behind the dock. Only actual
/// scrollables and floating action buttons opt into this clearance.
class FloatingNavigationInset extends InheritedWidget {
  const FloatingNavigationInset({
    super.key,
    required this.bottom,
    required super.child,
  });

  final double bottom;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FloatingNavigationInset>()
          ?.bottom ??
      0;

  @override
  bool updateShouldNotify(FloatingNavigationInset oldWidget) =>
      bottom != oldWidget.bottom;
}

/// A compact, in-app bottom navigator. Unlike an Android system overlay this
/// requires no permission, and its parent reserves enough reading space below
/// scrollables so that the last feed card cannot hide beneath it.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.height,
  });

  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final double height;

  /// Increase the bar's tappable height for larger system text.
  static double heightFor(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    if (scale >= 1.8) return 104;
    if (scale >= 1.4) return 92;
    if (scale >= 1.15) return 84;
    return 78;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: '底部导航',
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(34),
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withOpacity(0.10),
                blurRadius: 18,
                spreadRadius: -4,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(34),
              side: BorderSide(
                width: 0.6,
                color: colors.outlineVariant.withOpacity(0.32),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            color: colors.surfaceContainerHigh,
            child: NavigationBar(
              height: height,
              elevation: 0,
              backgroundColor: Colors.transparent,
              indicatorColor: colors.secondaryContainer,
              destinations: destinations,
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              labelBehavior:
                  NavigationDestinationLabelBehavior.onlyShowSelected,
            ),
          ),
        ),
      ),
    );
  }
}
