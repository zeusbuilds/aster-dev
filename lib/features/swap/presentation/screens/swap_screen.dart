import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final isDuoCover =
        ref
            .watch(duoCoverLayoutProvider)
            .value
            ?.appliesTo(MediaQuery.sizeOf(context)) ==
        true;
    final scrollsToBottom = isDuoCover || context.isOpenDuoLandscape;
    return AsterPageScaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: const CustomAppBar(
        title: 'Swap',
        leadingIcon: true,
        centerTitle: false,
      ),
      body: SafeArea(
        top: false,
        bottom: !scrollsToBottom,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.spacing.screenPadding,
          ),
          child: _SwapContent(
            state: swap,
            bottomPadding:
                context.spacing.lg +
                (scrollsToBottom ? context.windowInsets.bottomSafe : 0),
          ),
        ),
      ),
    );
  }
}

class _SwapContent extends ConsumerWidget {
  const _SwapContent({required this.state, required this.bottomPadding});

  final SwapState state;
  final double bottomPadding;

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

    return AsterFormBody(
      bottomPadding: bottomPadding,
      content: Column(
        children: [
          SwapCard(
            state: state,
            onSelectFrom: () => select(from: true),
            onSelectTo: () => select(from: false),
            onReverse: () => ref.read(swapViewModelProvider.notifier).reverse(),
          ),
        ],
      ),
      actions: const [CustomButton(text: 'Coming soon', enabled: false)],
    );
  }
}
