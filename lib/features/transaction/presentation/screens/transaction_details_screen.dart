import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../../settings/presentation/models/models.dart';
import '../../../settings/presentation/view_model/view_models.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/widgets/widgets.dart';
import '../formatting/formatting.dart';
import '../models/models.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

/// Details for one opaque Activity ID resolved from the active wallet.
class TransactionDetailsScreen extends ConsumerStatefulWidget {
  const TransactionDetailsScreen({
    super.key,
    required this.assetKind,
    required this.activityId,
  });

  final WalletAssetKind assetKind;
  final String activityId;

  @override
  ConsumerState<TransactionDetailsScreen> createState() =>
      _TransactionDetailsScreenState();
}

class _TransactionDetailsScreenState
    extends ConsumerState<TransactionDetailsScreen> {
  static final _formatter = ActivityDisplayFormatter();
  final Set<String> _copyingFields = <String>{};
  bool _openingExplorer = false;

  Future<void> _copy(String label, String value) async {
    if (_copyingFields.contains(label)) return;
    setState(() => _copyingFields.add(label));
    final result = await ref.read(clipboardServiceProvider).writeText(value);
    if (!mounted) return;
    setState(() => _copyingFields.remove(label));
    switch (result) {
      case AppSuccess<void>():
        unawaited(context.haptics.trigger(HapticIntent.lightImpact));
        context.toasts.show(
          title: '$label copied',
          variant: ToastVariant.success,
        );
      case AppFailureResult<void>(:final failure):
        unawaited(context.haptics.trigger(HapticIntent.error));
        context.toasts.show(
          title: 'Could not copy $label',
          message: failure.userMessage,
          variant: ToastVariant.failure,
        );
    }
  }

  Future<void> _openExplorer(Uri uri) async {
    if (_openingExplorer) return;
    setState(() => _openingExplorer = true);
    final result = await ref.read(externalUriServiceProvider).open(uri);
    if (!mounted) return;
    setState(() => _openingExplorer = false);
    switch (result) {
      case AppSuccess<void>():
        unawaited(context.haptics.trigger(HapticIntent.lightImpact));
      case AppFailureResult<void>(:final failure):
        unawaited(context.haptics.trigger(HapticIntent.error));
        context.toasts.show(
          title: 'Could not open explorer',
          message: failure.userMessage,
          variant: ToastVariant.failure,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final activity = ref.watch(activityViewModelProvider(widget.assetKind));
    final settings = ref.watch(settingsViewModelProvider);
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: CustomAppBar(
        title: 'Transaction details',
        leadingIcon: true,
        centerTitle: false,
      ),
      body: SafeArea(
        top: false,
        child: _DetailsBody(
          activity: activity,
          settings: settings,
          assetKind: widget.assetKind,
          activityId: widget.activityId,
          formatter: _formatter,
          copyingFields: _copyingFields,
          openingExplorer: _openingExplorer,
          onCopy: _copy,
          onOpenExplorer: _openExplorer,
        ),
      ),
    );
  }
}

class _DetailsBody extends ConsumerWidget {
  const _DetailsBody({
    required this.activity,
    required this.settings,
    required this.assetKind,
    required this.activityId,
    required this.formatter,
    required this.copyingFields,
    required this.openingExplorer,
    required this.onCopy,
    required this.onOpenExplorer,
  });

  final AsyncValue<ActivityState> activity;
  final AsyncValue<SettingsState> settings;
  final WalletAssetKind assetKind;
  final String activityId;
  final ActivityDisplayFormatter formatter;
  final Set<String> copyingFields;
  final bool openingExplorer;
  final Future<void> Function(String label, String value) onCopy;
  final Future<void> Function(Uri uri) onOpenExplorer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (activity.isLoading || settings.isLoading) {
      return const _DetailsLoadingView();
    }
    if (activity case AsyncError(:final error, :final stackTrace)) {
      return _DetailsFailure(
        failure: _failure(error, stackTrace),
        onRetry: () =>
            ref.read(activityViewModelProvider(assetKind).notifier).retry(),
      );
    }
    if (settings case AsyncError(:final error, :final stackTrace)) {
      return _DetailsFailure(
        failure: _failure(error, stackTrace),
        onRetry: () => ref.read(settingsViewModelProvider.notifier).retry(),
      );
    }
    final state = activity.requireValue;
    final record = state.feed.findById(activityId);
    if (record == null) {
      return _DetailsFailure(
        failure:
            state.refreshFailure ??
            const AppFailure(
              code: 'activity_not_found',
              kind: AppFailureKind.notFound,
              userMessage: 'This transaction is no longer available.',
              retryable: true,
            ),
        loading: state.refreshing,
        onRetry: () =>
            ref.read(activityViewModelProvider(assetKind).notifier).refresh(),
      );
    }
    final preferences = settings.requireValue.snapshot.preferences;
    final valuesVisible = preferences.balancesVisible;
    final amount = formatter.amountText(record, preferences.bitcoinUnit);
    final entries = _entries(
      record: record,
      feed: state.feed,
      bitcoinUnit: preferences.bitcoinUnit,
      valuesVisible: valuesVisible,
      formatter: formatter,
    );
    final txid = record.txid;
    final explorerUri = txid == null
        ? null
        : ref
              .watch(walletServiceConfigurationProvider)
              .transactionExplorerUri(txid);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            context.spacing.screenPadding,
            context.spacing.xl,
            context.spacing.screenPadding,
            context.spacing.xxl,
          ),
          sliver: SliverList.list(
            children: [
              Semantics(
                label:
                    '${formatter.activityTitle(record)}, '
                    '${valuesVisible ? amount ?? 'Amount unavailable' : 'Amount hidden'}, '
                    '${formatter.statusLabel(record.status)}',
                excludeSemantics: true,
                child: Column(
                  children: [
                    WalletAssetIcon(
                      kind: record.asset.kind,
                      size: context.icons.xl,
                    ),
                    SizedBox(height: context.spacing.md),
                    Text(
                      formatter.activityTitle(record),
                      style: context.type.title,
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: context.spacing.xs),
                    AmountText(
                      valuesVisible ? amount ?? '--' : '••••',
                      style: context.type.amountLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: context.spacing.md),
                    _StatusBadge(
                      status: record.status,
                      label: formatter.statusLabel(record.status),
                    ),
                  ],
                ),
              ),
              SizedBox(height: context.spacing.sectionGap),
              Squircle(
                color: context.appColors.surfaceRaised,
                padding: EdgeInsets.symmetric(horizontal: context.spacing.lg),
                child: Column(
                  children: [
                    for (var index = 0; index < entries.length; index += 1) ...[
                      TransactionDetailRow(
                        label: entries[index].label,
                        value: entries[index].value,
                        amount: entries[index].amount,
                        copying: copyingFields.contains(entries[index].label),
                        onCopy: entries[index].copyValue == null
                            ? null
                            : () => onCopy(
                                entries[index].label,
                                entries[index].copyValue!,
                              ),
                      ),
                      if (index < entries.length - 1) const AsterDivider(),
                    ],
                  ],
                ),
              ),
              if (explorerUri != null) ...[
                SizedBox(height: context.spacing.sectionGap),
                CustomButton(
                  text: 'View in explorer',
                  suffixIcon: RemixIcons.external_link_line,
                  loading: openingExplorer,
                  hapticIntent: null,
                  onTap: () => onOpenExplorer(explorerUri),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static AppFailure _failure(Object error, StackTrace stackTrace) =>
      error is AppFailureException
      ? error.failure
      : FailureMapper.from(error, stackTrace);

  static List<_DetailEntry> _entries({
    required WalletActivity record,
    required WalletActivityFeed feed,
    required BitcoinUnit bitcoinUnit,
    required bool valuesVisible,
    required ActivityDisplayFormatter formatter,
  }) {
    final entries = <_DetailEntry>[
      _DetailEntry('Status', formatter.statusLabel(record.status)),
      _DetailEntry('Date', formatter.dateTimeLabel(record.occurredAt)),
      _DetailEntry(
        'Network',
        formatter.networkLabel(feed.networkStatus.environment),
      ),
      _DetailEntry('Payment rail', formatter.railLabel(record.rail)),
      _DetailEntry('Type', formatter.operationLabel(record.operation)),
    ];
    final amount = formatter.amountText(record, bitcoinUnit);
    if (amount != null) {
      entries.add(
        _DetailEntry('Amount', valuesVisible ? amount : 'Hidden', amount: true),
      );
    }
    final fee = formatter.feeText(record, bitcoinUnit);
    if (fee != null) {
      entries.add(
        _DetailEntry(
          'Network fee',
          valuesVisible ? fee : 'Hidden',
          amount: true,
        ),
      );
    }
    if (record.updatedAt != null && record.updatedAt != record.occurredAt) {
      entries.add(
        _DetailEntry('Last updated', formatter.dateTimeLabel(record.updatedAt)),
      );
    }
    final confirmations = feed.confirmationsFor(record);
    if (confirmations != null) {
      entries.add(
        _DetailEntry('Confirmations', confirmations.toString(), amount: true),
      );
    }
    if (record.confirmationHeight case final value?) {
      entries.add(_DetailEntry('Block height', value.toString(), amount: true));
    }
    if (record.txid case final value?) {
      entries.add(
        _DetailEntry(
          'Transaction ID',
          formatter.compactIdentifier(value),
          copyValue: value,
        ),
      );
    }
    if (record.paymentHash case final value?) {
      entries.add(
        _DetailEntry(
          'Payment hash',
          formatter.compactIdentifier(value),
          copyValue: value,
        ),
      );
    }
    if (record.invoice case final value?) {
      entries.add(
        _DetailEntry(
          'Invoice',
          formatter.compactIdentifier(value),
          copyValue: value,
        ),
      );
    }
    if (record.recipientId case final value?) {
      entries.add(
        _DetailEntry(
          'Recipient',
          formatter.compactIdentifier(value),
          copyValue: value,
        ),
      );
    }
    if (record.payeePublicKey case final value?) {
      entries.add(
        _DetailEntry(
          'Payee public key',
          formatter.compactIdentifier(value),
          copyValue: value,
        ),
      );
    }
    if (record.transferIndex case final value?) {
      entries.add(
        _DetailEntry('Transfer index', value.toString(), amount: true),
      );
    }
    if (record.batchTransferIndex case final value?) {
      entries.add(
        _DetailEntry('Batch transfer index', value.toString(), amount: true),
      );
    }
    if (record.expiresAt case final value?) {
      entries.add(_DetailEntry('Expires', formatter.dateTimeLabel(value)));
    }
    if (record.receiveOutpoint case final value?) {
      entries.add(
        _DetailEntry(
          'Receive outpoint',
          formatter.compactIdentifier(value),
          copyValue: value,
        ),
      );
    }
    if (record.changeOutpoint case final value?) {
      entries.add(
        _DetailEntry(
          'Change outpoint',
          formatter.compactIdentifier(value),
          copyValue: value,
        ),
      );
    }
    if (record.transportEndpointCount > 0) {
      entries.add(
        _DetailEntry(
          'RGB transports',
          '${record.usedTransportEndpointCount} of '
              '${record.transportEndpointCount} used',
        ),
      );
    }
    if (record.transportTypes.isNotEmpty) {
      entries.add(
        _DetailEntry('Transport types', record.transportTypes.join(', ')),
      );
    }
    return entries;
  }
}

class _DetailEntry {
  const _DetailEntry(
    this.label,
    this.value, {
    this.amount = false,
    this.copyValue,
  });

  final String label;
  final String value;
  final bool amount;
  final String? copyValue;
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.label});

  final WalletActivityStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      WalletActivityStatus.succeeded => (
        context.appColors.successContainer,
        context.appColors.success,
      ),
      WalletActivityStatus.failed ||
      WalletActivityStatus.cancelled ||
      WalletActivityStatus.expired => (
        context.appColors.dangerContainer,
        context.appColors.danger,
      ),
      WalletActivityStatus.pending ||
      WalletActivityStatus.waitingCounterparty ||
      WalletActivityStatus.waitingSafeHeight ||
      WalletActivityStatus.waitingConfirmations ||
      WalletActivityStatus.claimable ||
      WalletActivityStatus.claiming => (
        context.appColors.warningContainer,
        context.appColors.warning,
      ),
    };
    return AsterPill(
      color: background,
      padding: EdgeInsets.symmetric(
        horizontal: context.spacing.md,
        vertical: context.spacing.xs,
      ),
      child: Text(
        label,
        style: context.type.badgeLabel.copyWith(color: foreground),
      ),
    );
  }
}

class _DetailsFailure extends StatelessWidget {
  const _DetailsFailure({
    required this.failure,
    required this.onRetry,
    this.loading = false,
  });

  final AppFailure failure;
  final VoidCallback onRetry;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(context.spacing.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              RemixIcons.error_warning_line,
              size: context.icons.lg,
              color: context.appColors.danger,
            ),
            SizedBox(height: context.spacing.lg),
            Text(
              failure.userMessage,
              style: context.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (failure.retryable) ...[
              SizedBox(height: context.spacing.lg),
              CustomButton.compact(
                text: 'Retry',
                loading: loading,
                hapticIntent: null,
                onTap: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailsLoadingView extends StatelessWidget {
  const _DetailsLoadingView();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AppSkeletonizer(
        enabled: true,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            context.spacing.screenPadding,
            context.spacing.xl,
            context.spacing.screenPadding,
            context.spacing.xxl,
          ),
          child: Column(
            children: [
              Container(
                width: context.icons.xl,
                height: context.icons.xl,
                decoration: BoxDecoration(
                  color: context.appColors.surfaceSubtle,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(height: context.spacing.md),
              Text('Transaction loading', style: context.type.title),
              SizedBox(height: context.spacing.xs),
              AmountText('0 sats', style: context.type.amountLarge),
              SizedBox(height: context.spacing.sectionGap),
              Squircle(
                color: context.appColors.surfaceRaised,
                padding: EdgeInsets.symmetric(horizontal: context.spacing.lg),
                child: Column(
                  children: [
                    for (var index = 0; index < 5; index += 1) ...[
                      const TransactionDetailRow(
                        label: 'Detail loading',
                        value: 'Value loading',
                      ),
                      if (index < 4) const AsterDivider(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
