import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../models/models.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

enum _WalletNameSource { create, import }

/// Final naming and native-provisioning step for create and import flows.
class WalletNameScreen extends ConsumerStatefulWidget {
  const WalletNameScreen.create({
    super.key,
    this.origin = WalletCreationOrigin.onboarding,
  }) : _source = _WalletNameSource.create;

  const WalletNameScreen.import({super.key})
    : _source = _WalletNameSource.import,
      origin = WalletCreationOrigin.onboarding;

  final _WalletNameSource _source;
  final WalletCreationOrigin origin;

  @override
  ConsumerState<WalletNameScreen> createState() => _WalletNameScreenState();
}

class _WalletNameScreenState extends ConsumerState<WalletNameScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    switch (widget._source) {
      case _WalletNameSource.create:
        ref.listenManual(createWalletViewModelProvider, (_, next) {
          _hydrate(next.value?.walletName);
        }, fireImmediately: true);
      case _WalletNameSource.import:
        ref.listenManual(importWalletViewModelProvider, (_, next) {
          _hydrate(next.value?.walletName);
        }, fireImmediately: true);
    }
  }

  @override
  void dispose() {
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  void _hydrate(String? name) {
    if (name == null || name == _controller.text) return;
    _controller.value = TextEditingValue(
      text: name,
      selection: TextSelection.collapsed(offset: name.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = switch (widget._source) {
      _WalletNameSource.create =>
        ref
            .watch(createWalletViewModelProvider)
            .whenData(
              (state) => _WalletNameViewState(
                name: state.walletName,
                nameValid: state.walletNameValid,
                previousStepComplete: state.quizComplete,
                canSubmit: state.canSubmit,
                submitting: state.submitting,
                completed: state.completed,
                requiresReconciliation: state.requiresReconciliation,
                failure: state.failure,
              ),
            ),
      _WalletNameSource.import =>
        ref
            .watch(importWalletViewModelProvider)
            .whenData(
              (state) => _WalletNameViewState(
                name: state.walletName,
                nameValid: state.walletNameValid,
                previousStepComplete: state.phraseValid,
                canSubmit: state.canSubmit,
                submitting: state.submitting,
                completed: false,
                requiresReconciliation: state.requiresReconciliation,
                failure: state.failure,
              ),
            ),
    };
    final value = asyncState.value;

    return AsterNavigationScope(
      child: Builder(
        builder: (context) {
          final navigation = AsterNavigationScope.of(context);
          final locked =
              navigation.inFlight ||
              value?.submitting == true ||
              value?.requiresReconciliation == true;
          return PopScope(
            canPop: !locked,
            child: Scaffold(
              backgroundColor: context.colorScheme.surface,
              resizeToAvoidBottomInset: true,
              body: SafeArea(
                child: switch (asyncState) {
                  AsyncData<_WalletNameViewState>(:final value)
                      when value.previousStepComplete && !value.completed =>
                    _buildForm(value, navigation),
                  AsyncData<_WalletNameViewState>(:final value)
                      when value.completed =>
                    const OnboardingStatusPanel.loading(
                      message: 'Finishing wallet setup...',
                    ),
                  AsyncData<_WalletNameViewState>() =>
                    OnboardingStatusPanel.failure(
                      title: 'Finish the previous step',
                      message: widget._source == _WalletNameSource.create
                          ? 'Confirm your recovery phrase before naming the wallet.'
                          : 'Enter and validate your recovery phrase before naming the wallet.',
                      onBack: () => context.pop(),
                    ),
                  AsyncError<_WalletNameViewState>(
                    :final error,
                    :final stackTrace,
                  ) =>
                    _buildFailure(error, stackTrace),
                  _ => const OnboardingStatusPanel.loading(),
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildForm(
    _WalletNameViewState state,
    AsterNavigationCommandOwner navigation,
  ) {
    final context = this.context;
    final spacing = context.spacing;
    final invalidVisible = state.name.isNotEmpty && !state.nameValid;
    final canNavigateBack =
        !state.submitting &&
        !state.requiresReconciliation &&
        !navigation.inFlight;
    return AsterFormBody(
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: context.metrics.appBarHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: AsterIconButton(
                icon: MingCuteIcons.mgc_left_line,
                tooltip: 'Back',
                onPressed: canNavigateBack ? () => _goBack(navigation) : null,
                hapticIntent: null,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.screenPadding,
              spacing.lg,
              spacing.screenPadding,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Name your wallet', style: context.type.pageTitle),
                SizedBox(height: spacing.sm),
                Text(
                  'Choose a name that will make this wallet easy to recognize.',
                  style: context.type.rowMeta,
                ),
                SizedBox(height: spacing.xxl),
                Semantics(
                  label: 'Wallet name',
                  child: TextField(
                    key: const ValueKey('wallet-name-field'),
                    controller: _controller,
                    autofocus: true,
                    enabled: !state.submitting && !state.requiresReconciliation,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [LengthLimitingTextInputFormatter(64)],
                    onChanged: _updateName,
                    onSubmitted: (_) {
                      if (state.canSubmit && !navigation.inFlight) {
                        unawaited(_submit(navigation));
                      }
                    },
                    decoration: InputDecoration(
                      hintText: 'My wallet',
                      errorText: invalidVisible
                          ? 'Use a visible name with up to 64 characters.'
                          : null,
                      counterText: '',
                    ),
                  ),
                ),
                if (state.failure case final failure?) ...[
                  SizedBox(height: spacing.md),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      failure.userMessage,
                      style: context.type.errorMessage,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.screenPadding,
            0,
            spacing.screenPadding,
            spacing.lg,
          ),
          child: CustomButton(
            text: widget._source == _WalletNameSource.create
                ? 'Create Wallet'
                : 'Import Wallet',
            enabled:
                state.canSubmit &&
                !state.submitting &&
                !state.requiresReconciliation &&
                !navigation.inFlight,
            loading: state.submitting,
            hapticIntent: null,
            onTap: () => unawaited(_submit(navigation)),
          ),
        ),
      ],
    );
  }

  Widget _buildFailure(Object error, StackTrace stackTrace) {
    final failure = FailureMapper.from(error, stackTrace);
    return OnboardingStatusPanel.failure(
      title: 'Wallet name unavailable',
      message: failure.userMessage,
      onBack: () => context.pop(),
    );
  }

  void _updateName(String name) {
    switch (widget._source) {
      case _WalletNameSource.create:
        ref.read(createWalletViewModelProvider.notifier).updateWalletName(name);
      case _WalletNameSource.import:
        ref.read(importWalletViewModelProvider.notifier).updateWalletName(name);
    }
  }

  Future<void> _submit(AsterNavigationCommandOwner navigation) async {
    FocusScope.of(context).unfocus();
    var completed = false;
    await navigation.run(
      command: () async {
        completed = switch (widget._source) {
          _WalletNameSource.create =>
            await ref.read(createWalletViewModelProvider.notifier).submit(),
          _WalletNameSource.import =>
            await ref.read(importWalletViewModelProvider.notifier).submit(),
        };
      },
      failureTitle: widget._source == _WalletNameSource.create
          ? 'Wallet could not be created'
          : 'Wallet could not be imported',
      hapticIntent: null,
      blocksRoutePop: true,
    );
    if (!completed || !mounted) return;
    switch (widget.origin) {
      case WalletCreationOrigin.onboarding:
        context.go(RoutePaths.home);
      case WalletCreationOrigin.walletSelector:
        context.pop(WalletCreationRouteResult.created);
    }
  }

  void _goBack(AsterNavigationCommandOwner navigation) {
    unawaited(
      navigation.run(
        command: () => context.pop(),
        failureTitle: 'Previous screen could not open',
      ),
    );
  }
}

@immutable
final class _WalletNameViewState {
  const _WalletNameViewState({
    required this.name,
    required this.nameValid,
    required this.previousStepComplete,
    required this.canSubmit,
    required this.submitting,
    required this.completed,
    required this.requiresReconciliation,
    required this.failure,
  });

  final String name;
  final bool nameValid;
  final bool previousStepComplete;
  final bool canSubmit;
  final bool submitting;
  final bool completed;
  final bool requiresReconciliation;
  final AppFailure? failure;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _WalletNameViewState &&
            name == other.name &&
            nameValid == other.nameValid &&
            previousStepComplete == other.previousStepComplete &&
            canSubmit == other.canSubmit &&
            submitting == other.submitting &&
            completed == other.completed &&
            requiresReconciliation == other.requiresReconciliation &&
            failure == other.failure;
  }

  @override
  int get hashCode => Object.hash(
    name,
    nameValid,
    previousStepComplete,
    canSubmit,
    submitting,
    completed,
    requiresReconciliation,
    failure,
  );
}
