import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aster/shared/shared.dart';

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
  /// completes (typically `const Aster()`).
  final Widget child;

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader>
    with SingleTickerProviderStateMixin {
  final _isSplashScreenVisible = ValueNotifier(true);
  final _container = ValueNotifier<ProviderContainer?>(null);

  late final AnimationController _controller =
      AnimatedSplashScreen.createController(this);

  Future<void>? _loader;

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
    _loader ??= _load();
  }

  @override
  void dispose() {
    _isSplashScreenVisible.dispose();
    _container.value?.dispose();
    _container.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final container = await widget.initialize();

    _container.value = container;

    // Ensure the app underneath has been laid out, then play the reveal.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Future<void>.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _controller.forward().ignore();
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
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
            ValueListenableBuilder<bool>(
              valueListenable: _isSplashScreenVisible,
              builder: (context, isVisible, splash) {
                if (!isVisible) return const SizedBox.shrink();
                return splash!;
              },
              child: AnimatedSplashScreen(controller: _controller),
            ),
          ],
        ),
      ),
    );
  }
}
