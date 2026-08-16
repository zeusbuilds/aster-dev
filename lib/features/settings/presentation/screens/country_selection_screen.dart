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

/// Persists the region used for localization and regional defaults.
class CountrySelectionScreen extends ConsumerWidget {
  const CountrySelectionScreen({super.key});

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
                title: 'Select Region',
                leadingIcon: true,
                leadingEnabled: !navigationLocked,
                fallbackLocation: RoutePaths.settings,
              ),
              body: settings.when(
                skipLoadingOnRefresh: false,
                data: (state) =>
                    _RegionList(state: state, navigation: navigation),
                loading: () => const _RegionLoading(),
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

class _RegionList extends ConsumerWidget {
  const _RegionList({required this.state, required this.navigation});

  final SettingsState state;
  final AsterNavigationCommandOwner navigation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCode = state.snapshot.preferences.regionCode;
    final saving = state.isSaving;
    return Stack(
      children: [
        SafeArea(
          top: false,
          minimum: EdgeInsets.only(bottom: context.spacing.lg),
          child: ListView.separated(
            itemCount: state.snapshot.regions.length,
            separatorBuilder: (context, index) => const AsterDivider.inset(),
            itemBuilder: (context, index) {
              final region = state.snapshot.regions[index];
              return CountrySelectOptionRow(
                country: region,
                selected: selectedCode == region.code,
                onTap: saving || navigation.inFlight
                    ? null
                    : () => unawaited(
                        _selectRegion(context, ref, navigation, region.code),
                      ),
              );
            },
          ),
        ),
        if (saving) const SettingsSavingIndicator(),
      ],
    );
  }

  Future<void> _selectRegion(
    BuildContext context,
    WidgetRef ref,
    AsterNavigationCommandOwner navigation,
    String code,
  ) async {
    var saved = false;
    final accepted = await navigation.run(
      command: () async {
        saved = await ref
            .read(settingsViewModelProvider.notifier)
            .selectRegion(code);
        if (!context.mounted || saved) return;
        final failure = ref
            .read(settingsViewModelProvider)
            .value
            ?.operationFailure;
        if (failure == null) return;
        unawaited(context.haptics.trigger(HapticIntent.error));
        context.toasts.show(
          title: 'Region not saved',
          message: failure.userMessage,
          variant: ToastVariant.failure,
        );
        ref.read(settingsViewModelProvider.notifier).clearOperationFailure();
      },
      failureTitle: 'Region could not be saved',
      hapticIntent: null,
      blocksRoutePop: true,
    );
    if (!accepted || !saved || !context.mounted) return;
    unawaited(context.haptics.trigger(HapticIntent.selection));
    context.pop();
  }
}

class _RegionLoading extends StatelessWidget {
  const _RegionLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Loading regions',
      excludeSemantics: true,
      child: AppSkeletonizer(
        enabled: true,
        child: ListView.separated(
          itemCount: 8,
          separatorBuilder: (context, index) => const AsterDivider.inset(),
          itemBuilder: (context, index) => CountrySelectOptionRow(
            country: Region(name: 'Loading region', code: 'US'),
            selected: false,
          ),
        ),
      ),
    );
  }
}
