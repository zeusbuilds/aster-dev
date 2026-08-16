import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/errors/errors.dart';
import '../feedback/feedback.dart';

/// A route-changing command owned by the currently visible screen.
typedef AsterNavigationCommand = FutureOr<void> Function();

/// Narrow command contract exposed by [AsterNavigationScope].
abstract interface class AsterNavigationCommandOwner {
  /// Whether a previously accepted command still owns this screen.
  bool get inFlight;

  /// Runs [command] only when this owner is idle.
  ///
  /// Ownership is acquired synchronously before tactile feedback and retained
  /// until the returned route future completes. Synchronous and asynchronous
  /// failures are reduced to an app-safe diagnostic and never escape as an
  /// unobserved future. Set [blocksRoutePop] for durable mutations whose result
  /// must remain owned by the current route; the pop veto is published before
  /// [command] starts, including within the initiating frame.
  Future<bool> run({
    required AsterNavigationCommand command,
    required String failureTitle,
    HapticIntent? hapticIntent = HapticIntent.lightImpact,
    bool blocksRoutePop = false,
  });
}

/// Gives all route affordances on one screen a single command owner.
///
/// This is deliberately screen-scoped. A process-global lock would remain held
/// while a pushed route is visible and incorrectly disable navigation within
/// that destination.
class AsterNavigationScope extends StatefulWidget {
  const AsterNavigationScope({super.key, required this.child});

  final Widget child;

  /// Returns the nearest owner and subscribes to its in-flight state.
  static AsterNavigationCommandOwner of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_AsterNavigationInherited>();
    if (inherited == null) {
      throw FlutterError(
        'Missing AsterNavigationScope. Route-changing controls that share a '
        'screen must be composed below one scope.',
      );
    }
    return inherited.owner;
  }

  /// Returns the nearest owner, if this surface has screen-scoped ownership.
  static AsterNavigationCommandOwner? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_AsterNavigationInherited>()
        ?.owner;
  }

  @override
  State<AsterNavigationScope> createState() => _AsterNavigationScopeState();
}

final class _AsterNavigationScopeState extends State<AsterNavigationScope>
    implements AsterNavigationCommandOwner {
  final ValueNotifier<bool> _routeCanPop = ValueNotifier<bool>(true);
  bool _inFlight = false;

  @override
  bool get inFlight => _inFlight;

  @override
  Future<bool> run({
    required AsterNavigationCommand command,
    required String failureTitle,
    HapticIntent? hapticIntent = HapticIntent.lightImpact,
    bool blocksRoutePop = false,
  }) async {
    if (_inFlight || !mounted) return false;
    if (blocksRoutePop) _routeCanPop.value = false;
    setState(() => _inFlight = true);
    if (hapticIntent case final intent?) {
      unawaited(context.haptics.trigger(intent));
    }

    try {
      await command();
      return true;
    } catch (error, stackTrace) {
      final failure = FailureMapper.from(error, stackTrace);
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: AppFailureException(failure),
          stack: stackTrace,
          library: 'UTEXO navigation',
          context: ErrorDescription('while changing application routes'),
        ),
      );
      if (mounted) {
        unawaited(context.haptics.trigger(HapticIntent.error));
        AsterFeedbackScope.maybeOf(context)?.toasts.show(
          title: failureTitle,
          message: failure.userMessage,
          variant: ToastVariant.failure,
        );
      }
      return false;
    } finally {
      if (mounted) {
        if (blocksRoutePop) _routeCanPop.value = true;
        setState(() => _inFlight = false);
      }
    }
  }

  @override
  void dispose() {
    _routeCanPop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AsterNavigationInherited(
      owner: this,
      inFlight: _inFlight,
      child: _AsterNavigationPopGuard(
        canPopNotifier: _routeCanPop,
        child: widget.child,
      ),
    );
  }
}

final class _AsterNavigationPopGuard extends StatefulWidget {
  const _AsterNavigationPopGuard({
    required this.canPopNotifier,
    required this.child,
  });

  final ValueListenable<bool> canPopNotifier;
  final Widget child;

  @override
  State<_AsterNavigationPopGuard> createState() =>
      _AsterNavigationPopGuardState();
}

final class _AsterNavigationPopGuardState
    extends State<_AsterNavigationPopGuard>
    implements PopEntry<Object?> {
  ModalRoute<dynamic>? _route;

  @override
  ValueListenable<bool> get canPopNotifier => widget.canPopNotifier;

  @override
  void onPopInvoked(bool didPop) {}

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {}

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextRoute = ModalRoute.of(context);
    if (identical(nextRoute, _route)) return;
    _route?.unregisterPopEntry(this);
    _route = nextRoute;
    _route?.registerPopEntry(this);
  }

  @override
  void didUpdateWidget(_AsterNavigationPopGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.canPopNotifier, widget.canPopNotifier)) return;
    _route?.unregisterPopEntry(this);
    _route?.registerPopEntry(this);
  }

  @override
  void dispose() {
    _route?.unregisterPopEntry(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

final class _AsterNavigationInherited extends InheritedWidget {
  const _AsterNavigationInherited({
    required this.owner,
    required this.inFlight,
    required super.child,
  });

  final AsterNavigationCommandOwner owner;
  final bool inFlight;

  @override
  bool updateShouldNotify(_AsterNavigationInherited oldWidget) {
    return inFlight != oldWidget.inFlight;
  }
}
