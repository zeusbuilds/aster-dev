import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/bootstrap/app_bootstrap.dart';
import 'core/bootstrap/app_loader.dart';
import 'core/core.dart';
import 'shared/shared.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Run ASAP so we can show the startup animation while bootstrapping.
  runApp(
    AppLoader(
      child: const Aster(),
      initialize: () async {
        final sharedPreferences = await SharedPreferences.getInstance();
        return bootstrapApplication(sharedPreferences);
      },
    ),
  );
}

/// Main application widget
///
/// Sets up MaterialApp with routing, theming, and Riverpod provider scope.
///
/// This is the root widget of the application.
class Aster extends ConsumerStatefulWidget {
  const Aster({super.key});

  @override
  ConsumerState<Aster> createState() => _AsterState();
}

class _AsterState extends ConsumerState<Aster> with WidgetsBindingObserver {
  AppLifecycleState? _lifecycleState;
  Future<void> _lifecycleTail = Future<void>.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleTail = _lifecycleTail.then((_) => _applyWalletLifecycle(state));
    unawaited(_lifecycleTail);
    setState(() {
      _lifecycleState = state;
    });
  }

  Future<void> _applyWalletLifecycle(AppLifecycleState state) async {
    try {
      final repository = await ref.read(walletRepositoryProvider.future);
      final result = switch (state) {
        AppLifecycleState.resumed => await repository.resume(),
        AppLifecycleState.hidden ||
        AppLifecycleState.paused => await repository.suspend(),
        AppLifecycleState.detached => await repository.dispose(),
        AppLifecycleState.inactive => const AppResult<void>.success(null),
      };
      if (result case AppFailureResult<void>(:final failure)) {
        if (kDebugMode) {
          debugPrint(
            'Wallet lifecycle failed: ${failure.code} (${failure.kind.name})',
          );
        }
      }
    } catch (_) {
      if (kDebugMode) debugPrint('Wallet lifecycle provider failed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final haptics = ref.watch(hapticFeedbackServiceProvider);
    final toasts = ref.watch(toastControllerProvider.notifier);
    final showSplashOverlay =
        _lifecycleState == AppLifecycleState.hidden ||
        _lifecycleState == AppLifecycleState.paused ||
        _lifecycleState == AppLifecycleState.inactive;

    return MaterialApp.router(
      title: AppConstants.appName,
      theme: AppTheme.light(),
      themeMode: ThemeMode.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return AsterFeedbackScope(
          haptics: haptics,
          toasts: toasts,
          child: ToastHost(
            child: Stack(
              children: [
                ?child,
                if (showSplashOverlay)
                  const Positioned.fill(child: SplashScreen()),
              ],
            ),
          ),
        );
      },
    );
  }
}
