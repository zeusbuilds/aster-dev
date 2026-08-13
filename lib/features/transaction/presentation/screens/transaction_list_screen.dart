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

    Future<void> refresh() async {
      final notifier = ref.read(activityViewModelProvider(assetKind).notifier);
      if (ref.read(activityViewModelProvider(assetKind)).value == null) {
        await notifier.retry();
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
      context.toasts.show(
        title: 'Activity refresh failed',
        message: failure.userMessage,
        variant: ToastVariant.failure,
      );
      notifier.clearRefreshFailure();
    }

    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: CustomAppBar(
        title:
            '${TransactionListScreen._formatter.assetTitle(assetKind)} Activity',
        leadingIcon: true,
        centerTitle: false,
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: refresh,
          child: _ActivityBody(
            activity: activity,
            settings: settings,
            assetKind: assetKind,
            now: _now,
            formatter: TransactionListScreen._formatter,
          ),
        ),
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
  });

  final AsyncValue<ActivityState> activity;
  final AsyncValue<SettingsState> settings;
  final WalletAssetKind assetKind;
  final DateTime now;
  final ActivityDisplayFormatter formatter;

  @override
  Widget build(BuildContext context) {
    if (activity.isLoading || settings.isLoading) {
      return const _ActivityLoadingView();
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
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            context.spacing.screenPadding,
            context.spacing.lg,
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
          sliver: SliverToBoxAdapter(
            child: Text('Activity', style: context.type.sectionTitle),
          ),
        ),
        if (records.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyActivity(assetKind: assetKind),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(
              horizontal: context.spacing.screenPadding,
            ),
            sliver: SliverList.builder(
              itemCount: records.length,
              itemBuilder: (context, index) {
                final record = records[index];
                final group = formatter.groupLabel(record.occurredAt, now);
                final previousGroup = index == 0
                    ? null
                    : formatter.groupLabel(records[index - 1].occurredAt, now);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (group != previousGroup) ...[
                      if (index > 0) SizedBox(height: context.spacing.lg),
                      Text(group, style: context.type.sectionLabel),
                      SizedBox(height: context.spacing.sm),
                    ],
                    TransactionItem(
                      key: ValueKey(record.id),
                      activity: record,
                      bitcoinUnit: preferences.bitcoinUnit,
                      valuesVisible: preferences.balancesVisible,
                      formatter: formatter,
                      onTap: () {
                        unawaited(
                          context.haptics.trigger(HapticIntent.lightImpact),
                        );
                        unawaited(
                          context.pushNamed(
                            RouteNames.transactionDetails,
                            pathParameters: <String, String>{
                              RoutePaths.assetKindParameter: assetKind.slug,
                              RoutePaths.activityIdParameter: record.id,
                            },
                          ),
                        );
                      },
                    ),
                    SizedBox(height: context.spacing.md),
                  ],
                );
              },
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: context.spacing.xxl)),
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
            padding: EdgeInsets.all(context.spacing.screenPadding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
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
  const _EmptyActivity({required this.assetKind});

  final WalletAssetKind assetKind;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(context.spacing.screenPadding),
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
          SizedBox(height: context.spacing.sm),
          Text(
            'Completed and pending payments will appear here.',
            style: context.type.rowMeta,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ActivityLoadingView extends StatelessWidget {
  const _ActivityLoadingView();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Loading activity',
      excludeSemantics: true,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.all(context.spacing.screenPadding),
            sliver: SliverList.builder(
              itemCount: 5,
              itemBuilder: (context, index) => Padding(
                padding: EdgeInsets.only(bottom: context.spacing.md),
                child: AppSkeletonizer(
                  enabled: true,
                  child: Squircle(
                    color: context.appColors.surfaceRaised,
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
                              Text(
                                'Activity loading',
                                style: context.type.rowTitle,
                              ),
                              SizedBox(height: context.spacing.xs),
                              Text(
                                'Status loading',
                                style: context.type.rowMeta,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
