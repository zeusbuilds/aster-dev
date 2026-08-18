import 'package:flutter/foundation.dart';

import '../../../../core/errors/errors.dart';
import '../../domain/models/models.dart';

/// Confirmed market data plus the state of an explicit refresh.
///
/// Initial loading and initial failure remain owned by Riverpod's
/// `AsyncValue`. Once a snapshot exists, refresh progress and failure live in
/// this state so presentation never discards confirmed content.
@immutable
final class BitcoinMarketState {
  BitcoinMarketState({
    required this.snapshot,
    this.refreshing = false,
    this.refreshFailure,
  }) {
    if (refreshing && refreshFailure != null) {
      throw ArgumentError(
        'A market refresh cannot be active and failed at the same time.',
      );
    }
  }

  /// Last successfully validated provider snapshot.
  final BitcoinMarketSnapshot snapshot;

  /// Whether a user-requested refresh is currently active.
  final bool refreshing;

  /// Most recent refresh failure while [snapshot] remains available.
  final AppFailure? refreshFailure;

  BitcoinMarketState copyWith({
    BitcoinMarketSnapshot? snapshot,
    bool? refreshing,
    Object? refreshFailure = _unset,
  }) {
    return BitcoinMarketState(
      snapshot: snapshot ?? this.snapshot,
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
