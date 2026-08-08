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
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: const CustomAppBar(title: 'Select Currency', leadingIcon: true),
      body: settings.when(
        skipLoadingOnRefresh: false,
        data: (state) => _CurrencyList(state: state),
        loading: () => const _CurrencyLoading(),
        error: (error, _) => _SettingsLoadFailure(
          message: FailureMapper.from(error, StackTrace.current).userMessage,
          onRetry: () => ref.read(settingsViewModelProvider.notifier).retry(),
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
    final saving = state.operation == SettingsOperation.currency;
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
        if (saving) const _SettingsSavingIndicator(),
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
    unawaited(context.haptics.trigger(HapticIntent.error));
    final failure = ref.read(settingsViewModelProvider).value?.operationFailure;
    if (failure != null) {
      context.toasts.show(
        title: 'Currency not saved',
        message: failure.userMessage,
        variant: ToastVariant.failure,
      );
    }
  }
}

class _CurrencyLoading extends StatelessWidget {
  const _CurrencyLoading();

  @override
  Widget build(BuildContext context) {
    return AppSkeletonizer(
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
    );
  }
}

class _SettingsLoadFailure extends StatelessWidget {
  const _SettingsLoadFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(context.spacing.screenPadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
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
      ),
    );
  }
}

class _SettingsSavingIndicator extends StatelessWidget {
  const _SettingsSavingIndicator();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Saving preference',
      child: const LinearProgressIndicator(),
    );
  }
}
