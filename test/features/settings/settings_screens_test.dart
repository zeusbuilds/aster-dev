import 'dart:convert';
import 'dart:ui' as ui;

import 'package:aster/core/core.dart';
import 'package:aster/features/settings/data/repository/repository.dart';
import 'package:aster/features/settings/domain/models/models.dart';
import 'package:aster/features/settings/presentation/screens/screens.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Bitcoin unit commits before closing and remains accessible', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repository = SettingsRepository(
      PreferencesService(await SharedPreferences.getInstance()),
      _CatalogAssetBundle(),
    );
    final haptics = _RecordingHaptics();
    final toasts = _RecordingToasts();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => context.push('/unit'),
                child: const Text('Open unit settings'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/unit',
          builder: (context, state) => const BitcoinUnitSelectionScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWith((ref) async => repository),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          builder: (context, child) => AsterFeedbackScope(
            haptics: haptics,
            toasts: toasts,
            child: child!,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open unit settings'));
    await tester.pumpAndSettle();

    expect(find.text('Satoshis'), findsOneWidget);
    expect(tester, meetsGuideline(androidTapTargetGuideline));
    expect(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(tester, meetsGuideline(textContrastGuideline));

    await tester.tap(find.text('Satoshis'));
    await tester.pumpAndSettle();

    expect(find.text('Open unit settings'), findsOneWidget);
    final persisted = await repository.load() as AppSuccess<SettingsSnapshot>;
    expect(persisted.value.preferences.bitcoinUnit, BitcoinUnit.sats);
    expect(haptics.intents, [HapticIntent.selection]);
    expect(toasts.messages, isEmpty);
  });

  testWidgets('advanced disclosures are disabled without auth policy', (
    tester,
  ) async {
    final haptics = _RecordingHaptics();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AsterFeedbackScope(
          haptics: haptics,
          toasts: _RecordingToasts(),
          child: const AdvancedSettingsScreen(),
        ),
      ),
    );

    final exportSemantics = tester.getSemantics(find.text('Export xpubs'));
    final seedSemantics = tester.getSemantics(find.text('Check seed phrase'));
    expect(exportSemantics.flagsCollection.isEnabled, ui.Tristate.isFalse);
    expect(seedSemantics.flagsCollection.isEnabled, ui.Tristate.isFalse);
    expect(find.text('Unavailable'), findsNWidgets(2));
    expect(haptics.intents, isEmpty);
  });
}

final class _CatalogAssetBundle extends CachingAssetBundle {
  static const _sources = {
    'assets/data/currencies.json':
        '[{"name":"United States Dollar","symbol":"\$","code":"USD","countryCode":"US"}]',
    'assets/data/countries.json': '[{"name":"United States","code":"US"}]',
  };

  @override
  Future<ByteData> load(String key) async {
    final bytes = Uint8List.fromList(utf8.encode(_sources[key]!));
    return ByteData.sublistView(bytes);
  }
}

final class _RecordingHaptics implements HapticFeedbackService {
  final intents = <HapticIntent>[];

  @override
  Future<void> trigger(HapticIntent intent) async => intents.add(intent);
}

final class _RecordingToasts implements ToastPresentationService {
  final messages = <String>[];

  @override
  void dismissCurrent({int? id}) {}

  @override
  bool show({
    required String title,
    required ToastVariant variant,
    String? message,
    Duration? duration,
  }) {
    messages.add(title);
    return true;
  }
}
