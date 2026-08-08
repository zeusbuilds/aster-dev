import 'package:flutter/foundation.dart';

import '../../../../core/errors/app_failure.dart';
import '../../domain/models/models.dart';

/// Immutable wallet-profile presentation state.
@immutable
class WalletState {
  WalletState({
    List<WalletProfile> wallets = const [],
    this.activeWallet,
    this.switchingWalletId,
    this.operationFailure,
  }) : wallets = List<WalletProfile>.unmodifiable(wallets);

  final List<WalletProfile> wallets;
  final WalletProfile? activeWallet;
  final String? switchingWalletId;
  final AppFailure? operationFailure;

  WalletState copyWith({
    List<WalletProfile>? wallets,
    Object? activeWallet = _unset,
    Object? switchingWalletId = _unset,
    Object? operationFailure = _unset,
  }) {
    return WalletState(
      wallets: wallets == null ? this.wallets : List.unmodifiable(wallets),
      activeWallet: identical(activeWallet, _unset)
          ? this.activeWallet
          : activeWallet as WalletProfile?,
      switchingWalletId: identical(switchingWalletId, _unset)
          ? this.switchingWalletId
          : switchingWalletId as String?,
      operationFailure: identical(operationFailure, _unset)
          ? this.operationFailure
          : operationFailure as AppFailure?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WalletState &&
      listEquals(other.wallets, wallets) &&
      other.activeWallet == activeWallet &&
      other.switchingWalletId == switchingWalletId &&
      other.operationFailure == operationFailure;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(wallets),
    activeWallet,
    switchingWalletId,
    operationFailure,
  );
}

const _unset = Object();
