import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/wallet/domain/models/wallet_access_recovery.dart';
import '../../features/wallet/presentation/pages/wallet_unavailable_screen.dart';
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
    _isRetrying.value = true;
    try {
      final container = await widget.initialize();
      if (!mounted) {
        container.dispose();
        return;
      }
      _container.value = container;
      _failure.value = null;
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
    final failure = _failure.value;
    if (_isRetrying.value ||
        failure == null ||
        WalletAccessRecovery.forFailure(failure) == null) {
      return;
    }
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
                      child: StartupRevealScope(
                        splashVisible: _isSplashScreenVisible,
                        child: widget.child,
                      ),
                    );
                  },
                ),
                ListenableBuilder(
                  listenable: Listenable.merge([
                    _failure,
                    _isRetrying,
                    _isSplashScreenVisible,
                    widget.security,
                  ]),
                  builder: (context, _) => _buildOverlay(context),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    if (!_isSplashScreenVisible.value) return const SizedBox.shrink();
    final security = widget.security;
    final failure = _failure.value;
    // A retry after a pre-authentication storage failure can reach device
    // authentication for the first time. It must be possible to unlock even
    // if the user cancels the automatic system prompt during that retry.
    final locked =
        security != null &&
        (security.isObscured ||
            (security.isLocked && (security.initialized || failure == null)));
    if (!locked && failure != null) {
      return WalletUnavailableScreen(
        failure: failure,
        title: 'Wallet could not be opened',
        retrying: _isRetrying.value,
        onRetry: _retry,
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: context.appColors.transparentSurface,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: context.appColors.transparentSurface,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: locked
          ? AsterLockScreen(controller: security)
          : AnimatedSplashScreen(
              controller: _controller,
              colorTransition: _colorController,
            ),
    );
  }
}
