import 'package:flutter/foundation.dart';

import '../../../../core/errors/errors.dart';
import '../../domain/models/models.dart';

/// Market presentation state with retained validated data and silent recovery.
///
/// A failed read is represented here instead of as an `AsyncError` so the
/// owner can keep retrying an idempotent market request in the background.
/// [snapshot] remains available across refresh failures and may be absent only
/// until the first validated quote arrives.
@immutable
final class BitcoinMarketState {
  const BitcoinMarketState({
    required this.snapshot,
    this.refreshing = false,
    this.refreshFailure,
  });

  /// Last successfully validated provider snapshot.
  final BitcoinMarketSnapshot? snapshot;

  /// Whether a foreground or scheduled recovery request is active.
  final bool refreshing;

  /// Most recent complete or partial read failure.
  ///
  /// This is retained while a background attempt is active so an offline
  /// surface does not flicker back to a skeleton between attempts.
  final AppFailure? refreshFailure;

  BitcoinMarketState copyWith({
    Object? snapshot = _unset,
    bool? refreshing,
    Object? refreshFailure = _unset,
  }) {
    return BitcoinMarketState(
      snapshot: identical(snapshot, _unset)
          ? this.snapshot
          : snapshot as BitcoinMarketSnapshot?,
      refreshing: refreshing ?? this.refreshing,
      refreshFailure: identical(refreshFailure, _unset)
          ? this.refreshFailure
          : refreshFailure as AppFailure?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BitcoinMarketState &&
      other.snapshot == snapshot &&
      other.refreshing == refreshing &&
      other.refreshFailure == refreshFailure;

  @override
  int get hashCode => Object.hash(snapshot, refreshing, refreshFailure);
}

const _unset = Object();
