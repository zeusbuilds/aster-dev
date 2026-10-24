import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class _ToastHostState extends ConsumerState<ToastHost>
    with WidgetsBindingObserver {
  Timer? _dismissTimer;
  Stopwatch? _visibilityStopwatch;
  Duration? _remainingVisibility;
  int? _scheduledMessageId;
  late bool _isForeground;
  bool _dependenciesReady = false;
  bool _accessibleNavigation = false;
  bool _keyboardFocused = false;
  bool _assistiveFocused = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dependenciesReady = true;
    _accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    _updateCountdown();
  }

  @override
  void initState() {
    super.initState();
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _isForeground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual<ToastQueueState>(
      toastControllerProvider,
      (_, next) => _schedule(next.current),
      fireImmediately: true,
    );
  }

  void _schedule(ToastMessage? message) {
    if (_scheduledMessageId == message?.id) return;
    _cancelCountdown();
    _scheduledMessageId = message?.id;
    _keyboardFocused = false;
    _assistiveFocused = false;
    if (message == null) return;
    _remainingVisibility = message.duration;
    _startCountdown();
  }

  void _startCountdown() {
    final id = _scheduledMessageId;
    final remaining = _remainingVisibility;
    if (!_isForeground ||
        !_dependenciesReady ||
        _accessibleNavigation ||
        _keyboardFocused ||
        _assistiveFocused ||
        id == null ||
        remaining == null ||
        _dismissTimer != null) {
      return;
    }

    _visibilityStopwatch = GestureBinding.instance.samplingClock.stopwatch()
      ..start();
    _dismissTimer = Timer(remaining, () => _completeCountdown(id));
  }

  void _updateCountdown() {
    if (_accessibleNavigation || _keyboardFocused || _assistiveFocused) {
      _pauseCountdown();
    } else {
      _startCountdown();
    }
  }

  void _onKeyboardFocus(int id, bool focused) {
    if (id != _scheduledMessageId) return;
    _keyboardFocused = focused;
    _updateCountdown();
  }

  void _onAssistiveFocus(int id) {
    if (id != _scheduledMessageId) return;
    // Speech completion is not observable. Once assistive focus reaches a
    // message, retain it until explicit dismissal, even if focus moves away.
    _assistiveFocused = true;
    _updateCountdown();
  }

  void _pauseCountdown() {
    final timer = _dismissTimer;
    final stopwatch = _visibilityStopwatch;
    final remaining = _remainingVisibility;
    if (timer == null || stopwatch == null || remaining == null) return;

    timer.cancel();
    _dismissTimer = null;
    stopwatch.stop();
    final elapsed = stopwatch.elapsed;
    _visibilityStopwatch = null;
    _remainingVisibility = elapsed >= remaining
        ? Duration.zero
        : remaining - elapsed;
  }

  void _completeCountdown(int id) {
    _dismissTimer = null;
    _visibilityStopwatch?.stop();
    _visibilityStopwatch = null;
    _remainingVisibility = Duration.zero;
    if (!mounted || !_isForeground || _scheduledMessageId != id) return;
    ref.read(toastControllerProvider.notifier).dismissCurrent(id: id);
  }

  void _cancelCountdown() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _visibilityStopwatch?.stop();
    _visibilityStopwatch = null;
    _remainingVisibility = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground = state == AppLifecycleState.resumed;
    if (_isForeground == isForeground) return;
    _isForeground = isForeground;
    if (isForeground) {
      _startCountdown();
    } else {
      _pauseCountdown();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelCountdown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (current, scopeGeneration) = ref.watch(
      toastControllerProvider.select(
        (state) => (state.current, state.scopeGeneration),
      ),
    );
    final transitionDuration = context.motionPolicy.duration(
      context.motion.toastTransitionDuration,
    );

    return CallbackShortcuts(
      bindings: {
        if (current != null)
          const SingleActivator(LogicalKeyboardKey.escape): () => ref
              .read(toastControllerProvider.notifier)
              .dismissCurrent(id: current.id),
      },
      child: Stack(
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
                key: ValueKey(scopeGeneration),
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
                    : Focus(
                        key: ValueKey(current.id),
                        canRequestFocus: false,
                        onFocusChange: (focused) =>
                            _onKeyboardFocus(current.id, focused),
                        child: CustomToast(
                          title: current.title,
                          message: current.message,
                          variant: current.variant,
                          onAccessibilityFocus: () =>
                              _onAssistiveFocus(current.id),
                          onDismiss: () => ref
                              .read(toastControllerProvider.notifier)
                              .dismissCurrent(id: current.id),
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
