import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Shared controller for the visibility state of a sidebar element.
final ValueNotifier<bool> sidebarVisibility = ValueNotifier<bool>(true);

/// Wrap a scrollable widget with this to toggle sidebar visibility
/// based on scroll direction.
class ScrollVisibilityListener extends StatefulWidget {
  const ScrollVisibilityListener({
    required this.child,
    this.enabled = true,
    super.key,
  });

  /// Whether the hide/show behavior is active.
  final bool enabled;

  /// The scrollable content to observe.
  final Widget child;

  @override
  State<ScrollVisibilityListener> createState() =>
      _ScrollVisibilityListenerState();
}

class _ScrollVisibilityListenerState extends State<ScrollVisibilityListener> {
  ScrollDirection _lastDirection = ScrollDirection.idle;

  @override
  void didUpdateWidget(covariant ScrollVisibilityListener oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.enabled != widget.enabled && !widget.enabled) {
      _resetVisibility();
    }
  }

  @override
  void dispose() {
    _resetVisibility();
    super.dispose();
  }

  void _resetVisibility() {
    sidebarVisibility.value = true;
    _lastDirection = ScrollDirection.idle;
  }

  bool _handleNotification(Notification notification) {
    if (!widget.enabled) return false;

    if (notification is ScrollMetricsNotification) {
      final isScrollable = notification.metrics.maxScrollExtent > 0;

      if (!isScrollable && !sidebarVisibility.value) {
        _resetVisibility();
      }

      return false;
    }

    if (notification is UserScrollNotification) {
      final direction = notification.direction;

      if (direction == ScrollDirection.idle ||
          direction == _lastDirection) {
        return false;
      }

      _lastDirection = direction;
      sidebarVisibility.value =
          direction == ScrollDirection.forward;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<Notification>(
      onNotification: _handleNotification,
      child: widget.child,
    );
  }
}
