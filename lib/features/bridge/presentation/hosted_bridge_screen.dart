import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/core.dart';
import '../../../shared/shared.dart';
import '../../scan/domain/models/models.dart';
import '../../wallet/domain/models/models.dart';
import 'view_model/hosted_bridge_controller.dart';

class HostedBridgeScreen extends ConsumerStatefulWidget {
  const HostedBridgeScreen({super.key});

  @override
  ConsumerState<HostedBridgeScreen> createState() => _HostedBridgeScreenState();
}

class _HostedBridgeScreenState extends ConsumerState<HostedBridgeScreen> {
  final _link = TextEditingController();
  bool _pairing = false;
  bool _preparing = false;
  bool _scanning = false;
  bool _disconnecting = false;
  bool _loadingBurns = false;
  bool _sharingBurn = false;
  List<HostedBridgeBurn> _burns = const [];

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _pair(HostedBridgeController bridge, String input) async {
    if (_pairing || !bridge.available) return;
    final toasts = context.toasts;
    FocusScope.of(context).unfocus();
    setState(() => _pairing = true);
    _link.clear();
    try {
      await bridge.pair(input);
    } on FormatException {
      if (mounted) {
        toasts.show(
          title: 'Connection link unavailable',
          message:
              'Scan or paste a current WalletConnect link from Dev Bridge.',
          variant: ToastVariant.warning,
        );
      }
    } on HostedBridgeOutputsRequired {
      if (mounted) {
        toasts.show(
          title: 'Prepare RGB outputs',
          message: 'A confirmed RGB output is required to connect.',
          variant: ToastVariant.warning,
        );
      }
    } on Object {
      if (mounted) {
        toasts.show(
          title: 'Could not connect',
          message: 'Open Dev Bridge and try a new connection link.',
          variant: ToastVariant.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _pairing = false);
    }
  }

  Future<void> _scan(HostedBridgeController bridge) async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final link = await context.pushNamed<String>(
        RouteNames.scan,
        extra: ScanPurpose.bridgePairing,
      );
      if (mounted && link != null) await _pair(bridge, link);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _prepare() async {
    if (_preparing) return;
    final toasts = context.toasts;
    setState(() => _preparing = true);
    try {
      final setup = ref.read(hostedBridgeSetupActionsProvider);
      final status = await setup.status();
      if (!mounted) return;
      if (status case AppSuccess<RgbWalletSetupStatus>(:final value)) {
        if (value.phase != RgbWalletSetupPhase.required) {
          _setupFeedback(value.phase);
          return;
        }
      } else if (status case AppFailureResult<RgbWalletSetupStatus>(
        :final failure,
      )) {
        toasts.show(
          title: 'Could not check outputs',
          message: failure.userMessage,
          variant: ToastVariant.warning,
        );
        return;
      }
      final prepared = await setup.prepare();
      if (!mounted) return;
      if (prepared case AppFailureResult<RgbWalletSetupReview>(
        :final failure,
      )) {
        toasts.show(
          title: 'Could not prepare outputs',
          message: failure.userMessage,
          variant: ToastVariant.warning,
        );
        return;
      }
      final review = (prepared as AppSuccess<RgbWalletSetupReview>).value;
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AsterConfirmationDialog(
          title: 'Prepare RGB outputs?',
          content: Text(
            'Create ${RgbWalletSetupReview.outputCount} outputs of ${RgbWalletSetupReview.outputValueSats} sats. '
            'Bitcoin fee rate ${review.feeRateSatPerVbyte} sat/vB. '
            'The total Bitcoin fee is determined when the transaction is built.',
          ),
          confirmText: 'Prepare',
        ),
      );
      if (approved != true || !mounted) {
        await setup.cancel(review);
        return;
      }
      final result = await setup.confirm(review);
      if (!mounted) return;
      switch (result) {
        case AppSuccess<RgbWalletSetupStatus>(:final value):
          _setupFeedback(value.phase);
        case AppFailureResult<RgbWalletSetupStatus>(:final failure):
          toasts.show(
            title: 'Could not prepare outputs',
            message: failure.userMessage,
            variant: ToastVariant.warning,
          );
      }
    } on Object {
      if (mounted) {
        toasts.show(
          title: 'Could not check outputs',
          message: 'Try again after the wallet has synced.',
          variant: ToastVariant.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  void _setupFeedback(RgbWalletSetupPhase phase) {
    final (title, message) = switch (phase) {
      RgbWalletSetupPhase.ready => (
        'RGB outputs ready',
        'You can connect to Dev Bridge.',
      ),
      RgbWalletSetupPhase.pending => (
        'Waiting for confirmation',
        'Check again after the Bitcoin transaction confirms.',
      ),
      RgbWalletSetupPhase.indeterminate => (
        'Check output status',
        'Wait for the existing transaction to appear in Activity.',
      ),
      RgbWalletSetupPhase.required => (
        'Outputs needed',
        'Prepare an RGB output to connect.',
      ),
    };
    context.toasts.show(
      title: title,
      message: message,
      variant: phase == RgbWalletSetupPhase.ready
          ? ToastVariant.success
          : ToastVariant.warning,
    );
  }

  Future<void> _disconnect(HostedBridgeController bridge) async {
    if (_disconnecting) return;
    final toasts = context.toasts;
    setState(() => _disconnecting = true);
    try {
      await bridge.disconnect();
    } on Object {
      if (mounted) {
        toasts.show(
          title: 'Could not finish disconnecting',
          message: 'Try again when the relay is available.',
          variant: ToastVariant.warning,
        );
      }
    } finally {
      if (mounted) setState(() => _disconnecting = false);
    }
  }

  Future<void> _showBurns(HostedBridgeController bridge) async {
    if (_loadingBurns || _sharingBurn) return;
    final toasts = context.toasts;
    setState(() => _loadingBurns = true);
    try {
      final burns = await bridge.savedBurns();
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      setState(() => _burns = burns);
      if (burns.isEmpty) {
        toasts.show(
          title: 'No saved burns',
          message: 'Burns submitted by this wallet will appear here.',
          variant: ToastVariant.warning,
        );
      }
    } on Object {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      toasts.show(
        title: 'Could not open saved burns',
        message: 'Try again after the wallet has synced.',
        variant: ToastVariant.warning,
      );
    } finally {
      if (mounted) setState(() => _loadingBurns = false);
    }
  }

  Future<void> _shareBurn(
    HostedBridgeController bridge,
    HostedBridgeBurn burn,
    BuildContext rowContext,
  ) async {
    if (_sharingBurn || !bridge.ownsBurn(burn)) return;
    final box = rowContext.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final offset = box.localToGlobal(Offset.zero);
    final origin = ShareOrigin(
      left: offset.dx,
      top: offset.dy,
      width: box.size.width,
      height: box.size.height,
    );
    final toasts = context.toasts;
    final security = ref.read(securityControllerProvider);
    _sharingBurn = true;
    try {
      final export = await bridge.exportBurn(burn, security);
      if (export == null) return;
      await PlatformShareService.shareDevBurnProof(
        txid: export.txid,
        package: export.package,
        origin: origin,
        canShare: () =>
            mounted &&
            ModalRoute.of(context)?.isCurrent == true &&
            bridge.canShare(export),
      );
    } on Object {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      toasts.show(
        title: 'Could not export burn proof',
        message: 'Open saved burns and try again.',
        variant: ToastVariant.warning,
      );
    } finally {
      _sharingBurn = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.watch(hostedBridgeControllerProvider);
    final spacing = context.spacing;
    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Dev Bridge',
        leadingIcon: true,
        fallbackLocation: RoutePaths.settings,
      ),
      body: AsterHorizontalSafeArea(
        child: bridge == null
            ? const SizedBox.shrink()
            : ListenableBuilder(
                listenable: bridge,
                builder: (context, _) {
                  if (!bridge.available) return const SizedBox.shrink();
                  return ListView(
                    padding: EdgeInsets.fromLTRB(
                      spacing.screenPadding,
                      spacing.lg,
                      spacing.screenPadding,
                      spacing.lg + context.windowInsets.bottomSafe,
                    ),
                    children: [
                      if (bridge.connected)
                        AsterOptionRow(
                          title: 'dev.mint.utexo.com',
                          details: 'Connected',
                          prefixIcon: Icons.link,
                          onTap: null,
                        )
                      else ...[
                        TextField(
                          controller: _link,
                          decoration: const InputDecoration(
                            labelText: 'WalletConnect link',
                          ),
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.go,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(
                              HostedBridgeController.maxLinkLength,
                            ),
                          ],
                          onSubmitted: (value) =>
                              unawaited(_pair(bridge, value)),
                        ),
                        SizedBox(height: spacing.lg),
                        CustomButton(
                          text: 'Connect',
                          loading: _pairing,
                          onTap: () => unawaited(_pair(bridge, _link.text)),
                        ),
                        SizedBox(height: spacing.md),
                        CustomButton(
                          text: 'Scan connection QR',
                          variant: ButtonVariant.secondary,
                          enabled: !_pairing && !_scanning,
                          onTap: () => unawaited(_scan(bridge)),
                        ),
                      ],
                      SizedBox(height: spacing.xl),
                      if (bridge.connected)
                        CustomButton(
                          text: 'Disconnect',
                          variant: ButtonVariant.secondary,
                          loading: _disconnecting,
                          onTap: () => unawaited(_disconnect(bridge)),
                        )
                      else
                        CustomButton(
                          text: 'Prepare RGB outputs',
                          variant: ButtonVariant.secondary,
                          loading: _preparing,
                          onTap: () => unawaited(_prepare()),
                        ),
                      SizedBox(height: spacing.md),
                      CustomButton(
                        text: 'Saved burns',
                        variant: ButtonVariant.secondary,
                        loading: _loadingBurns,
                        onTap: () => unawaited(_showBurns(bridge)),
                      ),
                      for (final burn in _burns.where(bridge.ownsBurn))
                        Builder(
                          builder: (rowContext) => AsterOptionRow(
                            title: 'Export burn proof',
                            details: '${burn.txid.substring(0, 12)}…',
                            prefixIcon: Icons.ios_share,
                            onTap: () =>
                                unawaited(_shareBurn(bridge, burn, rowContext)),
                          ),
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
