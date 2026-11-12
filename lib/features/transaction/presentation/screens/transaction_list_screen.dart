import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../../settings/presentation/models/models.dart';
import '../../../settings/presentation/view_model/view_models.dart';
import '../../../wallet/domain/models/models.dart';
import '../formatting/formatting.dart';
import '../models/models.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

/// Real cross-rail Activity for one product asset.
class TransactionListScreen extends ConsumerStatefulWidget {
  const TransactionListScreen({super.key, required this.assetKind});

  final WalletAssetKind assetKind;

  static final _formatter = ActivityDisplayFormatter();

  @override
  ConsumerState<TransactionListScreen> createState() =>
      _TransactionListScreenState();
}

class _TransactionListScreenState extends ConsumerState<TransactionListScreen>
    with WidgetsBindingObserver {
  static const _calendarBoundaryEpsilon = Duration(milliseconds: 1);

  Timer? _calendarTimer;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _now = ref.read(utcClockProvider)().toUtc();
    _scheduleCalendarBoundary(_now);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshCalendarClock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _calendarTimer?.cancel();
    super.dispose();
  }

  void _refreshCalendarClock() {
    final now = ref.read(utcClockProvider)().toUtc();
    if (_now != now) setState(() => _now = now);
    _scheduleCalendarBoundary(now);
  }

  void _scheduleCalendarBoundary(DateTime now) {
    _calendarTimer?.cancel();
    final localNow = now.toLocal();
    final nextLocalDay = DateTime(
      localNow.year,
      localNow.month,
      localNow.day + 1,
    );
    final delay = nextLocalDay.difference(localNow);
    _calendarTimer = Timer(delay + _calendarBoundaryEpsilon, () {
      if (mounted) _refreshCalendarClock();
    });
  }

  @override
  Widget build(BuildContext context) {
    final assetKind = widget.assetKind;
    final activity = ref.watch(activityViewModelProvider(assetKind));
    final settings = ref.watch(settingsViewModelProvider);
    final isDuoCover =
        ref
            .watch(duoCoverLayoutProvider)
            .value
            ?.appliesTo(MediaQuery.sizeOf(context)) ==
        true;

    Future<void> refresh() async {
      final toasts = context.toasts;
      final activityProvider = activityViewModelProvider(assetKind);
      final notifier = ref.read(activityProvider.notifier);
      if (ref.read(activityProvider).value == null) {
        await notifier.retry();
        return;
      }
      if (ref.read(settingsViewModelProvider).value == null) {
        await ref.read(settingsViewModelProvider.notifier).retry();
        return;
      }
      final completed = await notifier.refresh();
      if (!context.mounted || completed) return;
      final failure = ref
          .read(activityViewModelProvider(assetKind))
          .value
          ?.refreshFailure;
      if (failure == null) return;
      unawaited(context.haptics.trigger(HapticIntent.error));
      toasts.show(
        title: 'Activity refresh failed',
        message: failure.userMessage,
        variant: ToastVariant.failure,
      );
      notifier.clearRefreshFailure();
    }

    return AsterNavigationScope(
      child: Builder(
        builder: (context) {
          final navigation = AsterNavigationScope.of(context);

          void openDetails(String activityId) {
            unawaited(
              navigation.openRoute(
                command: () => context.pushNamed<void>(
                  RouteNames.transactionDetails,
                  pathParameters: <String, String>{
                    RoutePaths.assetKindParameter: widget.assetKind.slug,
                    RoutePaths.activityIdParameter: activityId,
                  },
                ),
                failureTitle: 'Transaction details could not be opened',
              ),
            );
          }

          return AsterPageScaffold(
            backgroundColor: context.colorScheme.surface,
            appBar: CustomAppBar(
              title:
                  '${TransactionListScreen._formatter.assetTitle(assetKind)} Activity',
              leadingIcon: true,
              centerTitle: false,
            ),
            body: AsterCenteredSafeArea(
              top: false,
              bottom: false,
              centerHorizontally:
                  !activity.isLoading &&
                  !settings.isLoading &&
                  (activity.hasError || settings.hasError),
              child: RefreshIndicator(
                onRefresh: refresh,
                child: _ActivityBody(
                  activity: activity,
                  settings: settings,
                  assetKind: assetKind,
                  now: _now,
                  formatter: TransactionListScreen._formatter,
                  onOpenDetails: navigation.inFlight ? null : openDetails,
                  isDuoCover: isDuoCover,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ActivityBody extends StatelessWidget {
  const _ActivityBody({
    required this.activity,
    required this.settings,
    required this.assetKind,
    required this.now,
    required this.formatter,
    required this.onOpenDetails,
    required this.isDuoCover,
  });

  final AsyncValue<ActivityState> activity;
  final AsyncValue<SettingsState> settings;
  final WalletAssetKind assetKind;
  final DateTime now;
  final ActivityDisplayFormatter formatter;
  final ValueChanged<String>? onOpenDetails;
  final bool isDuoCover;

  @override
  Widget build(BuildContext context) {
    if (activity.isLoading || settings.isLoading) {
      return _ActivityLoadingView(isDuoCover: isDuoCover);
    }
    if (activity case AsyncError(:final error, :final stackTrace)) {
      return _ActivityFailureView(
        failure: _failure(error, stackTrace),
        assetKind: assetKind,
      );
    }
    if (settings case AsyncError(:final error, :final stackTrace)) {
      return _ActivityFailureView(
        failure: _failure(error, stackTrace),
        assetKind: assetKind,
        retrySettings: true,
      );
    }
    final state = activity.requireValue;
    final preferences = settings.requireValue.snapshot.preferences;
    final records = state.feed.activities;
    final submission = state.feed.paymentSubmission;
    final display = submission == null
        ? null
        : PaymentSubmissionDisplay(submission);
    final showSubmission = display?.visibleIn(state.feed) ?? false;
    final entries =
        <(WalletActivity?, PaymentSubmissionDisplay?, DateTime?)>[
          for (final record in records) (record, null, record.occurredAt),
          if (showSubmission) (null, display, submission!.paymentSubmittedAt),
        ]..sort((left, right) {
          final a = left.$3;
          final b = right.$3;
          if (a == null && b != null) return 1;
          if (a != null && b == null) return -1;
          final byTime = a == null ? 0 : b!.compareTo(a);
          if (byTime != 0) return byTime;
          return (left.$1?.id ?? left.$2!.id).compareTo(
            right.$1?.id ?? right.$2!.id,
          );
        });

    final landscape = context.isOpenDuoLandscape;
    final omitLastItemGap = isDuoCover || landscape;
    final bottomInset =
        context.windowInsets.bottomSafe +
        (landscape ? context.spacing.lg : context.spacing.xxl);
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            context.spacing.screenPadding,
            context.spacing.none,
            context.spacing.screenPadding,
            context.spacing.none,
          ),
          sliver: SliverToBoxAdapter(
            child: ActivityBalanceCard(
              balance: state.feed.balance,
              bitcoinUnit: preferences.bitcoinUnit,
              valuesVisible: preferences.balancesVisible,
              formatter: formatter,
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            context.spacing.screenPadding,
            context.spacing.sectionGap,
            context.spacing.screenPadding,
            context.spacing.md,
          ),
          sliver: SliverToBoxAdapter(child: const SizedBox.shrink()),
        ),
        if (entries.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyActivity(
              assetKind: assetKind,
              bottomInset: landscape ? bottomInset : 0,
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(
              horizontal: context.spacing.screenPadding,
            ),
            sliver: SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                final group = formatter.groupLabel(entry.$3, now);
                final previousGroup = index == 0
                    ? null
                    : formatter.groupLabel(entries[index - 1].$3, now);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (group != previousGroup) ...[
                      if (index > 0) SizedBox(height: context.spacing.lg),
                      Text(group, style: context.type.rowMeta),
                      SizedBox(height: context.spacing.sm),
                    ],
                    if (entry.$1 case final record?)
                      TransactionItem(
                        key: ValueKey(record.id),
                        activity: record,
                        bitcoinUnit: preferences.bitcoinUnit,
                        valuesVisible: preferences.balancesVisible,
                        formatter: formatter,
                        onTap: onOpenDetails == null
                            ? null
                            : () => onOpenDetails!(record.id),
                      ),
                    if (entry.$2 case final pending?)
                      PaymentSubmissionItem(
                        key: ValueKey(pending.id),
                        display: pending,
                        bitcoinUnit: preferences.bitcoinUnit,
                        valuesVisible: preferences.balancesVisible,
                        formatter: formatter,
                        onTap: onOpenDetails == null
                            ? null
                            : () => onOpenDetails!(pending.id),
                      ),
                    if (!omitLastItemGap || index < entries.length - 1)
                      SizedBox(height: context.spacing.md),
                  ],
                );
              },
            ),
          ),
        if (entries.isNotEmpty || !landscape)
          SliverToBoxAdapter(child: SizedBox(height: bottomInset)),
      ],
    );
  }

  static AppFailure _failure(Object error, StackTrace stackTrace) =>
      error is AppFailureException
      ? error.failure
      : FailureMapper.from(error, stackTrace);
}

class _ActivityFailureView extends ConsumerWidget {
  const _ActivityFailureView({
    required this.failure,
    required this.assetKind,
    this.retrySettings = false,
  });

  final AppFailure failure;
  final WalletAssetKind assetKind;
  final bool retrySettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              context.spacing.screenPadding,
              context.spacing.screenPadding,
              context.spacing.screenPadding,
              context.spacing.screenPadding + context.windowInsets.bottomSafe,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  RemixIcons.error_warning_line,
                  size: context.icons.lg,
                  color: context.appColors.danger,
                ),
                SizedBox(height: context.spacing.lg),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    failure.userMessage,
                    style: context.type.statusMessage,
                    textAlign: TextAlign.center,
                  ),
                ),
                if (failure.retryable) ...[
                  SizedBox(height: context.spacing.lg),
                  CustomButton.compact(
                    text: 'Retry',
                    onTap: retrySettings
                        ? () => ref
                              .read(settingsViewModelProvider.notifier)
                              .retry()
                        : () => ref
                              .read(
                                activityViewModelProvider(assetKind).notifier,
                              )
                              .retry(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity({required this.assetKind, required this.bottomInset});

  final WalletAssetKind assetKind;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.all(context.spacing.screenPadding) +
          EdgeInsets.only(bottom: bottomInset),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            RemixIcons.inbox_2_line,
            size: context.icons.lg,
            color: context.appColors.textTertiary,
          ),
          SizedBox(height: context.spacing.lg),
          Text(
            'No ${assetKind == WalletAssetKind.bitcoin ? 'Bitcoin' : 'USDT'} activity yet',
            style: context.type.title,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ActivityLoadingView extends StatelessWidget {
  const _ActivityLoadingView({required this.isDuoCover});

  static const _placeholderCount = 4;
  final bool isDuoCover;

  @override
  Widget build(BuildContext context) {
    final landscape = context.isOpenDuoLandscape;
    final omitLastItemGap = isDuoCover || landscape;
    final bottomInset =
        context.windowInsets.bottomSafe +
        (landscape ? context.spacing.lg : context.spacing.xxl);
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Loading activity',
      excludeSemantics: true,
      child: AppSkeletonizer(
        enabled: true,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                context.spacing.screenPadding,
                context.spacing.lg,
                context.spacing.screenPadding,
                context.spacing.none,
              ),
              sliver: const SliverToBoxAdapter(
                child: _ActivityBalanceLoading(),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                context.spacing.screenPadding,
                context.spacing.sectionGap,
                context.spacing.screenPadding,
                context.spacing.md,
              ),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Activity',
                  key: const ValueKey('activity-loading-heading'),
                  style: context.type.sectionTitle,
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(
                horizontal: context.spacing.screenPadding,
              ),
              sliver: SliverList.builder(
                itemCount: _placeholderCount,
                itemBuilder: (context, index) => Padding(
                  padding: EdgeInsets.only(
                    bottom: !omitLastItemGap || index < _placeholderCount - 1
                        ? context.spacing.md
                        : 0,
                  ),
                  child: _ActivityItemLoading(index: index),
                ),
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: bottomInset)),
          ],
        ),
      ),
    );
  }
}

class _ActivityBalanceLoading extends StatelessWidget {
  const _ActivityBalanceLoading();

  @override
  Widget build(BuildContext context) {
    return Squircle(
      key: const ValueKey('activity-loading-balance'),
      color: context.appColors.surfaceRaised,
      padding: EdgeInsets.all(context.spacing.screenPadding),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total balance', style: context.type.rowMeta),
                SizedBox(height: context.spacing.xxs),
                AmountText(
                  '000 000 sats',
                  style: context.type.amountInline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          SizedBox(width: context.spacing.lg),
          Container(
            width: context.icons.xl,
            height: context.icons.xl,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.appColors.surfaceSubtle,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityItemLoading extends StatelessWidget {
  const _ActivityItemLoading({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      key: ValueKey('activity-loading-item-$index'),
      constraints: BoxConstraints(minHeight: context.metrics.minTouchTarget),
      child: Padding(
        padding: EdgeInsets.all(context.spacing.lg),
        child: Row(
          children: [
            Container(
              width: context.icons.xl,
              height: context.icons.xl,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.appColors.surfaceSubtle,
              ),
            ),
            SizedBox(width: context.spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Activity loading', style: context.type.rowTitle),
                  SizedBox(height: context.spacing.xxs),
                  NumericText(
                    '00:00, Status loading',
                    style: context.type.rowMeta,
                  ),
                ],
              ),
            ),
            SizedBox(width: context.spacing.sm),
            Flexible(
              child: AmountText(
                '000 sats',
                style: context.type.amountInline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
