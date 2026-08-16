import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../../settings/presentation/view_model/view_models.dart';
import '../../data/data.dart';
import '../../domain/models/models.dart';

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

/// Owns initial-load and retry state for the Bitcoin market card.
@riverpod
class BitcoinMarketViewModel extends _$BitcoinMarketViewModel {
  NetworkCancellationToken? _activeRequest;
  var _stateGeneration = 0;

  @override
  Future<BitcoinMarketSnapshot> build() async {
    _stateGeneration += 1;
    _activeRequest?.cancel();
    ref.onDispose(() => _activeRequest?.cancel());
    final currency = await ref.watch(
      selectedMarketQuoteCurrencyProvider.future,
    );
    return _fetch(currency);
  }

  /// Force-refreshes loaded data or retries a retryable initial failure.
  Future<void> retry() async {
    if (state.isLoading) return;
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
      return _fetch(currency, forceRefresh: true);
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
