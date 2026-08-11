import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../data/data.dart';

part 'bitcoin_market_view_model.g.dart';

@riverpod
BitcoinMarketRepository bitcoinMarketRepository(Ref ref) {
  return BitcoinMarketRepository(
    ref.watch(resilientHttpClientProvider),
    clock: ref.watch(utcClockProvider),
  );
}

/// Owns initial-load and retry state for the Bitcoin market card.
@riverpod
class BitcoinMarketViewModel extends _$BitcoinMarketViewModel {
  NetworkCancellationToken? _activeRequest;

  @override
  Future<BitcoinMarketSnapshot> build() {
    ref.onDispose(() => _activeRequest?.cancel());
    return _fetch();
  }

  Future<void> retry() async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    final next = await AsyncValue.guard(_fetch);
    if (ref.mounted) state = next;
  }

  Future<BitcoinMarketSnapshot> _fetch() async {
    _activeRequest?.cancel();
    final cancellation = NetworkCancellationToken();
    _activeRequest = cancellation;
    final repository = ref.read(bitcoinMarketRepositoryProvider);
    try {
      final result = await repository.fetch(cancellation: cancellation);
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
