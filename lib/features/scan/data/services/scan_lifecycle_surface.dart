import 'package:flutter/material.dart';

/// Binds an opaque camera view to widget and application lifecycle events.
///
/// Camera state remains owned by the Scan session. This implementation widget
/// only forwards attachment and lifecycle facts and is not exported from the
/// feature service barrel.
final class ScanLifecycleSurface extends StatefulWidget {
  const ScanLifecycleSurface({
    super.key,
    required this.owner,
    required this.onAttach,
    required this.onDetach,
    required this.onLifecycleChanged,
    required this.child,
  });

  final Object owner;
  final VoidCallback onAttach;
  final VoidCallback onDetach;
  final ValueChanged<AppLifecycleState> onLifecycleChanged;
  final Widget child;

  @override
  State<ScanLifecycleSurface> createState() => _ScanLifecycleSurfaceState();
}

final class _ScanLifecycleSurfaceState extends State<ScanLifecycleSurface>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _forwardCurrentLifecycle();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onAttach();
    });
  }

  @override
  void didUpdateWidget(ScanLifecycleSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.owner, widget.owner)) return;
    oldWidget.onDetach();
    _forwardCurrentLifecycle();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onAttach();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.onLifecycleChanged(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.onDetach();
    super.dispose();
  }

  void _forwardCurrentLifecycle() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null) widget.onLifecycleChanged(lifecycle);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
