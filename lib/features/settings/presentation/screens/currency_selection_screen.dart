import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/errors.dart';
import '../../../../shared/shared.dart';
import '../../domain/models/models.dart';
import '../models/models.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

/// Persists the fiat currency used for app-wide conversions.
class CurrencySelectionScreen extends ConsumerWidget {
  const CurrencySelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsViewModelProvider);
    final saving = settings.value?.isSaving ?? false;
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        backgroundColor: context.colorScheme.surface,
        appBar: CustomAppBar(
          title: 'Select Currency',
          leadingIcon: true,
          leadingEnabled: !saving,
          fallbackLocation: RoutePaths.settings,
        ),
        body: settings.when(
          skipLoadingOnRefresh: false,
          data: (state) => _CurrencyList(state: state),
          loading: () => const _CurrencyLoading(),
          error: (error, stackTrace) => SettingsLoadFailure(
            failure: FailureMapper.from(error, stackTrace),
            onRetry: () => ref.read(settingsViewModelProvider.notifier).retry(),
          ),
        ),
      ),
    );
  }
}

class _CurrencyList extends ConsumerWidget {
  const _CurrencyList({required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCode = state.snapshot.preferences.currencyCode;
    final saving = state.isSaving;
    return Stack(
      children: [
        SafeArea(
          top: false,
          minimum: EdgeInsets.only(bottom: context.spacing.lg),
          child: ListView.separated(
            itemCount: state.snapshot.currencies.length,
            separatorBuilder: (context, index) => const AsterDivider.inset(),
            itemBuilder: (context, index) {
              final currency = state.snapshot.currencies[index];
              return CurrencySelectOptionRow(
                currency: currency,
                selected: selectedCode == currency.code,
                onTap: saving
                    ? null
                    : () => unawaited(
                        _selectCurrency(context, ref, currency.code),
                      ),
              );
            },
          ),
        ),
        if (saving) const SettingsSavingIndicator(),
      ],
    );
  }

  Future<void> _selectCurrency(
    BuildContext context,
    WidgetRef ref,
    String code,
  ) async {
    final saved = await ref
        .read(settingsViewModelProvider.notifier)
        .selectCurrency(code);
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
      title: 'Currency not saved',
      message: failure.userMessage,
      variant: ToastVariant.failure,
    );
    ref.read(settingsViewModelProvider.notifier).clearOperationFailure();
  }
}

class _CurrencyLoading extends StatelessWidget {
  const _CurrencyLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Loading currencies',
      excludeSemantics: true,
      child: AppSkeletonizer(
        enabled: true,
        child: ListView.separated(
          itemCount: 8,
          separatorBuilder: (context, index) => const AsterDivider.inset(),
          itemBuilder: (context, index) => CurrencySelectOptionRow(
            currency: FiatCurrency(
              name: 'Loading currency',
              symbol: r'$',
              code: 'USD',
              countryCode: 'US',
            ),
            selected: false,
          ),
        ),
      ),
    );
  }
}
