import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../../onboarding/presentation/widgets/onboarding_recovery_phrase_grid.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/view_model/view_models.dart';

/// Sensitive values never enter route arguments or persistent presentation state.
/// A direct route entry must authorize itself, just like a Settings tap.
class WalletDisclosureScreen extends ConsumerStatefulWidget {
  const WalletDisclosureScreen.seed({super.key})
    : purpose = SecurityPurpose.revealSeed;
  const WalletDisclosureScreen.xpubs({super.key})
    : purpose = SecurityPurpose.exportXpubs;

  final SecurityPurpose purpose;

  @override
  ConsumerState<WalletDisclosureScreen> createState() =>
      _WalletDisclosureScreenState();
}

class _WalletDisclosureScreenState
    extends ConsumerState<WalletDisclosureScreen> {
  SecurityController? _security;
  Completer<bool>? _accessWaiter;
  String? _walletId;
  String? _mnemonic;
  WalletPublicKeys? _keys;
  int? _authorizedGeneration;
  bool _armed = false;
  bool _sensitiveLease = false;
  bool _closing = false;
  bool _closeScheduled = false;
  AppFailure? _closeFailure;
  bool _sharing = false;
  bool _copying = false;

  bool get _isSeed => widget.purpose == SecurityPurpose.revealSeed;
  bool get _current =>
      mounted &&
      !_closing &&
      ModalRoute.of(context)?.isCurrent == true &&
      _security?.sensitiveVisible == true &&
      _security?.generation == _authorizedGeneration &&
      ref.read(walletViewModelProvider).value?.activeWallet?.id == _walletId &&
      ref.read(walletViewModelProvider).value?.isChangingWallet != true;

  @override
  void initState() {
    super.initState();
    _security = ref.read(securityControllerProvider);
    _security!.addListener(_securityChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_open());
    });
  }

  Future<void> _open() async {
    try {
      if (!_security!.canAccessWallet) {
        final waiter = _accessWaiter ??= Completer<bool>();
        if (!await waiter.future) return;
      }
      if (!mounted || _closing) return;
      if (ModalRoute.of(context)?.isCurrent != true) {
        _close();
        return;
      }
      if (ref.read(walletViewModelProvider).isLoading) {
        await ref.read(walletViewModelProvider.future);
      }
      if (!mounted || _closing) return;
      final walletState = ref.read(walletViewModelProvider);
      final profile =
          !walletState.isLoading &&
              !walletState.hasError &&
              walletState.value?.isChangingWallet != true
          ? walletState.value?.activeWallet
          : null;
      if (profile == null || profile.state != WalletProfileState.ready) {
        _close(
          const AppFailure(
            code: 'wallet_disclosure_wallet_unavailable',
            kind: AppFailureKind.unavailable,
            userMessage: 'This wallet is unavailable. Try again.',
            retryable: true,
          ),
        );
        return;
      }
      _walletId = profile.id;
      if (_security!.isCaptured) {
        _close(_captureFailure);
        return;
      }
      _sensitiveLease = true;
      await _security!.setSensitive(true);
      if (!mounted || _closing) return;
      if (_security!.isCaptured) {
        _close(_captureFailure);
        return;
      }
      final authorization = await _security!.authorize(
        widget.purpose,
        walletId: profile.id,
      );
      if (!mounted || _closing) return;
      if (authorization == null) {
        _close();
        return;
      }
      if (_security!.isCaptured) {
        _close(_captureFailure);
        return;
      }
      _authorizedGeneration = _security!.generation;
      _armed = true;
      if (!_current) {
        _close();
        return;
      }
      final repository = await ref.read(walletRepositoryProvider.future);
      if (!_current) return _close();
      if (_isSeed) {
        final result = await repository.recoveryMnemonic(
          profile.id,
          authorization: authorization,
        );
        if (!_current) return _close();
        switch (result) {
          case AppSuccess<String>(:final value):
            // Stored wallets currently use twelve words. Reject a malformed
            // credential rather than partially rendering secret material.
            if (value.trim().split(RegExp(r'\s+')).length != 12) {
              _close(
                const AppFailure(
                  code: 'wallet_disclosure_phrase_invalid',
                  kind: AppFailureKind.storage,
                  userMessage: 'The seed phrase could not be opened safely.',
                  retryable: false,
                ),
              );
              return;
            }
            setState(() => _mnemonic = value);
          case AppFailureResult<String>(:final failure):
            _close(failure);
        }
      } else {
        final result = await repository.publicKeys(
          authorization: authorization,
          walletId: profile.id,
        );
        if (!_current) return _close();
        switch (result) {
          case AppSuccess<WalletPublicKeys>(:final value):
            setState(() => _keys = value);
          case AppFailureResult<WalletPublicKeys>(:final failure):
            _close(failure);
        }
      }
    } catch (error, stackTrace) {
      if (mounted && !_closing) _close(FailureMapper.from(error, stackTrace));
    }
  }

  void _securityChanged() {
    // Keep an incoming disclosure destination behind the global unlock gate.
    // The gate owns its prompt; this route requests its own fresh disclosure
    // authorization only after wallet access has actually been restored.
    final waiter = _accessWaiter;
    if (waiter != null &&
        !waiter.isCompleted &&
        _security?.canAccessWallet == true) {
      waiter.complete(true);
      _accessWaiter = null;
    }
    // The native authentication sheet can transiently obscure its own route.
    // Only an accepted disclosure session is subject to invalidation here.
    if (!_armed || _closing) return;
    if (!_current) _close();
  }

  void _close([AppFailure? failure]) {
    if (_closing) return;
    _closing = true;
    _closeFailure = failure;
    _mnemonic = null;
    _keys = null;
    _armed = false;
    if (mounted &&
        SchedulerBinding.instance.schedulerPhase !=
            SchedulerPhase.persistentCallbacks) {
      setState(() {});
    }
    _scheduleClose();
  }

  void _scheduleClose() {
    if (_closeScheduled || !mounted) return;
    _closeScheduled = true;
    // Clear painted/semantic content before navigating. If another Flutter
    // route covered this page, keep it blank until it becomes current, then
    // return to Settings. Never pop the unrelated page or retain a disclosure
    // beneath it, and let GoRouter own its page-match stack.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _closeScheduled = false;
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (context.canPop()) {
        context.pop(_closeFailure);
      } else {
        context.goNamed(RouteNames.advancedSettings);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  static const _captureFailure = AppFailure(
    code: 'wallet_disclosure_capture_active',
    kind: AppFailureKind.unavailable,
    userMessage: 'Stop screen sharing to view wallet information.',
    retryable: true,
  );

  String get _exportText =>
      'Bitcoin account\n${_keys!.bitcoin}\n\nRGB account\n${_keys!.rgb}';

  Future<void> _copy() async {
    if (_copying || _keys == null || !_current) return;
    final toasts = context.toasts;
    setState(() => _copying = true);
    final result = await ref
        .read(clipboardServiceProvider)
        .writeText(_exportText);
    if (_current) {
      switch (result) {
        case AppSuccess<void>():
          toasts.show(title: 'Keys copied', variant: ToastVariant.success);
        case AppFailureResult<void>():
          toasts.show(
            title: 'Keys could not be copied',
            message: 'The system clipboard is unavailable. Try again.',
            variant: ToastVariant.failure,
          );
      }
    }
    if (mounted) setState(() => _copying = false);
  }

  Future<void> _share(BuildContext buttonContext) async {
    if (_sharing || _keys == null || !_current) return;
    final toasts = context.toasts;
    final box = buttonContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final offset = box.localToGlobal(Offset.zero);
    final text = _exportText;
    setState(() => _sharing = true);
    final result = await ref
        .read(shareServiceProvider)
        .shareText(
          text,
          subject: 'Aster extended public keys',
          origin: ShareOrigin(
            left: offset.dx,
            top: offset.dy,
            width: box.size.width,
            height: box.size.height,
          ),
        );
    if (_current && result is AppFailureResult<ShareDisposition>) {
      toasts.show(
        title: 'Keys could not be shared',
        message: 'Sharing is unavailable. Try again.',
        variant: ToastVariant.failure,
      );
    }
    if (mounted) setState(() => _sharing = false);
  }

  @override
  void dispose() {
    _mnemonic = null;
    _keys = null;
    final waiter = _accessWaiter;
    if (waiter != null && !waiter.isCompleted) waiter.complete(false);
    _accessWaiter = null;
    _security?.removeListener(_securityChanged);
    if (_security != null && _sensitiveLease) {
      _sensitiveLease = false;
      unawaited(_security!.setSensitive(false).catchError((Object _) {}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(walletViewModelProvider, (_, next) {
      if (_walletId == null || _closing) return;
      if (next.isLoading ||
          next.hasError ||
          next.value?.activeWallet?.id != _walletId ||
          next.value?.isChangingWallet == true) {
        _close();
      }
    });
    if (_armed && ModalRoute.of(context)?.isCurrent != true) _close();
    if (_closing) _scheduleClose();
    final visible = _armed && _current;
    final ready = visible && (_isSeed ? _mnemonic != null : _keys != null);
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: CustomAppBar(
        title: _isSeed ? 'Seed phrase' : 'Export xpubs',
        leadingIcon: true,
        fallbackLocation: RoutePaths.advancedSettingsLocation,
      ),
      body: !ready
          ? const Center(
              child: GridLoader(semanticLabel: 'Opening wallet information'),
            )
          : _isSeed
          ? ListView(
              padding: EdgeInsets.fromLTRB(
                context.spacing.screenPadding,
                context.spacing.lg,
                context.spacing.screenPadding,
                context.spacing.lg + context.windowInsets.bottomSafe,
              ),
              children: [
                OnboardingRecoveryPhraseGrid(
                  words: _mnemonic!.trim().split(RegExp(r'\s+')),
                ),
                SizedBox(height: context.spacing.xl),
                Text(
                  'Keep these words private. Anyone with them can access your funds.',
                  style: context.type.supportingMeta,
                ),
              ],
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      context.spacing.screenPadding,
                      context.spacing.lg,
                      context.spacing.screenPadding,
                      context.spacing.lg,
                    ),
                    children: [
                      _PublicKey(
                        label: 'Bitcoin account',
                        value: _keys!.bitcoin,
                      ),
                      SizedBox(height: context.spacing.xl),
                      _PublicKey(label: 'RGB account', value: _keys!.rgb),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    context.spacing.screenPadding,
                    context.spacing.lg,
                    context.spacing.screenPadding,
                    context.spacing.lg + context.windowInsets.bottomSafe,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Extended public keys can reveal your wallet activity. Share them only with services you trust.',
                        style: context.type.supportingMeta,
                      ),
                      SizedBox(height: context.spacing.lg),
                      Row(
                        children: [
                          Expanded(
                            child: CustomButton(
                              text: 'Copy',
                              variant: ButtonVariant.secondary,
                              onTap: _copying ? null : () => unawaited(_copy()),
                            ),
                          ),
                          SizedBox(width: context.spacing.md),
                          Expanded(
                            child: Builder(
                              builder: (buttonContext) => CustomButton(
                                text: 'Share',
                                variant: ButtonVariant.secondary,
                                onTap: _sharing
                                    ? null
                                    : () => unawaited(_share(buttonContext)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _PublicKey extends StatelessWidget {
  const _PublicKey({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: context.type.rowMeta),
      SizedBox(height: context.spacing.sm),
      Text(value, style: context.type.rowValue),
    ],
  );
}
