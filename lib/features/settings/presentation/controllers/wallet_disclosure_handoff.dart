import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/view_model/view_models.dart';
import '../view_model/view_models.dart';

final walletDisclosureHandoffProvider = Provider<WalletDisclosureHandoff>((
  ref,
) {
  final handoff = WalletDisclosureHandoff(ref);
  ref.listen(walletViewModelProvider, (_, _) => handoff.checkWallet());
  ref.onDispose(handoff.dispose);
  return handoff;
});

/// One process-local handoff, never serialized into URLs, route arguments,
/// restoration state or logs. Authentication and data preparation belong to
/// the source screen; the destination can only claim a ready disclosure once.
final class WalletDisclosureHandoff {
  WalletDisclosureHandoff(this._ref);

  final Ref _ref;
  WalletDisclosureSession? _session;
  bool _preparing = false;
  bool _disposed = false;

  bool _walletCurrent(String walletId) {
    if (_disposed) return false;
    final state = _ref.read(walletViewModelProvider);
    return !state.isLoading &&
        !state.hasError &&
        state.value?.isChangingWallet != true &&
        state.value?.activeWallet?.id == walletId &&
        state.value?.activeWallet?.state == WalletProfileState.ready;
  }

  Future<WalletDisclosureSession?> prepare(
    SecurityPurpose purpose, {
    required bool Function() sourceCurrent,
  }) async {
    if (_preparing || _disposed) return null;
    if (purpose != SecurityPurpose.revealSeed &&
        purpose != SecurityPurpose.exportXpubs) {
      throw ArgumentError.value(purpose, 'purpose');
    }
    _preparing = true;
    _session?.close();
    _session = null;
    final security = _ref.read(securityControllerProvider);
    var lease = false;
    try {
      if (!sourceCurrent() || !security.canAccessWallet) return null;
      if (_ref.read(walletViewModelProvider).isLoading) {
        await _ref.read(walletViewModelProvider.future);
      }
      if (!sourceCurrent() || !security.canAccessWallet) return null;
      final wallet = _ref.read(walletViewModelProvider).value?.activeWallet;
      if (wallet == null || !_walletCurrent(wallet.id)) {
        throw const AppFailureException(
          AppFailure(
            code: 'wallet_disclosure_wallet_unavailable',
            kind: AppFailureKind.unavailable,
            userMessage: 'This wallet is unavailable. Try again.',
            retryable: true,
          ),
        );
      }
      if (security.isCaptured) throw const AppFailureException(_captureFailure);
      lease = true;
      await security.setSensitive(true);
      if (!sourceCurrent() || !_walletCurrent(wallet.id)) return null;
      if (security.isCaptured) throw const AppFailureException(_captureFailure);
      final grant = await security.authorize(purpose, walletId: wallet.id);
      if (grant == null || !sourceCurrent() || !_walletCurrent(wallet.id)) {
        return null;
      }
      final generation = security.generation;
      bool current() =>
          !_disposed &&
          sourceCurrent() &&
          _walletCurrent(wallet.id) &&
          security.sensitiveVisible &&
          security.generation == generation;
      if (!current()) return null;
      final disclosure = _ref.read(walletDisclosureViewModelProvider);
      String? mnemonic;
      WalletPublicKeys? keys;
      if (purpose == SecurityPurpose.revealSeed) {
        final result = await disclosure.recoveryMnemonic(
          walletId: wallet.id,
          authorization: grant,
          current: current,
        );
        if (!current()) return null;
        switch (result) {
          case AppSuccess<String>(:final value):
            if (value.trim().split(RegExp(r'\s+')).length != 12) {
              throw const AppFailureException(
                AppFailure(
                  code: 'wallet_disclosure_phrase_invalid',
                  kind: AppFailureKind.storage,
                  userMessage: 'The seed phrase could not be opened safely.',
                  retryable: false,
                ),
              );
            }
            mnemonic = value;
          case AppFailureResult<String>(:final failure):
            throw AppFailureException(failure);
        }
      } else {
        final result = await disclosure.publicKeys(
          walletId: wallet.id,
          authorization: grant,
          current: current,
        );
        if (!current()) return null;
        switch (result) {
          case AppSuccess<WalletPublicKeys>(:final value):
            keys = value;
          case AppFailureResult<WalletPublicKeys>(:final failure):
            throw AppFailureException(failure);
        }
      }
      final session = WalletDisclosureSession._(
        security,
        wallet.id,
        generation,
        purpose,
        _walletCurrent,
        mnemonic,
        keys,
      );
      _session = session;
      lease = false; // The ready session now owns the native protection lease.
      return session;
    } finally {
      _preparing = false;
      if (lease) await security.setSensitive(false);
    }
  }

  WalletDisclosureSession? claim(SecurityPurpose purpose) {
    final session = _session;
    if (session == null || !session.claim(purpose)) return null;
    return session;
  }

  bool allows(SecurityPurpose purpose) =>
      _session?.purpose == purpose && _session?.valid == true;

  void discard(WalletDisclosureSession session) {
    session.close();
    if (identical(_session, session)) _session = null;
  }

  void checkWallet() {
    final session = _session;
    if (session != null && !_walletCurrent(session.walletId)) session.close();
  }

  void dispose() {
    _disposed = true;
    _session?.close();
    _session = null;
  }

  static const _captureFailure = AppFailure(
    code: 'wallet_disclosure_capture_active',
    kind: AppFailureKind.unavailable,
    userMessage: 'Stop screen sharing to view wallet information.',
    retryable: true,
  );
}

/// Holds only the material already read with a consumed, purpose-bound grant.
/// Any loss of authority clears it synchronously, including before route paint.
final class WalletDisclosureSession extends ChangeNotifier {
  WalletDisclosureSession._(
    this._security,
    this.walletId,
    this._generation,
    this.purpose,
    this._walletCurrent,
    this._mnemonic,
    this._keys,
  ) {
    _security.addListener(_securityChanged);
  }

  final SecurityController _security;
  final String walletId;
  final int _generation;
  final SecurityPurpose purpose;
  final bool Function(String) _walletCurrent;
  String? _mnemonic;
  WalletPublicKeys? _keys;
  bool _claimed = false;
  bool _closed = false;

  bool get valid =>
      !_closed &&
      _security.sensitiveVisible &&
      _security.generation == _generation &&
      _walletCurrent(walletId);
  String? get mnemonic => valid ? _mnemonic : null;
  WalletPublicKeys? get keys => valid ? _keys : null;

  bool claim(SecurityPurpose expected) {
    if (_claimed || expected != purpose || !valid) return false;
    _claimed = true;
    return true;
  }

  void _securityChanged() {
    if (!valid) close();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _mnemonic = null;
    _keys = null;
    _security.removeListener(_securityChanged);
    notifyListeners();
    unawaited(_releaseProtection().catchError((Object _) {}));
  }

  Future<void> _releaseProtection() async {
    if (_claimed) {
      // Clearing Dart fields does not erase the previously painted seed/key
      // frame. Keep the native capture cover / FLAG_SECURE until the framework
      // has submitted the invalidated frame (or removed this destination).
      // While backgrounded, frames may be suspended: protection must remain
      // enabled until a safe frame is produced, with no timer-based bypass.
      await WidgetsBinding.instance.endOfFrame;
    }
    await _security.setSensitive(false);
  }
}
