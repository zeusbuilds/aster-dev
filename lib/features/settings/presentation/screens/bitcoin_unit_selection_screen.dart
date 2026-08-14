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
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: const CustomAppBar(
        title: 'Bitcoin Unit',
        leadingIcon: true,
        fallbackLocation: RoutePaths.settings,
      ),
      body: settings.when(
        skipLoadingOnRefresh: false,
        loading: () => const Center(
          child: GridLoader(semanticLabel: 'Loading Bitcoin units'),
        ),
        error: (error, stackTrace) => SettingsLoadFailure(
          failure: FailureMapper.from(error, stackTrace),
          onRetry: () => ref.read(settingsViewModelProvider.notifier).retry(),
        ),
        data: (state) {
          final selected = state.snapshot.preferences.bitcoinUnit;
          final saving = state.isSaving;
          return Stack(
            children: [
              SafeArea(
                top: false,
                child: ListView.separated(
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
                      onTap: saving
                          ? null
                          : () => unawaited(_select(context, ref, unit)),
                    );
                  },
                ),
              ),
              if (saving) const SettingsSavingIndicator(),
            ],
          );
        },
      ),
    );
  }

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    BitcoinUnit unit,
  ) async {
    final saved = await ref
        .read(settingsViewModelProvider.notifier)
        .selectBitcoinUnit(unit);
    if (!context.mounted) return;
    if (saved) {
      unawaited(context.haptics.trigger(HapticIntent.selection));
      context.pop();
      return;
    }
    final failure = ref.read(settingsViewModelProvider).value?.operationFailure;
    if (failure == null) return;
    unawaited(context.haptics.trigger(HapticIntent.error));
    context.toasts.show(
      title: 'Bitcoin unit not saved',
      message: failure.userMessage,
      variant: ToastVariant.failure,
    );
    ref.read(settingsViewModelProvider.notifier).clearOperationFailure();
  }
}
