import 'package:flutter/foundation.dart';

import '../../../../core/core.dart';
import '../../../wallet/domain/models/models.dart';

/// Loaded Activity content with operation-specific refresh state.
@immutable
final class ActivityState {
  const ActivityState({
    required this.feed,
    this.refreshing = false,
    this.refreshFailure,
  });

  final WalletActivityFeed feed;
  final bool refreshing;
  final AppFailure? refreshFailure;

  ActivityState copyWith({
    WalletActivityFeed? feed,
    bool? refreshing,
    AppFailure? refreshFailure,
    bool clearRefreshFailure = false,
  }) {
    return ActivityState(
      feed: feed ?? this.feed,
      refreshing: refreshing ?? this.refreshing,
      refreshFailure: clearRefreshFailure
          ? null
          : refreshFailure ?? this.refreshFailure,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ActivityState &&
      other.feed == feed &&
      other.refreshing == refreshing &&
      other.refreshFailure == refreshFailure;

  @override
  int get hashCode => Object.hash(feed, refreshing, refreshFailure);
}
