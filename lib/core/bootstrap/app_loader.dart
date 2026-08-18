import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/shared.dart';
import '../errors/errors.dart';

const _bootstrapMotion = AsterMotion();

/// Shows the animated startup splash while bootstrapping app dependencies.
///
/// Once initialization is complete, the animation plays and reveals the app
/// underneath; the splash overlay is removed when the animation completes.
class AppLoader extends StatefulWidget {
  const AppLoader({super.key, required this.initialize, required this.child});

  /// Callback that performs all app bootstrapping and returns a ready
  /// [ProviderContainer].
  final Future<ProviderContainer> Function() initialize;

  /// The root widget of the application to display once initialization
  /// completes (typically `const UtexoApp()`).
  final Widget child;

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader>
    with SingleTickerProviderStateMixin {
  final _isSplashScreenVisible = ValueNotifier(true);
  final _container = ValueNotifier<ProviderContainer?>(null);
  final _failure = ValueNotifier<AppFailure?>(null);
  final _isRetrying = ValueNotifier(false);

  late final AnimationController _controller =
      AnimatedSplashScreen.createController(this);

  Future<void>? _loader;
  Timer? _revealTimer;

  @override
  void initState() {
    super.initState();
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
    _loader ??= _load();
  }

  @override
  void dispose() {
    _isSplashScreenVisible.dispose();
    _failure.dispose();
    _isRetrying.dispose();
    _revealTimer?.cancel();
    _container.value?.dispose();
    _container.dispose();
    _controller.dispose();
    super.dispose();
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
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _revealTimer?.cancel();
        _revealTimer = Timer(
          context.motionPolicy.duration(_bootstrapMotion.bootstrapRevealDelay),
          () {
            if (mounted) _controller.forward().ignore();
          },
        );
      });
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
          name: 'utexo.bootstrap',
        );
      }
      _failure.value = failure;
    } finally {
      if (mounted) _isRetrying.value = false;
    }
  }

  void _retry() {
    if (_isRetrying.value || _failure.value?.retryable != true) return;
    _controller.reset();
    _isSplashScreenVisible.value = true;
    _loader = _load();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.light(),
      child: Builder(
        builder: (context) {
          final colors = context.appColors;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              systemNavigationBarColor: colors.transparentSurface,
              systemNavigationBarIconBrightness: Brightness.light,
            ),
            child: Directionality(
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
                        child: AnimatedSplashScreen(controller: _controller),
                      );
                    },
                  ),
                ],
              ),
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
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(themedSpacing.screenPadding),
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
                  AsterStatusMessage(failure.userMessage, announce: true),
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
