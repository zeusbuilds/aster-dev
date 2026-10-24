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
                title: 'Select Currency',
                leadingIcon: true,
                leadingEnabled: !navigationLocked,
                fallbackLocation: RoutePaths.settings,
              ),
              body: settings.when(
                skipLoadingOnRefresh: false,
                data: (state) =>
                    _CurrencyList(state: state, navigation: navigation),
                loading: () => const _CurrencyLoading(),
                error: (error, stackTrace) => SettingsLoadFailure(
                  failure: FailureMapper.from(error, stackTrace),
                  onRetry: () =>
                      ref.read(settingsViewModelProvider.notifier).retry(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CurrencyList extends ConsumerWidget {
  const _CurrencyList({required this.state, required this.navigation});

  final SettingsState state;
  final AsterNavigationCommandOwner navigation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCode = state.snapshot.preferences.currencyCode;
    final saving = state.isSaving;
    return Stack(
      children: [
        SafeArea(
          top: false,
          bottom: false,
          child: ListView.separated(
            padding: EdgeInsets.only(
              bottom: context.windowInsets.bottomSafe + context.spacing.lg,
            ),
            itemCount: state.snapshot.currencies.length,
            separatorBuilder: (context, index) => const AsterDivider.inset(),
            itemBuilder: (context, index) {
              final currency = state.snapshot.currencies[index];
              return CurrencySelectOptionRow(
                currency: currency,
                selected: selectedCode == currency.code,
                onTap: saving || navigation.inFlight
                    ? null
                    : () => unawaited(
                        _selectCurrency(
                          context,
                          ref,
                          navigation,
                          currency.code,
                        ),
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
    AsterNavigationCommandOwner navigation,
    String code,
  ) async {
    final toasts = context.toasts;
    var saved = false;
    final accepted = await navigation.run(
      command: () async {
        saved = await ref
            .read(settingsViewModelProvider.notifier)
            .selectCurrency(code);
        if (!context.mounted || saved) return;
        final failure = ref
            .read(settingsViewModelProvider)
            .value
            ?.operationFailure;
        if (failure == null) return;
        unawaited(context.haptics.trigger(HapticIntent.error));
        toasts.show(
          title: 'Currency not saved',
          message: failure.userMessage,
          variant: ToastVariant.failure,
        );
        ref.read(settingsViewModelProvider.notifier).clearOperationFailure();
      },
      failureTitle: 'Currency could not be saved',
      hapticIntent: null,
      blocksRoutePop: true,
    );
    if (!accepted || !saved || !context.mounted) return;
    unawaited(context.haptics.trigger(HapticIntent.selection));
    context.pop();
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
          padding: EdgeInsets.only(
            bottom: context.windowInsets.bottomSafe + context.spacing.lg,
          ),
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
