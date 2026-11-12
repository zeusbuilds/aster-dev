import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/shared.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

/// Selects the app-wide Bitcoin denomination without changing stored values.
class BitcoinUnitSelectionScreen extends ConsumerWidget {
  const BitcoinUnitSelectionScreen({
    super.key,
    this.onClose,
    this.showBack = true,
  });

  /// Returns an embedded chooser to its Settings panel.
  final VoidCallback? onClose;
  final bool showBack;

  static const _exampleSatoshis = 12345678;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsViewModelProvider);
    final saving =
        !settings.isLoading &&
        !settings.hasError &&
        settings.value?.isSaving == true;
    final selected = settings.value?.snapshot.preferences.bitcoinUnit;
    final content = Builder(
      builder: (context) {
        final navigation = AsterNavigationScope.of(context);
        final navigationLocked = saving || navigation.inFlight;
        final canSelect =
            !navigationLocked &&
            !settings.isLoading &&
            !settings.hasError &&
            selected != null;
        return PopScope(
          canPop: !navigationLocked,
          child: AsterPageScaffold(
            backgroundColor: context.colorScheme.surface,
            appBar: CustomAppBar(
              title: 'Bitcoin Unit',
              leadingIcon: showBack,
              automaticallyImplyLeading: showBack,
              leadingEnabled: !navigationLocked,
              onBack: onClose,
              fallbackLocation: RoutePaths.settings,
            ),
            body: Stack(
              children: [
                SafeArea(
                  top: false,
                  bottom: false,
                  child: ListView.separated(
                    padding: EdgeInsets.only(
                      bottom:
                          context.windowInsets.bottomSafe + context.spacing.lg,
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
                        onTap: canSelect
                            ? () => unawaited(
                                _select(context, ref, navigation, unit),
                              )
                            : null,
                      );
                    },
                  ),
                ),
                if (saving)
                  Semantics(
                    container: true,
                    liveRegion: true,
                    label: 'Saving preference',
                    child: const ExcludeSemantics(
                      child: LinearProgressIndicator(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    return onClose == null ? AsterNavigationScope(child: content) : content;
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
    if (onClose case final close?) {
      close();
    } else {
      context.pop();
    }
  }
}
