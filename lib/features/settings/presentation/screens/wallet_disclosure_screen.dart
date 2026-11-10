import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../../onboarding/presentation/widgets/onboarding_recovery_phrase_grid.dart';
import '../../../wallet/domain/models/models.dart';
import '../controllers/wallet_disclosure_handoff.dart';
import '../view_model/view_models.dart';

/// Displays only a ready, single-use handoff prepared on Advanced Settings.
/// A direct route entry has no authority and returns to Advanced Settings.
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
  WalletDisclosureSession? _session;
  String? get _mnemonic => _session?.mnemonic;
  WalletPublicKeys? get _keys => _session?.keys;
  bool _closing = false;
  bool _closeScheduled = false;
  bool _sharing = false;
  bool _copying = false;

  bool get _isSeed => widget.purpose == SecurityPurpose.revealSeed;
  bool get _current =>
      mounted &&
      !_closing &&
      ModalRoute.of(context)?.isCurrent == true &&
      _session?.valid == true;

  @override
  void initState() {
    super.initState();
    _session = ref.read(walletDisclosureHandoffProvider).claim(widget.purpose);
    _session?.addListener(_sessionChanged);
    if (_session == null) {
      _closing = true;
      _scheduleClose();
    }
  }

  void _sessionChanged() {
    if (_session?.valid != true) _close();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    _session?.close();
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
        context.pop();
      } else {
        context.goNamed(RouteNames.advancedSettings);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  String get _exportText =>
      'Bitcoin account\n${_keys!.bitcoin}\n\nRGB account\n${_keys!.rgb}';

  Future<void> _copy() async {
    if (_copying || _keys == null || !_current) return;
    final toasts = context.toasts;
    setState(() => _copying = true);
    final result = await ref
        .read(walletDisclosureViewModelProvider)
        .copyPublicKeys(_exportText, current: () => _current);
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
        .read(walletDisclosureViewModelProvider)
        .sharePublicKeys(
          text,
          current: () => _current,
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
    _session?.removeListener(_sessionChanged);
    _session?.close();
    _session = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_current && !_closing) _close();
    if (_closing) _scheduleClose();
    final ready = _current;
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: CustomAppBar(
        title: _isSeed ? 'Seed phrase' : 'Export xpubs',
        leadingIcon: true,
        fallbackLocation: RoutePaths.advancedSettingsLocation,
      ),
      body: AsterHorizontalSafeArea(
        child: !ready
            ? const SizedBox.shrink()
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
                                onTap: _copying
                                    ? null
                                    : () => unawaited(_copy()),
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
