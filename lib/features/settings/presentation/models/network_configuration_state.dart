import 'package:flutter/foundation.dart';

import '../../../../core/config/config.dart';
import '../../../../core/errors/app_failure.dart';
import '../../../wallet/domain/models/models.dart';

/// Read-only public network configuration and live wallet-node health.
@immutable
final class NetworkConfigurationState {
  const NetworkConfigurationState({
    required this.configuration,
    this.status,
    this.healthFailure,
    this.refreshing = false,
  });

  final WalletServiceConfiguration configuration;
  final WalletNetworkStatus? status;
  final AppFailure? healthFailure;
  final bool refreshing;

  NetworkConfigurationState copyWith({
    Object? status = _unset,
    Object? healthFailure = _unset,
    bool? refreshing,
  }) {
    return NetworkConfigurationState(
      configuration: configuration,
      status: identical(status, _unset)
          ? this.status
          : status as WalletNetworkStatus?,
      healthFailure: identical(healthFailure, _unset)
          ? this.healthFailure
          : healthFailure as AppFailure?,
      refreshing: refreshing ?? this.refreshing,
    );
  }
}

const _unset = Object();
