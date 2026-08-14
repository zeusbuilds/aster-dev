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
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: const CustomAppBar(
        title: 'Select Region',
        leadingIcon: true,
        fallbackLocation: RoutePaths.settings,
      ),
      body: settings.when(
        skipLoadingOnRefresh: false,
        data: (state) => _RegionList(state: state),
        loading: () => const _RegionLoading(),
        error: (error, stackTrace) => _RegionLoadFailure(
          message: FailureMapper.from(error, stackTrace).userMessage,
          onRetry: () => ref.read(settingsViewModelProvider.notifier).retry(),
        ),
      ),
    );
  }
}

class _RegionList extends ConsumerWidget {
  const _RegionList({required this.state});

  final SettingsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCode = state.snapshot.preferences.regionCode;
    final saving = state.operation == SettingsOperation.region;
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
                onTap: saving
                    ? null
                    : () => unawaited(_selectRegion(context, ref, region.code)),
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
  }

  Future<void> _selectRegion(
    BuildContext context,
    WidgetRef ref,
    String code,
  ) async {
    final saved = await ref
        .read(settingsViewModelProvider.notifier)
        .selectRegion(code);
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
      title: 'Region not saved',
      message: failure.userMessage,
      variant: ToastVariant.failure,
    );
    ref.read(settingsViewModelProvider.notifier).clearOperationFailure();
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

class _RegionLoadFailure extends StatelessWidget {
  const _RegionLoadFailure({required this.message, required this.onRetry});

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
