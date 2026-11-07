import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/view_model/view_models.dart';
import '../view_model/view_models.dart';

/// Explicit cancellation belongs only to the exact saved-payment details route.
/// Capability reads stay quiet; no background operation revokes a handoff.
class PaymentRevocationAction extends ConsumerStatefulWidget {
  const PaymentRevocationAction({
    super.key,
    required this.submission,
    required this.assetKind,
    required this.checking,
    required this.routeContext,
  });

  final WalletPaymentSubmission submission;
  final WalletAssetKind assetKind;
  final bool checking;
  final BuildContext routeContext;

  @override
  ConsumerState<PaymentRevocationAction> createState() =>
      _PaymentRevocationActionState();
}

class _PaymentRevocationActionState
    extends ConsumerState<PaymentRevocationAction> {
  bool _available = false;
  bool _busy = false;
  bool _performingRevocation = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCapability());
  }

  @override
  void didUpdateWidget(PaymentRevocationAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.submission != widget.submission ||
        (oldWidget.checking && !widget.checking)) {
      unawaited(_loadCapability());
    }
  }

  Future<void> _loadCapability() async {
    final revision = ++_revision;
    final result = await ref
        .read(activityViewModelProvider(widget.assetKind).notifier)
        .canRevokePayment(widget.submission);
    if (!mounted || revision != _revision) return;
    final available = result is AppSuccess<bool> && result.value;
    if (_available != available) setState(() => _available = available);
  }

  bool _owns(
    BuildContext routeContext,
    ProviderContainer container,
    ModalRoute<Object?>? route,
    int foreground,
    String walletId,
  ) {
    final ownership = _readOwnership(
      routeContext,
      container,
      route,
      foreground,
      walletId,
    );
    // A vanished owner cannot present feedback or authorize a revocation.
    return ownership is AppSuccess<bool> && ownership.value;
  }

  AppResult<bool> _readOwnership(
    BuildContext routeContext,
    ProviderContainer container,
    ModalRoute<Object?>? route,
    int foreground,
    String walletId,
  ) {
    if (!routeContext.mounted ||
        !identical(ModalRoute.of(routeContext), route) ||
        !(route?.isCurrent ?? false) ||
        !TickerMode.valuesOf(routeContext).enabled) {
      return const AppResult.success(false);
    }
    try {
      final lifecycle = container.read(walletLifecycleViewModelProvider);
      final wallet = container.read(walletViewModelProvider);
      return AppResult.success(
        !lifecycle.blocksInteraction &&
            lifecycle.foregroundGeneration == foreground &&
            !wallet.isLoading &&
            !wallet.hasError &&
            wallet.value?.isChangingWallet == false &&
            wallet.value?.activeWallet?.id == walletId &&
            (WidgetsBinding.instance.lifecycleState == null ||
                WidgetsBinding.instance.lifecycleState ==
                    AppLifecycleState.resumed),
      );
    } catch (error, stackTrace) {
      return AppResult.failure(FailureMapper.from(error, stackTrace));
    }
  }

  Future<void> _cancel() async {
    if (_busy || widget.checking || !_available) return;
    final record = widget.submission;
    final routeContext = widget.routeContext;
    final route = ModalRoute.of(routeContext);
    final container = ProviderScope.containerOf(routeContext, listen: false);
    final foreground = container
        .read(walletLifecycleViewModelProvider)
        .foregroundGeneration;
    if (!_owns(routeContext, container, route, foreground, record.walletId)) {
      return;
    }
    final toasts = routeContext.toasts;
    final notifier = container.read(
      activityViewModelProvider(widget.assetKind).notifier,
    );
    setState(() => _busy = true);
    try {
      final confirmed = await showDialog<bool>(
        context: routeContext,
        builder: (context) => const AsterConfirmationDialog(
          title: 'Cancel payment?',
          content: Text(
            'If this payment was already sent, it stays sent. Sending unlocks only after cancellation is verified.',
          ),
          cancelText: 'Keep payment',
          confirmText: 'Cancel payment',
        ),
      );
      if (confirmed != true || !routeContext.mounted) return;
      if (!_owns(routeContext, container, route, foreground, record.walletId)) {
        return;
      }
      if (mounted) setState(() => _performingRevocation = true);
      final result = await notifier.revokePayment(record);
      if (!routeContext.mounted) return;
      if (!_owns(routeContext, container, route, foreground, record.walletId)) {
        return;
      }
      final latest = result is AppSuccess<WalletPaymentSubmission?>
          ? result.value
          : null;
      final accepted =
          latest?.outcome == WalletPaymentSubmissionOutcome.accepted;
      final cancelled =
          latest?.outcome == WalletPaymentSubmissionOutcome.notSubmitted;
      final complete = latest?.requiresReconciliation == false;
      toasts.show(
        title: accepted
            ? 'Payment submitted'
            : cancelled
            ? 'Payment cancelled'
            : 'Could not cancel payment',
        message: accepted || cancelled
            ? complete
                  ? null
                  : 'Check its status before sending again.'
            : 'Check its status before sending again.',
        variant: (accepted || cancelled) && complete
            ? ToastVariant.success
            : ToastVariant.warning,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _performingRevocation = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => !_available
      ? const SizedBox.shrink()
      : Padding(
          padding: EdgeInsets.only(top: context.spacing.md),
          child: Align(
            alignment: Alignment.center,
            child: CustomButton.compact(
              text: 'Cancel payment',
              variant: ButtonVariant.secondary,
              loading: _performingRevocation,
              enabled: !_busy && !widget.checking,
              onTap: _cancel,
            ),
          ),
        );
}
