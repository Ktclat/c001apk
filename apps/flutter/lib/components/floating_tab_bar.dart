import 'package:flutter/material.dart';

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

  @override
  bool updateShouldNotify(FloatingNavigationInset oldWidget) =>
      bottom != oldWidget.bottom;
}

/// A genuinely compact floating dock, NOT a full-size NavigationBar inside a
/// pill. NavigationBar adds its own Material layout and safe-area behavior,
/// which made the previous dock taller than the requested height on devices.
class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.height,
  });

  static const double width = 268;
  static const double _innerPadding = 5;

  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final double height;

  /// The entire dock stays smaller than an ordinary Material bottom bar.
  /// Each of the three destinations still has an accessible 48dp hit target.
  static double heightFor(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    if (scale >= 1.8) return 72;
    if (scale >= 1.3) return 66;
    return 62;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final stackedLabel = scale >= 1.3;

    return RepaintBoundary(
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(height / 2),
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withOpacity(0.14),
                blurRadius: 18,
                spreadRadius: -4,
                offset: const Offset(0, 6),
              ),
            ],
          ),
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
              padding: const EdgeInsets.all(_innerPadding),
              child: Row(
                children: [
                  for (var index = 0; index < destinations.length; index++)
                    Expanded(
                      child: _DockDestination(
                        key: ValueKey('floating-tab-$index'),
                        destination: destinations[index],
                        selected: selectedIndex == index,
                        stackedLabel: stackedLabel,
                        colorScheme: colors,
                        onPressed: () => onDestinationSelected(index),
                      ),
                    ),
                ],
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
    required this.stackedLabel,
    required this.colorScheme,
    required this.onPressed,
  });

  final NavigationDestination destination;
  final bool selected;
  final bool stackedLabel;
  final ColorScheme colorScheme;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
        label: destination.label,
        selected: selected,
        button: true,
        onTap: onPressed,
        child: ExcludeSemantics(
          child: Tooltip(
            message: destination.label,
            child: Material(
              color:
                  selected ? colorScheme.primaryContainer : Colors.transparent,
              shape: const StadiumBorder(),
              child: InkWell(
                key: ValueKey('floating-tab-hit-${destination.label}'),
                onTap: onPressed,
                customBorder: const StadiumBorder(),
                child: SizedBox.expand(
                  child: Flex(
                    direction: stackedLabel ? Axis.vertical : Axis.horizontal,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconTheme(
                        data: IconThemeData(
                          size: 22,
                          color: selected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                        child: selected
                            ? destination.selectedIcon ?? destination.icon
                            : destination.icon,
                      ),
                      if (selected) ...[
                        SizedBox(
                            width: stackedLabel ? 0 : 5,
                            height: stackedLabel ? 2 : 0),
                        Flexible(
                          child: Text(
                            destination.label,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
