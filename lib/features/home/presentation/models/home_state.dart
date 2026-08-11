import 'package:flutter/foundation.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../wallet/domain/models/models.dart';

/// Loaded Home portfolio plus operation-specific refresh state.
@immutable
final class HomeState {
  const HomeState({
    required this.portfolio,
    this.refreshing = false,
    this.refreshFailure,
  });

  final WalletPortfolio portfolio;
  final bool refreshing;
  final AppFailure? refreshFailure;

  HomeState copyWith({
    WalletPortfolio? portfolio,
    bool? refreshing,
    Object? refreshFailure = _unset,
  }) {
    return HomeState(
      portfolio: portfolio ?? this.portfolio,
      refreshing: refreshing ?? this.refreshing,
      refreshFailure: identical(refreshFailure, _unset)
          ? this.refreshFailure
          : refreshFailure as AppFailure?,
    );
  }
}

const _unset = Object();
