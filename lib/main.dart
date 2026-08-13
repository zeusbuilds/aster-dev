import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/bootstrap/app_bootstrap.dart';
import 'core/bootstrap/app_loader.dart';
import 'core/core.dart';
import 'features/wallet/presentation/view_model/view_models.dart';
import 'features/wallet/presentation/widgets/widgets.dart';
import 'shared/shared.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Run ASAP so we can show the startup animation while bootstrapping.
  runApp(
    AppLoader(
      child: const UtexoApp(),
      initialize: () async {
        final sharedPreferences = await SharedPreferences.getInstance();
        return bootstrapApplication(sharedPreferences);
      },
    ),
  );
}

/// Root UTEXO application and authoritative app-lifecycle observer.
class UtexoApp extends ConsumerStatefulWidget {
  const UtexoApp({super.key});

  @override
  ConsumerState<UtexoApp> createState() => _UtexoAppState();
}

class _UtexoAppState extends ConsumerState<UtexoApp>
    with WidgetsBindingObserver {
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
    unawaited(
      ref.read(walletLifecycleViewModelProvider.notifier).handle(state),
    );
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final haptics = ref.watch(hapticFeedbackServiceProvider);
    final toasts = ref.watch(toastControllerProvider.notifier);
    final lifecycle = ref.watch(walletLifecycleViewModelProvider);

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
          child: WalletLifecycleGate(
            state: lifecycle,
            onRetry: () => unawaited(
              ref.read(walletLifecycleViewModelProvider.notifier).retry(),
            ),
            child: ToastHost(child: child ?? const SizedBox.shrink()),
          ),
        );
      },
    );
  }
}
