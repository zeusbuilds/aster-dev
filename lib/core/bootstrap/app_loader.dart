import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/shared.dart';
import '../errors/errors.dart';
import '../security/security_controller.dart';
import '../security/security_gate.dart';

const _bootstrapMotion = AsterMotion();

/// Shows the animated startup splash while bootstrapping app dependencies.
///
/// Once initialization is complete, the animation plays and reveals the app
/// underneath; the splash overlay is removed when the animation completes.
class AppLoader extends StatefulWidget {
  const AppLoader({
    super.key,
    required this.initialize,
    required this.child,
    this.security,
  });

  final SecurityController? security;

  /// Callback that performs all app bootstrapping and returns a ready
  /// [ProviderContainer].
  final Future<ProviderContainer> Function() initialize;

  /// The root widget of the application to display once initialization
  /// completes (typically `const AsterApp()`).
  final Widget child;

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _isSplashScreenVisible = ValueNotifier(true);
  final _container = ValueNotifier<ProviderContainer?>(null);
  final _failure = ValueNotifier<AppFailure?>(null);
  final _isRetrying = ValueNotifier(false);

  late final AnimationController _controller =
      AnimatedSplashScreen.createController(this);
  late final AnimationController _colorController =
      AnimatedSplashScreen.createColorTransitionController(this);

  Future<void>? _loader;
  Timer? _revealTimer;
  int _revealRevision = 0;
  bool _revealScheduled = false;
  bool _revealRunning = false;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    _lifecycle =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.security?.addListener(_securityChanged);
    _controller.addStatusListener((status) {
      _isSplashScreenVisible.value = !status.isCompleted;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = context.motionPolicy.duration(
      _bootstrapMotion.splashRevealDuration,
    );
    _colorController.duration = context.motionPolicy.duration(
      _bootstrapMotion.splashColorTransitionDuration,
    );
    _loader ??= _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.security?.removeListener(_securityChanged);
    _isSplashScreenVisible.dispose();
    _failure.dispose();
    _isRetrying.dispose();
    _revealTimer?.cancel();
    _container.value?.dispose();
    _container.dispose();
    _controller.dispose();
    _colorController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    widget.security?.handleLifecycle(state);
    if (!_isSplashScreenVisible.value) return;
    if (!_canReveal) {
      _resetReveal();
    } else if (_container.value != null) {
      _scheduleReveal();
    }
  }

  bool get _canReveal =>
      _lifecycle == AppLifecycleState.resumed &&
      (widget.security == null ||
          (!widget.security!.isLocked &&
              !widget.security!.isObscured &&
              !widget.security!.isAuthenticating));

  void _securityChanged() {
    if (!mounted || !_isSplashScreenVisible.value) return;
    if (!_canReveal) {
      _resetReveal();
    } else if (_container.value != null) {
      _scheduleReveal();
    }
  }

  void _resetReveal() {
    _revealRevision += 1;
    _revealTimer?.cancel();
    _revealTimer = null;
    _revealScheduled = false;
    _revealRunning = false;
    _controller.reset();
    _colorController.reset();
  }

  bool _canPlayReveal(int revision) =>
      mounted &&
      revision == _revealRevision &&
      _canReveal &&
      _container.value != null &&
      _failure.value == null &&
      _isSplashScreenVisible.value;

  void _scheduleReveal() {
    if (_revealScheduled ||
        _revealRunning ||
        !_canPlayReveal(_revealRevision)) {
      return;
    }
    _revealScheduled = true;
    final revision = _revealRevision;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_canPlayReveal(revision)) return;
      if (context.motionPolicy.reduceMotion) {
        _revealScheduled = false;
        _revealRunning = true;
        unawaited(_playReveal(revision));
        return;
      }
      _revealTimer = Timer(
        context.motionPolicy.duration(_bootstrapMotion.bootstrapRevealDelay),
        () {
          _revealTimer = null;
          if (!_canPlayReveal(revision)) return;
          _revealScheduled = false;
          _revealRunning = true;
          unawaited(_playReveal(revision));
        },
      );
    });
  }

  Future<void> _playReveal(int revision) async {
    try {
      if (context.motionPolicy.reduceMotion) {
        _colorController.value = 1;
        _controller.value = 1;
        return;
      }
      await _colorController.forward().orCancel;
      if (!_canPlayReveal(revision)) return;
      await _controller.forward().orCancel;
    } on TickerCanceled {
      // Locking, backgrounding and disposal cancel both phases deliberately.
    } finally {
      if (revision == _revealRevision) _revealRunning = false;
    }
  }

  Future<void> _load() async {
    _failure.value = null;
    _isRetrying.value = true;
    try {
      final container = await widget.initialize();
      if (!mounted) {
        container.dispose();
        return;
      }
      _container.value = container;
      _scheduleReveal();
    } catch (error, stackTrace) {
      if (!mounted) return;
      final failure = FailureMapper.from(
        error,
        stackTrace,
        fallbackCode: 'app_bootstrap_failed',
      );
      if (kDebugMode) {
        developer.log(
          'Bootstrap failed: ${failure.code} (${failure.kind.name})',
          name: 'aster.bootstrap',
        );
      }
      _failure.value = failure;
    } finally {
      if (mounted) _isRetrying.value = false;
    }
  }

  void _retry() {
    if (_isRetrying.value || _failure.value?.retryable != true) return;
    _resetReveal();
    _isSplashScreenVisible.value = true;
    _loader = _load();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.light(),
      child: Builder(
        builder: (context) {
          return Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                ValueListenableBuilder<ProviderContainer?>(
                  valueListenable: _container,
                  builder: (context, container, _) {
                    if (container == null) {
                      return const SizedBox.expand();
                    }

                    return UncontrolledProviderScope(
                      container: container,
                      child: widget.child,
                    );
                  },
                ),
                ValueListenableBuilder<AppFailure?>(
                  valueListenable: _failure,
                  builder: (context, failure, _) {
                    if (failure != null) {
                      return _BootstrapFailureView(
                        failure: failure,
                        retrying: _isRetrying,
                        onRetry: _retry,
                      );
                    }
                    return ValueListenableBuilder<bool>(
                      valueListenable: _isSplashScreenVisible,
                      builder: (context, isVisible, splash) {
                        if (!isVisible) return const SizedBox.shrink();
                        return splash!;
                      },
                      child: AnnotatedRegion<SystemUiOverlayStyle>(
                        value: SystemUiOverlayStyle(
                          statusBarColor: context.appColors.transparentSurface,
                          statusBarIconBrightness: Brightness.dark,
                          statusBarBrightness: Brightness.light,
                          systemNavigationBarColor:
                              context.appColors.transparentSurface,
                          systemNavigationBarIconBrightness: Brightness.dark,
                        ),
                        child: widget.security == null
                            ? AnimatedSplashScreen(
                                controller: _controller,
                                colorTransition: _colorController,
                              )
                            : ListenableBuilder(
                                listenable: widget.security!,
                                builder: (context, _) =>
                                    widget.security!.isLocked ||
                                        widget.security!.isObscured
                                    ? AsterLockScreen(
                                        controller: widget.security!,
                                      )
                                    : AnimatedSplashScreen(
                                        controller: _controller,
                                        colorTransition: _colorController,
                                      ),
                              ),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BootstrapFailureView extends StatelessWidget {
  const _BootstrapFailureView({
    required this.failure,
    required this.retrying,
    required this.onRetry,
  });

  final AppFailure failure;
  final ValueListenable<bool> retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final themedSpacing = context.spacing;
    final surface = context.colorScheme.surface;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: context.appColors.transparentSurface,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: surface,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Material(
        color: surface,
        child: SafeArea(
          bottom: false,
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                themedSpacing.screenPadding,
                themedSpacing.screenPadding,
                themedSpacing.screenPadding,
                themedSpacing.screenPadding + context.windowInsets.bottomSafe,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: context.icons.xl,
                    color: context.appColors.danger,
                  ),
                  SizedBox(height: themedSpacing.lg),
                  Text(
                    'Wallet could not be opened',
                    style: context.type.title,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: themedSpacing.sm),
                  Semantics(
                    container: true,
                    liveRegion: true,
                    label: failure.userMessage,
                    excludeSemantics: true,
                    child: Text(
                      failure.userMessage,
                      style: context.type.errorMessage,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (failure.retryable) ...[
                    SizedBox(height: themedSpacing.xxl),
                    ValueListenableBuilder<bool>(
                      valueListenable: retrying,
                      builder: (context, loading, _) {
                        return CustomButton(
                          text: 'Retry',
                          loading: loading,
                          onTap: loading ? null : onRetry,
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
