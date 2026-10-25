import 'package:flutter/material.dart';

/// Adds horizontal drag-to-select without changing a bar's tap, focus, or
/// accessibility implementation. Only the actual tab area excludes safe insets.
class NavigationTabScrubber extends StatefulWidget {
  const NavigationTabScrubber({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
    this.contentPadding = EdgeInsets.zero,
  });

  final List<NavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;
  final EdgeInsets contentPadding;

  @override
  State<NavigationTabScrubber> createState() => _NavigationTabScrubberState();
}

class _NavigationTabScrubberState extends State<NavigationTabScrubber> {
  int? _dragSelection;
  Size? _dragSize;
  TextDirection? _direction;
  Offset? _downPosition;

  Size get _size => (context.findRenderObject()! as RenderBox).size;
  Rect _tabRect(Size size) =>
      widget.contentPadding.deflateRect(Offset.zero & size);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final direction = Directionality.of(context);
    if (_direction != direction) _endDrag();
    _direction = direction;
  }

  @override
  void didUpdateWidget(NavigationTabScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentPadding != widget.contentPadding ||
        oldWidget.destinations.length != widget.destinations.length) {
      _endDrag();
    }
  }

  void _endDrag() {
    _dragSelection = null;
    _dragSize = null;
    _downPosition = null;
  }

  void _selectAt(Offset position) {
    if (_dragSelection == null || widget.destinations.isEmpty) {
      return;
    }
    final size = _size;
    if (_dragSize != size) {
      // A held pointer must not choose targets against newly resized geometry.
      _endDrag();
      return;
    }
    final rect = _tabRect(size);
    if (position.dy < rect.top ||
        position.dy > rect.bottom ||
        rect.width <= 0) {
      return;
    }
    final visualIndex =
        ((position.dx - rect.left) / rect.width * widget.destinations.length)
            .floor()
            .clamp(0, widget.destinations.length - 1);
    final index = _direction == TextDirection.rtl
        ? widget.destinations.length - 1 - visualIndex
        : visualIndex;
    if (index == _dragSelection || !widget.destinations[index].enabled) {
      return;
    }
    _dragSelection = index;
    // Never generate tap-again actions while dwelling on a tab. Keep the
    // gesture's latest selection even before the parent has had a rebuild.
    widget.onDestinationSelected(index);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onHorizontalDragDown: (details) {
          _downPosition = details.localPosition;
          _dragSize = _size;
        },
        onHorizontalDragStart: (details) {
          final size = _size;
          final down = _downPosition;
          if (down == null ||
              _dragSize != size ||
              !_tabRect(size).contains(down)) {
            _endDrag();
            return;
          }
          _dragSelection = widget.selectedIndex;
          _selectAt(details.localPosition);
        },
        onHorizontalDragUpdate: (details) => _selectAt(details.localPosition),
        onHorizontalDragEnd: (_) => _endDrag(),
        onHorizontalDragCancel: _endDrag,
        child: widget.child,
      );
}
