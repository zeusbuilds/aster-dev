import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/errors.dart';
import '../../../../shared/shared.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

/// Selects the app-wide Bitcoin denomination without changing stored values.
class BitcoinUnitSelectionScreen extends ConsumerWidget {
  const BitcoinUnitSelectionScreen({super.key});

  static const _exampleSatoshis = 12345678;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsViewModelProvider);
    final saving = settings.value?.isSaving ?? false;
    return AsterNavigationScope(
      child: Builder(
        builder: (context) {
          final navigation = AsterNavigationScope.of(context);
          final navigationLocked = saving || navigation.inFlight;
          return PopScope(
            canPop: !navigationLocked,
            child: Scaffold(
              backgroundColor: context.colorScheme.surface,
              appBar: CustomAppBar(
                title: 'Bitcoin Unit',
                leadingIcon: true,
                leadingEnabled: !navigationLocked,
                fallbackLocation: RoutePaths.settings,
              ),
              body: settings.when(
                skipLoadingOnRefresh: false,
                loading: () => const Center(
                  child: GridLoader(semanticLabel: 'Loading Bitcoin units'),
                ),
                error: (error, stackTrace) => SettingsLoadFailure(
                  failure: FailureMapper.from(error, stackTrace),
                  onRetry: () =>
                      ref.read(settingsViewModelProvider.notifier).retry(),
                ),
                data: (state) {
                  final selected = state.snapshot.preferences.bitcoinUnit;
                  return Stack(
                    children: [
                      SafeArea(
                        top: false,
                        bottom: false,
                        child: ListView.separated(
                          padding: EdgeInsets.only(
                            bottom:
                                context.windowInsets.bottomSafe +
                                context.spacing.lg,
                          ),
                          itemCount: BitcoinUnit.values.length,
                          separatorBuilder: (context, index) =>
                              const AsterDivider.inset(),
                          itemBuilder: (context, index) {
                            final unit = BitcoinUnit.values[index];
                            return SettingsChoiceRow(
                              title: unit.displayName,
                              subtitle: BitcoinAmountFormatter(unit: unit)
                                  .format(_exampleSatoshis),
                              selected: selected == unit,
                              onTap: navigationLocked
                                  ? null
                                  : () => unawaited(
                                      _select(context, ref, navigation, unit),
                                    ),
                            );
                          },
                        ),
                      ),
                      if (saving) const SettingsSavingIndicator(),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    AsterNavigationCommandOwner navigation,
    BitcoinUnit unit,
  ) async {
    final toasts = context.toasts;
    var saved = false;
    final accepted = await navigation.run(
      command: () async {
        saved = await ref
            .read(settingsViewModelProvider.notifier)
            .selectBitcoinUnit(unit);
        if (!context.mounted || saved) return;
        final failure = ref
            .read(settingsViewModelProvider)
            .value
            ?.operationFailure;
        if (failure == null) return;
        unawaited(context.haptics.trigger(HapticIntent.error));
        toasts.show(
          title: 'Bitcoin unit not saved',
          message: failure.userMessage,
          variant: ToastVariant.failure,
        );
        ref.read(settingsViewModelProvider.notifier).clearOperationFailure();
      },
      failureTitle: 'Bitcoin unit could not be saved',
      hapticIntent: null,
      blocksRoutePop: true,
    );
    if (!accepted || !saved || !context.mounted) return;
    unawaited(context.haptics.trigger(HapticIntent.selection));
    context.pop();
  }
}
