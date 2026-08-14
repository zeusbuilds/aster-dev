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
class TransactionDetailsScreen extends ConsumerWidget {
  const TransactionDetailsScreen({
    super.key,
    required this.assetKind,
    required this.activityId,
  });

  final WalletAssetKind assetKind;
  final String activityId;

  static final _formatter = ActivityDisplayFormatter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(activityViewModelProvider(assetKind));
    final settings = ref.watch(settingsViewModelProvider);
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: CustomAppBar(
        title: 'Transaction details',
        leadingIcon: true,
        centerTitle: false,
        fallbackLocation: RoutePaths.transactionListFor(assetKind.slug),
      ),
      body: SafeArea(
        top: false,
        child: _DetailsBody(
          activity: activity,
          settings: settings,
          assetKind: assetKind,
          activityId: activityId,
          formatter: _formatter,
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
  });

  final AsyncValue<ActivityState> activity;
  final AsyncValue<SettingsState> settings;
  final WalletAssetKind assetKind;
  final String activityId;
  final ActivityDisplayFormatter formatter;

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
    final actionsProvider = transactionDetailsActionsViewModelProvider(
      record.id,
      record.txid,
    );
    final actions = ref.watch(actionsProvider);
    final amount = formatter.amountText(record, preferences.bitcoinUnit);
    final entries = _entries(
      record: record,
      feed: state.feed,
      bitcoinUnit: preferences.bitcoinUnit,
      valuesVisible: valuesVisible,
      formatter: formatter,
    );
    final actionsNotifier = ref.read(actionsProvider.notifier);

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
                    '${formatter.assetTitle(record.asset.kind)}, '
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
                        identifier: entries[index].identifier,
                        copying:
                            actions.copyingField == entries[index].copyField,
                        copyEnabled: actions.copyingField == null,
                        onCopy: entries[index].copyValue == null
                            ? null
                            : () => _copy(
                                context,
                                actionsNotifier,
                                entries[index].copyField!,
                                entries[index].label,
                                entries[index].copyValue!,
                              ),
                      ),
                      if (index < entries.length - 1) const AsterDivider(),
                    ],
                  ],
                ),
              ),
              if (actions.explorerUri != null) ...[
                SizedBox(height: context.spacing.sectionGap),
                CustomButton(
                  text: 'View in explorer',
                  suffixIcon: RemixIcons.external_link_line,
                  loading: actions.openingExplorer,
                  hapticIntent: null,
                  onTap: () => _openExplorer(context, actionsNotifier),
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

  static Future<void> _copy(
    BuildContext context,
    TransactionDetailsActionsViewModel notifier,
    TransactionDetailField field,
    String label,
    String value,
  ) async {
    final result = await notifier.copyField(field, value);
    if (!context.mounted || result == null) return;
    switch (result) {
      case AppSuccess<void>():
        context.toasts.show(
          title: '$label copied',
          variant: ToastVariant.success,
        );
      case AppFailureResult<void>(:final failure):
        context.toasts.show(
          title: 'Could not copy $label',
          message: failure.userMessage,
          variant: ToastVariant.failure,
        );
    }
  }

  static Future<void> _openExplorer(
    BuildContext context,
    TransactionDetailsActionsViewModel notifier,
  ) async {
    final result = await notifier.openExplorer();
    if (!context.mounted || result == null) return;
    if (result case AppFailureResult<void>(:final failure)) {
      context.toasts.show(
        title: 'Could not open explorer',
        message: failure.userMessage,
        variant: ToastVariant.failure,
      );
    }
  }

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
    if (record.confirmedAt case final value?) {
      entries.add(_DetailEntry('Confirmed', formatter.dateTimeLabel(value)));
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
          copyField: TransactionDetailField.transactionId,
          copyValue: value,
          identifier: true,
        ),
      );
    }
    if (record.paymentHash case final value?) {
      entries.add(
        _DetailEntry(
          'Payment hash',
          formatter.compactIdentifier(value),
          copyField: TransactionDetailField.paymentHash,
          copyValue: value,
          identifier: true,
        ),
      );
    }
    if (record.invoice case final value?) {
      entries.add(
        _DetailEntry(
          'Invoice',
          formatter.compactIdentifier(value),
          copyField: TransactionDetailField.invoice,
          copyValue: value,
          identifier: true,
        ),
      );
    }
    if (record.recipientId case final value?) {
      entries.add(
        _DetailEntry(
          'Recipient',
          formatter.compactIdentifier(value),
          copyField: TransactionDetailField.recipient,
          copyValue: value,
          identifier: true,
        ),
      );
    }
    if (record.payeePublicKey case final value?) {
      entries.add(
        _DetailEntry(
          'Payee public key',
          formatter.compactIdentifier(value),
          copyField: TransactionDetailField.payeePublicKey,
          copyValue: value,
          identifier: true,
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
          copyField: TransactionDetailField.receiveOutpoint,
          copyValue: value,
          identifier: true,
        ),
      );
    }
    if (record.changeOutpoint case final value?) {
      entries.add(
        _DetailEntry(
          'Change outpoint',
          formatter.compactIdentifier(value),
          copyField: TransactionDetailField.changeOutpoint,
          copyValue: value,
          identifier: true,
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
    this.identifier = false,
    this.copyField,
    this.copyValue,
  }) : assert(!amount || !identifier),
       assert((copyField == null) == (copyValue == null));

  final String label;
  final String value;
  final bool amount;
  final bool identifier;
  final TransactionDetailField? copyField;
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
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Loading transaction details',
      excludeSemantics: true,
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
