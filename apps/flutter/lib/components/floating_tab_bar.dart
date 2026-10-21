import 'package:flutter/material.dart';

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
    if (scale >= 1.4) return 92;
    if (scale >= 1.15) return 84;
    return 78;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: '悬浮 Tab 导航',
      child: Material(
        elevation: 8,
        shadowColor: colors.shadow.withOpacity(0.24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(34),
          side: BorderSide(
            width: 0.7,
            color: colors.outlineVariant.withOpacity(0.45),
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
    );
  }
}
