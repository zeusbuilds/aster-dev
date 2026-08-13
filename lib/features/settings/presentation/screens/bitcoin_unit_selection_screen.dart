import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/errors.dart';
import '../../../../shared/shared.dart';
import '../models/models.dart';
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
      appBar: const CustomAppBar(title: 'Bitcoin Unit', leadingIcon: true),
      body: settings.when(
        skipLoadingOnRefresh: false,
        loading: () => const Center(child: GridLoader()),
        error: (error, stackTrace) => _UnitLoadFailure(
          message: FailureMapper.from(error, stackTrace).userMessage,
          onRetry: () => ref.read(settingsViewModelProvider.notifier).retry(),
        ),
        data: (state) {
          final selected = state.snapshot.preferences.bitcoinUnit;
          final saving = state.operation == SettingsOperation.bitcoinUnit;
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
              if (saving)
                Semantics(
                  liveRegion: true,
                  label: 'Saving preference',
                  child: LinearProgressIndicator(),
                ),
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

class _UnitLoadFailure extends StatelessWidget {
  const _UnitLoadFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(context.spacing.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: context.type.errorMessage,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: context.spacing.xxl),
            CustomButton(text: 'Retry', onTap: onRetry),
          ],
        ),
      ),
    );
  }
}
