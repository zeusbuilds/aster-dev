import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        // Initialize database
        final databaseService = DatabaseService();
        await databaseService.init();

        final sharedPreferences = await SharedPreferences.getInstance();

        // Create a ProviderContainer for app runtime.
        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWith((ref) => sharedPreferences),
            databaseServiceProvider.overrideWith((ref) => databaseService),
          ],
        );

        // Run migration before the app starts reading wallet state.
        final walletRepository = container.read(walletRepositoryProvider);
        final migrationService = WalletMigrationService(walletRepository);
        await migrationService.migrateIfNeeded();

        return container;
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
    setState(() {
      _lifecycleState = state;
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final showSplashOverlay =
        _lifecycleState == AppLifecycleState.paused ||
        _lifecycleState == AppLifecycleState.inactive;

    return MaterialApp.router(
      title: AppConstants.appName,
      theme: AppTheme.light(),
      themeMode: ThemeMode.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            if (showSplashOverlay) const Positioned.fill(child: SplashScreen()),
          ],
        );
      },
    );
  }
}
