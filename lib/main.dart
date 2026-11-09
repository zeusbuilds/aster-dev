import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/bootstrap/app_bootstrap.dart';
import 'core/bootstrap/app_loader.dart';
import 'core/core.dart';
import 'core/security/security_gate.dart';
import 'features/bridge/presentation/hosted_bridge_scope.dart';
import 'features/wallet/presentation/view_model/view_models.dart';
import 'features/wallet/presentation/widgets/widgets.dart';
import 'shared/shared.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  late SharedPreferences preferences;
  final security = SecurityController(
    PlatformDeviceAuthentication(),
    saveAppLock: (enabled) => preferences.setBool('security.appLock', enabled),
  );

  // Run ASAP so we can show the startup animation while bootstrapping.
  runApp(
    AppLoader(
      security: security,
      child: const AsterApp(),
      initialize: () async {
        preferences = await SharedPreferences.getInstance();
        if (!security.initialized) {
          security.loadAppLockPreference(
            preferences.getBool('security.appLock') ?? true,
          );
        }
        final container = createApplicationProviderContainer(
          preferences,
          securityController: security,
        );
        try {
          // Read only public metadata before auth. No credential inventory,
          // mnemonic read, native database open or wallet bootstrap happens yet.
          final profiles = await container.read(
            walletProfileStoreProvider.future,
          );
          final registry = await profiles.read();
          final snapshot = switch (registry) {
            AppSuccess(:final value) => value,
            AppFailureResult(:final failure) => throw AppFailureException(
              failure,
            ),
          };
          await security.initialize(hasWallet: snapshot.profiles.isNotEmpty);
          // Ensure the static Flutter gradient has painted before presenting
          // the native sheet. The native launch storyboard cannot host it.
          await WidgetsBinding.instance.endOfFrame;
          await security.waitForUnlock();
        } catch (_) {
          container.dispose();
          rethrow;
        }
        return bootstrapApplicationContainer(container);
      },
    ),
  );
}

/// Root Aster application and authoritative app-lifecycle observer.
class AsterApp extends ConsumerStatefulWidget {
  const AsterApp({super.key});

  @override
  ConsumerState<AsterApp> createState() => _AsterAppState();
}

class _AsterAppState extends ConsumerState<AsterApp>
    with WidgetsBindingObserver {
  late final SecurityController _security;
  bool _wasLocked = false;
  bool _preparingForeground = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _security = ref.read(securityControllerProvider);
    _wasLocked = _security.isLocked;
    _security.addListener(_securityChanged);
    ref.listenManual(
      walletViewModelProvider.select((state) => state.value?.activeWallet?.id),
      (_, walletId) {
        _security.updateWallet(walletId);
        ref.read(toastControllerProvider.notifier).updateWalletScope(walletId);
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _security.removeListener(_securityChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // AppLoader forwards visibility to security first. Native auth owns its
    // inactive/resumed transitions and must not recursively reopen the runtime.
    if (_security.isAuthenticating) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeAfterSecurityCheck());
      return;
    }
    unawaited(
      ref.read(walletLifecycleViewModelProvider.notifier).handle(state),
    );
  }

  Future<void> _resumeAfterSecurityCheck() async {
    if (_preparingForeground) return;
    _preparingForeground = true;
    try {
      final allowed = await _security.prepareForeground();
      if (mounted && allowed && _security.canAccessWallet) {
        await ref
            .read(walletLifecycleViewModelProvider.notifier)
            .handle(AppLifecycleState.resumed);
      }
    } finally {
      _preparingForeground = false;
    }
  }

  void _securityChanged() {
    if (_wasLocked == _security.isLocked) return;
    _wasLocked = _security.isLocked;
    if (_wasLocked) {
      ref.read(toastControllerProvider.notifier).discardMessagesForPopup();
      unawaited(
        ref
            .read(walletLifecycleViewModelProvider.notifier)
            .handle(AppLifecycleState.paused),
      );
    } else if (!_security.isObscured && !_preparingForeground) {
      unawaited(
        ref
            .read(walletLifecycleViewModelProvider.notifier)
            .handle(AppLifecycleState.resumed),
      );
    }
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
          child: SecurityGate(
            controller: _security,
            child: WalletLifecycleGate(
              state: lifecycle,
              onRetry: () => unawaited(
                ref.read(walletLifecycleViewModelProvider.notifier).retry(),
              ),
              child: HostedBridgeScope(
                navigatorKey: router.routerDelegate.navigatorKey,
                child: ToastHost(child: child ?? const SizedBox.shrink()),
              ),
            ),
          ),
        );
      },
    );
  }
}
