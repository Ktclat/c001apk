import 'package:flutter/material.dart';

class ToolbarIconButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Icon icon;
  final bool selected;
  final double extent;

  const ToolbarIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.selected,
    this.extent = 36,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: extent,
      height: extent,
      child: IconButton(
        onPressed: onPressed,
        icon: icon,
        highlightColor: Theme.of(context).colorScheme.secondaryContainer,
        color: selected
            ? Theme.of(context).colorScheme.onSecondaryContainer
            : Theme.of(context).colorScheme.outline,
        style: ButtonStyle(
          padding: WidgetStateProperty.all(EdgeInsets.zero),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return selected
                ? Theme.of(context).colorScheme.secondaryContainer
                : null;
          }),
        ),
      ),
    );
  }
}
