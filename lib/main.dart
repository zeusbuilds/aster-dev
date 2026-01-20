import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gdk_flutter/gdk_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/core.dart';
import 'shared/shared.dart';

Future<void> _initializeGdk() async {
  try {
    String? dataDir;
    String? torDir;

    if (Platform.isIOS || Platform.isAndroid) {
      final docDir = await getApplicationDocumentsDirectory();
      dataDir = '${docDir.path}/gdk_data';
      torDir = '${docDir.path}/gdk_tor';
    }

    await GDK.initialize(dataDir: dataDir, torDir: torDir, logLevel: 'info');
  } catch (e, stackTrace) {
    // ignore: avoid_print
    print('GDK initialization error: $e');
    // ignore: avoid_print
    print(stackTrace);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _initializeGdk();

  // Initialize database
  final databaseService = DatabaseServiceImpl();
  await databaseService.init();

  final sharedPreferences = await SharedPreferences.getInstance();

  // Create a temporary ProviderContainer for initial setup
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWith((ref) => sharedPreferences),
      databaseServiceProvider.overrideWith((ref) => databaseService),
    ],
  );

  // Initialize and run migration service
  final walletRepository = container.read(walletRepositoryProvider);
  final migrationService = WalletMigrationService(walletRepository);
  await migrationService.migrateIfNeeded();

  runApp(UncontrolledProviderScope(container: container, child: const Aster()));
}

/// Main application widget
///
/// Sets up MaterialApp with routing, theming, and Riverpod provider scope.
///
/// This is the root widget of the application.
class Aster extends ConsumerWidget {
  const Aster({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: AppConstants.appName,
      theme: AppTheme.light(),
      darkTheme: AppTheme.light(),
      themeMode: ThemeMode.light,
      routerConfig: ref.watch(appRouterProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}
