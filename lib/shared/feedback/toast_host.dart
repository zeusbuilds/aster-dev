import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../layout/layout.dart';
import '../motion/motion.dart';
import '../theme/theme.dart';
import '../widgets/custom_toast.dart';
import 'toast_controller.dart';
import 'toast_message.dart';

/// Renders the single active toast and owns its dismissal timer.
///
/// Place exactly one host below `MaterialApp.builder`. Queue state remains in
/// Riverpod, while animation and timer lifecycles remain with this widget.
class ToastHost extends ConsumerStatefulWidget {
  const ToastHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends ConsumerState<ToastHost> {
  Timer? _dismissTimer;
  int? _scheduledMessageId;

  @override
  void initState() {
    super.initState();
    ref.listenManual<ToastQueueState>(
      toastControllerProvider,
      (_, next) => _schedule(next.current),
      fireImmediately: true,
    );
  }

  void _schedule(ToastMessage? message) {
    if (_scheduledMessageId == message?.id) return;
    _dismissTimer?.cancel();
    _scheduledMessageId = message?.id;
    if (message == null) return;
    _dismissTimer = Timer(message.duration, () {
      if (!mounted) return;
      ref.read(toastControllerProvider.notifier).dismissCurrent(id: message.id);
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(
      toastControllerProvider.select((state) => state.current),
    );
    final transitionDuration = context.motionPolicy.duration(
      context.motion.toastTransitionDuration,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedPadding(
            duration: transitionDuration,
            curve: context.motion.toastCurve,
            padding: EdgeInsets.only(bottom: context.windowInsets.keyboard),
            child: AnimatedSwitcher(
              duration: transitionDuration,
              reverseDuration: transitionDuration,
              switchInCurve: context.motion.toastCurve,
              switchOutCurve: context.motion.toastCurve,
              transitionBuilder: (child, animation) {
                final slide = Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: current == null
                  ? const SizedBox.shrink(key: ValueKey('toast-empty'))
                  : CustomToast(
                      key: ValueKey(current.id),
                      title: current.title,
                      message: current.message,
                      variant: current.variant,
                      onDismiss: () => ref
                          .read(toastControllerProvider.notifier)
                          .dismissCurrent(id: current.id),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
