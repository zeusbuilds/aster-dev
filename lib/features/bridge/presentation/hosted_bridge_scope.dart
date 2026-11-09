import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/core.dart';
import '../../../shared/shared.dart';
import '../../wallet/presentation/view_model/view_models.dart';
import 'view_model/hosted_bridge_controller.dart';

/// Applies app-lock and native lifecycle ownership to every relay request.
class HostedBridgeScope extends ConsumerStatefulWidget {
  const HostedBridgeScope({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<HostedBridgeScope> createState() => _HostedBridgeScopeState();
}

class _HostedBridgeScopeState extends ConsumerState<HostedBridgeScope> {
  HostedBridgeController? _controller;
  late final SecurityController _security;
  DialogRoute<bool>? _dialog;
  HostedBridgeApproval? _displayed;
  bool _scheduled = false;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(hostedBridgeControllerProvider);
    if (_controller == null) return;
    _security = ref.read(securityControllerProvider)..addListener(_updateOwner);
    ref.listenManual(walletViewModelProvider, (_, _) => _updateOwner());
    ref.listenManual(
      walletLifecycleViewModelProvider,
      (_, _) => _updateOwner(),
    );
    _controller!.addListener(_updatePrompt);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateOwner();
    });
  }

  void _updateOwner() {
    if (!mounted) return;
    final wallet = ref.read(walletViewModelProvider);
    final lifecycle = ref.read(walletLifecycleViewModelProvider);
    final active =
        _security.canAccessWallet &&
            _security.sensitiveVisible &&
            !lifecycle.blocksInteraction &&
            !wallet.hasError &&
            !wallet.isLoading &&
            wallet.value?.isChangingWallet != true
        ? wallet.value?.activeWallet?.id
        : null;
    _controller?.updateOwner(
      walletId: active,
      generation: (_security.generation, lifecycle.foregroundGeneration),
    );
  }

  void _updatePrompt() {
    if (!mounted || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final prompt = _controller?.approval;
      if (identical(_displayed, prompt)) return;
      _dismiss();
      final navigator = widget.navigatorKey.currentState;
      if (prompt == null || navigator == null || !_security.sensitiveVisible) {
        prompt?.resolve(false);
        return;
      }
      _displayed = prompt;
      final route = DialogRoute<bool>(
        context: navigator.context,
        barrierDismissible: false,
        builder: (context) => _approvalDialog(prompt),
      );
      _dialog = route;
      unawaited(
        navigator.push(route).then((answer) {
          if (identical(_dialog, route)) {
            _dialog = null;
            _displayed = null;
            prompt.resolve(answer == true);
          }
        }),
      );
    });
  }

  void _dismiss() {
    final route = _dialog;
    _dialog = null;
    _displayed = null;
    if (route != null && route.isActive) route.navigator?.removeRoute(route);
  }

  @override
  void dispose() {
    if (_controller != null) {
      _security.removeListener(_updateOwner);
      _controller!.removeListener(_updatePrompt);
      _displayed?.resolve(false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Widget _approvalDialog(HostedBridgeApproval prompt) {
  final operation = prompt.operation;
  final params = operation?.params;
  switch (operation?.method) {
    case null:
      return const AsterConfirmationDialog(
        title: 'Connect to Dev Bridge?',
        content: Text(
          'dev.mint.utexo.com can read this Dev wallet and request your approval for invoices and burns.',
        ),
        confirmText: 'Connect',
      );
    case 'blindReceive':
      return const AsterConfirmationDialog(
        title: 'Create a USDT invoice?',
        content: Text(
          'Dev Bridge will receive a USDT invoice from this wallet.',
        ),
        confirmText: 'Create invoice',
      );
    case 'burnAsset':
      final recipient = params?['burnRecipient'];
      final address = recipient is Map ? recipient['address'] : null;
      final amount = _busdtAmount(params?['amount']);
      final feeRate = params?['feeRate'];
      final feeSats = params?['feeSats'];
      if (address is! String || amount == null || feeRate is! int) break;
      return AsterConfirmationDialog(
        title: 'Burn $amount USDT?',
        content: Text(
          'This permanently burns the Dev Signet USDT. The bridge pays out on Arbitrum One to '
          '$address.\n\nBitcoin fee ${feeSats == null ? 'rate $feeRate sat/vB' : '$feeSats sats'}.',
        ),
        confirmText: 'Burn USDT',
      );
    case 'getConsignment':
      return const AsterConfirmationDialog(
        title: 'Share burn proof?',
        content: Text(
          'Dev Bridge needs the proof for the existing burn to process the payout.',
        ),
        confirmText: 'Share proof',
      );
  }
  return Builder(
    builder: (context) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => prompt.resolve(false),
      );
      return const SizedBox.shrink();
    },
  );
}

String? _busdtAmount(Object? value) {
  if (value is! String || !RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(value)) {
    return null;
  }
  final digits = value.padLeft(7, '0');
  final fraction = digits
      .substring(digits.length - 6)
      .replaceFirst(RegExp(r'0+$'), '');
  final whole = digits.substring(0, digits.length - 6);
  return fraction.isEmpty ? whole : '$whole.$fraction';
}
