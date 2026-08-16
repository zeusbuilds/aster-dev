import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../models/models.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

/// Asset-and-rail swap preview with execution disabled by product policy.
class SwapScreen extends ConsumerWidget {
  const SwapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final swap = ref.watch(swapViewModelProvider);
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: const CustomAppBar(
        title: 'Swap',
        leadingIcon: true,
        centerTitle: false,
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.spacing.screenPadding,
          ),
          child: swap.when(
            skipLoadingOnRefresh: false,
            data: (state) => _SwapContent(state: state),
            loading: () => const _SwapLoading(),
            error: (error, stackTrace) => _SwapFailure(
              failure: error is AppFailureException
                  ? error.failure
                  : FailureMapper.from(error, stackTrace),
              onRetry: () => ref.read(swapViewModelProvider.notifier).retry(),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwapContent extends ConsumerWidget {
  const _SwapContent({required this.state});

  final SwapState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> select({required bool from}) async {
      unawaited(context.haptics.trigger(HapticIntent.lightImpact));
      final selected = await AssetSelectorSheet.show(
        context,
        capabilities: state.capabilities,
        selected: from ? state.from : state.to,
        otherSelection: from ? state.to : state.from,
      );
      if (selected == null || !context.mounted) return;
      final notifier = ref.read(swapViewModelProvider.notifier);
      if (from) {
        notifier.selectFrom(selected);
      } else {
        notifier.selectTo(selected);
      }
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              SwapCard(
                state: state,
                onSelectFrom: () => select(from: true),
                onSelectTo: () => select(from: false),
                onReverse: () =>
                    ref.read(swapViewModelProvider.notifier).reverse(),
              ),
              SizedBox(height: context.spacing.xl),
              Squircle(
                color: context.appColors.surfaceSubtle,
                borderColor: context.appColors.borderSubtle,
                padding: EdgeInsets.all(context.spacing.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      MingCuteIcons.mgc_information_line,
                      size: context.icons.sm,
                      color: context.colorScheme.primary,
                    ),
                    SizedBox(width: context.spacing.md),
                    Expanded(
                      child: Text(
                        'Swap execution is not available in this build.',
                        style: context.type.statusMessage,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: context.spacing.lg),
        const CustomButton(text: 'Swap unavailable', enabled: false),
        SizedBox(height: context.spacing.lg),
      ],
    );
  }
}

class _SwapLoading extends StatelessWidget {
  const _SwapLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Loading swap options',
      excludeSemantics: true,
      child: AppSkeletonizer(
        enabled: true,
        child: Column(
          children: [
            for (var index = 0; index < 2; index += 1) ...[
              Squircle(
                padding: EdgeInsets.all(context.spacing.xl),
                child: Text(
                  index == 0 ? 'Bitcoin · On-chain' : 'Bitcoin · Lightning',
                  style: context.type.title,
                ),
              ),
              if (index == 0) SizedBox(height: context.spacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}

class _SwapFailure extends StatelessWidget {
  const _SwapFailure({required this.failure, required this.onRetry});

  final AppFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              failure.userMessage,
              style: context.type.statusMessage,
              textAlign: TextAlign.center,
            ),
          ),
          if (failure.retryable) ...[
            SizedBox(height: context.spacing.lg),
            CustomButton(text: 'Retry', onTap: onRetry),
          ],
        ],
      ),
    );
  }
}
