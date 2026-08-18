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

/// Owns initial load and retained-content refresh for market presentation.
@riverpod
class BitcoinMarketViewModel extends _$BitcoinMarketViewModel {
  NetworkCancellationToken? _activeRequest;
  var _stateGeneration = 0;

  @override
  Future<BitcoinMarketState> build() async {
    _stateGeneration += 1;
    _activeRequest?.cancel();
    ref.onDispose(() => _activeRequest?.cancel());
    final currency = await ref.watch(
      selectedMarketQuoteCurrencyProvider.future,
    );
    return BitcoinMarketState(snapshot: await _fetch(currency));
  }

  /// Force-refreshes retained data or retries a retryable initial failure.
  Future<void> retry() async {
    if (state.isLoading) return;
    final current = state.value;
    if (current != null) {
      if (current.refreshing || current.refreshFailure?.retryable == false) {
        return;
      }
      final generation = ++_stateGeneration;
      state = AsyncData(
        current.copyWith(refreshing: true, refreshFailure: null),
      );
      try {
        final currency = await ref.read(
          selectedMarketQuoteCurrencyProvider.future,
        );
        final snapshot = await _fetch(currency, forceRefresh: true);
        if (!ref.mounted || generation != _stateGeneration) return;
        state = AsyncData(BitcoinMarketState(snapshot: snapshot));
      } catch (error, stackTrace) {
        if (!ref.mounted || generation != _stateGeneration) return;
        state = AsyncData(
          current.copyWith(
            refreshing: false,
            refreshFailure: FailureMapper.from(error, stackTrace),
          ),
        );
      }
      return;
    }
    if (state case AsyncError(:final error, :final stackTrace)
        when !FailureMapper.from(error, stackTrace).retryable) {
      return;
    }
    final generation = ++_stateGeneration;
    state = const AsyncLoading();
    final next = await AsyncValue.guard(() async {
      final currency = await ref.read(
        selectedMarketQuoteCurrencyProvider.future,
      );
      return BitcoinMarketState(
        snapshot: await _fetch(currency, forceRefresh: true),
      );
    });
    if (ref.mounted && generation == _stateGeneration) state = next;
  }

  Future<BitcoinMarketSnapshot> _fetch(
    MarketQuoteCurrency currency, {
    bool forceRefresh = false,
  }) async {
    _activeRequest?.cancel();
    final cancellation = NetworkCancellationToken();
    _activeRequest = cancellation;
    final repository = ref.read(bitcoinMarketRepositoryProvider);
    try {
      final result = await repository.fetch(
        currency: currency,
        cancellation: cancellation,
        forceRefresh: forceRefresh,
      );
      return switch (result) {
        AppSuccess<BitcoinMarketSnapshot>(:final value) => value,
        AppFailureResult<BitcoinMarketSnapshot>(:final failure) =>
          throw AppFailureException(failure),
      };
    } finally {
      if (identical(_activeRequest, cancellation)) _activeRequest = null;
    }
  }
}
