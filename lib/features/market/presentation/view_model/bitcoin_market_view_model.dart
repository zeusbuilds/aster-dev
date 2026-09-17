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
  Timer? _backgroundRetryTimer;
  late RetryPolicy? _backgroundRetryPolicy;
  var _backgroundRetryAttempts = 0;
  var _stateGeneration = 0;
  var _observationGeneration = 0;
  var _observed = true;

  @override
  Future<BitcoinMarketState> build() async {
    final generation = ++_stateGeneration;
    _activeRequest?.cancel();
    _backgroundRetryTimer?.cancel();
    _backgroundRetryAttempts = 0;
    _backgroundRetryPolicy = ref.watch(
      bitcoinMarketBackgroundRetryPolicyProvider,
    );
    ref.onCancel(_handleObservationCancelled);
    ref.onResume(_handleObservationResumed);
    ref.onDispose(() {
      _activeRequest?.cancel();
      _cancelBackgroundRetry();
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
      _finishAttempt(failure: load.degradedFailure, generation: generation);
      return next;
    } catch (error, stackTrace) {
      final failure = FailureMapper.from(error, stackTrace);
      _finishAttempt(failure: failure, generation: generation);
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

    _backgroundRetryTimer?.cancel();
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
      _finishAttempt(failure: load.degradedFailure, generation: generation);
      return;
    } catch (error, stackTrace) {
      if (!ref.mounted || generation != _stateGeneration) return;
      final failure = FailureMapper.from(error, stackTrace);
      state = AsyncData(
        current.copyWith(refreshing: false, refreshFailure: failure),
      );
      _finishAttempt(failure: failure, generation: generation);
    }
  }

  void _finishAttempt({required AppFailure? failure, required int generation}) {
    if (failure == null) {
      _backgroundRetryAttempts = 0;
      _cancelBackgroundRetry();
      return;
    }
    _scheduleBackgroundRetry(failure, generation);
  }

  void _scheduleBackgroundRetry(AppFailure failure, int generation) {
    _cancelBackgroundRetry();
    if (!ref.mounted || generation != _stateGeneration) return;
    final policy = _backgroundRetryPolicy;
    if (policy == null) return;

    var delay = policy.delayFor(_backgroundRetryAttempts);
    _backgroundRetryAttempts += 1;
    if (failure.retryAfter case final retryAfter? when retryAfter > delay) {
      delay = retryAfter;
    }
    _backgroundRetryTimer = Timer(delay, () {
      _backgroundRetryTimer = null;
      if (!ref.mounted || generation != _stateGeneration) return;
      unawaited(_refresh());
    });
  }

  void _cancelBackgroundRetry() {
    _backgroundRetryTimer?.cancel();
    _backgroundRetryTimer = null;
  }

  void _handleObservationCancelled() {
    _observed = false;
    _observationGeneration += 1;
    _cancelBackgroundRetry();
  }

  void _handleObservationResumed() {
    _observed = true;
    final observationGeneration = ++_observationGeneration;
    scheduleMicrotask(() {
      if (!_observed || observationGeneration != _observationGeneration) {
        return;
      }
      _resumeBackgroundRetry();
    });
  }

  void _resumeBackgroundRetry() {
    if (!ref.mounted || _backgroundRetryTimer != null) return;
    final current = state.value;
    final failure = current?.refreshFailure;
    if (failure == null || current!.refreshing) return;
    _scheduleBackgroundRetry(failure, _stateGeneration);
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
