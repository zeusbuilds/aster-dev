import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../../settings/presentation/view_model/view_models.dart';
import '../../data/data.dart';
import '../../domain/models/models.dart';
import '../models/models.dart';

part 'bitcoin_market_view_model.g.dart';

@riverpod
BitcoinMarketRepository bitcoinMarketRepository(Ref ref) {
  return BitcoinMarketRepository(
    ref.watch(resilientHttpClientProvider),
    ref.watch(marketDataConfigurationProvider),
    clock: ref.watch(utcClockProvider),
  );
}

/// Backoff used after the bounded request-level retry budget is exhausted.
@riverpod
RetryPolicy? bitcoinMarketBackgroundRetryPolicy(Ref ref) {
  return RetryPolicy(
    maxAttempts: 1,
    baseDelay: const Duration(seconds: 5),
    maximumDelay: const Duration(minutes: 1),
  );
}

/// Maps the persisted settings selection to the market provider contract.
@riverpod
Future<MarketQuoteCurrency> selectedMarketQuoteCurrency(Ref ref) async {
  final selected = await ref.watch(
    settingsViewModelProvider.selectAsync(
      (state) => state.snapshot.selectedCurrency,
    ),
  );
  return MarketQuoteCurrency(
    code: selected.code,
    symbol: selected.symbol,
    minorUnitDigits: selected.minorUnitDigits,
  );
}

/// Owns retained market data and cancellable background recovery.
@riverpod
class BitcoinMarketViewModel extends _$BitcoinMarketViewModel {
  NetworkCancellationToken? _activeRequest;
  Timer? _backgroundRefreshTimer;
  late RetryPolicy? _backgroundRetryPolicy;
  var _backgroundRetryAttempts = 0;
  var _stateGeneration = 0;
  var _observationGeneration = 0;
  var _observed = true;

  @override
  Future<BitcoinMarketState> build() async {
    final generation = ++_stateGeneration;
    _activeRequest?.cancel();
    _cancelBackgroundRefresh();
    _backgroundRetryAttempts = 0;
    _backgroundRetryPolicy = ref.watch(
      bitcoinMarketBackgroundRetryPolicyProvider,
    );
    ref.onCancel(_handleObservationCancelled);
    ref.onResume(_handleObservationResumed);
    ref.onDispose(() {
      _activeRequest?.cancel();
      _cancelBackgroundRefresh();
    });
    final currency = await ref.watch(
      selectedMarketQuoteCurrencyProvider.future,
    );
    try {
      final load = await _fetch(currency);
      final next = BitcoinMarketState(
        snapshot: load.snapshot,
        refreshFailure: load.degradedFailure,
      );
      _finishAttempt(
        snapshot: load.snapshot,
        failure: load.degradedFailure,
        generation: generation,
      );
      return next;
    } catch (error, stackTrace) {
      final failure = FailureMapper.from(error, stackTrace);
      _finishAttempt(snapshot: null, failure: failure, generation: generation);
      return BitcoinMarketState(snapshot: null, refreshFailure: failure);
    }
  }

  /// Immediately retries the idempotent market read.
  ///
  /// This explicit path resets the background backoff. It intentionally
  /// retries every failure category because the operation cannot mutate user
  /// or wallet state; persistent failures remain visually silent.
  Future<void> retry() async {
    _backgroundRetryAttempts = 0;
    await _refresh();
  }

  Future<void> _refresh() async {
    if (state.isLoading) return;
    final current = state.value;
    if (current == null || current.refreshing) return;

    _cancelBackgroundRefresh();
    final generation = ++_stateGeneration;
    state = AsyncData(current.copyWith(refreshing: true));
    try {
      final currency = await ref.read(
        selectedMarketQuoteCurrencyProvider.future,
      );
      final load = await _fetch(currency, forceRefresh: true);
      if (!ref.mounted || generation != _stateGeneration) return;
      state = AsyncData(
        BitcoinMarketState(
          snapshot: load.snapshot,
          refreshFailure: load.degradedFailure,
        ),
      );
      _finishAttempt(
        snapshot: load.snapshot,
        failure: load.degradedFailure,
        generation: generation,
      );
      return;
    } catch (error, stackTrace) {
      if (!ref.mounted || generation != _stateGeneration) return;
      final failure = FailureMapper.from(error, stackTrace);
      state = AsyncData(
        current.copyWith(refreshing: false, refreshFailure: failure),
      );
      _finishAttempt(
        snapshot: current.snapshot,
        failure: failure,
        generation: generation,
      );
    }
  }

  void _finishAttempt({
    required BitcoinMarketSnapshot? snapshot,
    required AppFailure? failure,
    required int generation,
  }) {
    if (!ref.mounted || !_observed || generation != _stateGeneration) return;
    if (failure != null) {
      _scheduleBackgroundRetry(failure, generation);
      return;
    }
    final now = ref.read(utcClockProvider)().toUtc();
    // Tether is optional at the repository boundary so an invalid observation
    // cannot discard valid Bitcoin data. It still needs silent recovery here.
    if (snapshot == null ||
        !snapshot.currentBitcoinPrice.isCurrentAt(now) ||
        snapshot.currentUsdtPrice?.isCurrentAt(now) != true) {
      _scheduleBackgroundRetry(_incompleteFiatQuote, generation);
      return;
    }
    _backgroundRetryAttempts = 0;
    _scheduleQuoteRefresh(snapshot, generation, now);
  }

  void _scheduleQuoteRefresh(
    BitcoinMarketSnapshot snapshot,
    int generation,
    DateTime now,
  ) {
    _cancelBackgroundRefresh();
    if (!ref.mounted || !_observed || generation != _stateGeneration) return;
    final bitcoinExpiry = snapshot.currentBitcoinPrice.expiresAt;
    final usdtExpiry = snapshot.currentUsdtPrice!.expiresAt;
    final earliestExpiry = bitcoinExpiry.isBefore(usdtExpiry)
        ? bitcoinExpiry
        : usdtExpiry;
    _scheduleBackgroundRefresh(
      earliestExpiry.difference(now) + const Duration(milliseconds: 1),
      generation,
    );
  }

  void _scheduleBackgroundRetry(AppFailure failure, int generation) {
    _cancelBackgroundRefresh();
    if (!ref.mounted || !_observed || generation != _stateGeneration) return;
    final policy = _backgroundRetryPolicy;
    if (policy == null) return;

    var delay = policy.delayFor(_backgroundRetryAttempts);
    _backgroundRetryAttempts += 1;
    if (failure.retryAfter case final retryAfter? when retryAfter > delay) {
      delay = retryAfter;
    }
    _scheduleBackgroundRefresh(delay, generation);
  }

  void _scheduleBackgroundRefresh(Duration delay, int generation) {
    _backgroundRefreshTimer = Timer(delay, () {
      _backgroundRefreshTimer = null;
      if (!ref.mounted || !_observed || generation != _stateGeneration) return;
      unawaited(_refresh());
    });
  }

  void _cancelBackgroundRefresh() {
    _backgroundRefreshTimer?.cancel();
    _backgroundRefreshTimer = null;
  }

  void _handleObservationCancelled() {
    _observed = false;
    _observationGeneration += 1;
    _cancelBackgroundRefresh();
  }

  void _handleObservationResumed() {
    _observed = true;
    final observationGeneration = ++_observationGeneration;
    scheduleMicrotask(() {
      if (!_observed || observationGeneration != _observationGeneration) {
        return;
      }
      _resumeBackgroundRefresh();
    });
  }

  void _resumeBackgroundRefresh() {
    if (!ref.mounted || _backgroundRefreshTimer != null || state.isLoading) {
      return;
    }
    final current = state.value;
    if (current == null || current.refreshing) return;
    _finishAttempt(
      snapshot: current.snapshot,
      failure: current.refreshFailure,
      generation: _stateGeneration,
    );
  }

  Future<BitcoinMarketLoad> _fetch(
    MarketQuoteCurrency currency, {
    bool forceRefresh = false,
  }) async {
    _activeRequest?.cancel();
    final cancellation = NetworkCancellationToken();
    _activeRequest = cancellation;
    final repository = ref.read(bitcoinMarketRepositoryProvider);
    try {
      final result = await repository.fetchLoad(
        currency: currency,
        cancellation: cancellation,
        forceRefresh: forceRefresh,
      );
      return switch (result) {
        AppSuccess<BitcoinMarketLoad>(:final value) => value,
        AppFailureResult<BitcoinMarketLoad>(:final failure) =>
          throw AppFailureException(failure),
      };
    } finally {
      if (identical(_activeRequest, cancellation)) _activeRequest = null;
    }
  }
}

const _incompleteFiatQuote = AppFailure(
  code: 'market_fiat_quote_incomplete',
  kind: AppFailureKind.unavailable,
  userMessage: 'Fiat quote is unavailable.',
  retryable: true,
);
