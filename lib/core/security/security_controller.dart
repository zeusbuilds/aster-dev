import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/errors.dart';
import 'device_authentication.dart';

enum SecurityPurpose {
  revealSeed,
  exportXpubs,
  exportBurnProof,
  changeAppLock,
  walletSetup,
  deleteWallet,
}

/// Process-local, single-use authority. Never persisted or carried in a route.
final class SensitiveAuthorization {
  SensitiveAuthorization._(
    this._owner,
    this._purpose,
    this._walletId,
    this._generation,
  );
  final SecurityController _owner;
  final SecurityPurpose _purpose;
  final String? _walletId;
  final int _generation;
  bool _used = false;
}

final securityControllerProvider = Provider<SecurityController>((ref) {
  final controller = SecurityController(PlatformDeviceAuthentication());
  ref.onDispose(controller.dispose);
  return controller;
});

/// Owns device authentication, app visibility and short-lived disclosure grants.
/// A missing credential is an explicit product policy; unknown capability never
/// grants access. Existing wallet encryption remains independent of screen lock.
class SecurityController extends ChangeNotifier {
  SecurityController(
    this._device, {
    Future<bool> Function(bool)? saveAppLock,
    bool appLockEnabled = true,
    // Keep the public configuration names independent of private storage.
    // ignore: prefer_initializing_formals
  }) : _saveAppLock = saveAppLock,
       // ignore: prefer_initializing_formals
       _appLockEnabled = appLockEnabled {
    _captureSubscription = _device.captureChanges.listen((captured) {
      _captured = captured;
      if (captured) {
        _generation++;
        _requestRevision++;
        if (_authenticating) {
          _obscured = _lifecycle != AppLifecycleState.resumed;
          unawaited(_device.cancel().catchError((Object _) {}));
        }
      }
      _notify();
    });
    if (_device case final DeviceAuthenticationBackgroundEvents events) {
      _backgroundSubscription = events.backgroundEvents.listen((_) {
        _obscured = true;
        lock();
      });
    }
  }

  final DeviceAuthentication _device;
  final Future<bool> Function(bool)? _saveAppLock;
  late final StreamSubscription<bool> _captureSubscription;
  StreamSubscription<void>? _backgroundSubscription;
  bool _appLockEnabled;
  bool _locked = false;
  bool _obscured = false;
  bool _captured = false;
  bool _authenticating = false;
  bool _unlockActionRequired = false;
  bool _hasWallet = false;
  bool _protectedSetup = false;
  bool _initialized = false;
  bool _disposed = false;
  bool _needsForegroundAuthentication = false;
  bool _savingLock = false;
  int _generation = 0;
  int _requestRevision = 0;
  int? _ownedPromptRevision;
  int _sensitiveLeases = 0;
  Future<void> _sensitiveTail = Future<void>.value();
  String? _walletId;
  String? _unlockError;
  DeviceSecurityStatus? _status;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  Completer<void>? _foreground;
  Completer<void>? _unlocked;

  bool get appLockEnabled => _appLockEnabled;
  bool get isLocked => _locked;
  bool get isAuthenticating => _authenticating;
  bool get isObscured => _obscured;
  bool get isCaptured => _captured;
  bool get initialized => _initialized;

  /// Automatic unlock keeps the launch frame quiet until user action is needed.
  bool get requiresUnlockAction => _unlockActionRequired;
  String? get unlockError => _unlockError;
  DeviceSecurityStatus? get deviceStatus => _status;
  int get generation => _generation;
  bool get sensitiveVisible =>
      _lifecycle == AppLifecycleState.resumed &&
      !_authenticating &&
      !_locked &&
      !_obscured &&
      !_captured;
  bool get canAccessWallet =>
      _initialized &&
      _lifecycle == AppLifecycleState.resumed &&
      !_locked &&
      !_obscured;

  bool get _ownsSystemPrompt =>
      _authenticating && _ownedPromptRevision == _requestRevision;

  void loadAppLockPreference(bool enabled) {
    if (_initialized) throw StateError('Security is already initialized');
    _appLockEnabled = enabled;
  }

  Future<void> initialize({required bool hasWallet}) async {
    _hasWallet = hasWallet;
    _unlockActionRequired = false;
    // Keep a failed capability check behind the lock, including first launch.
    _locked = true;
    try {
      await refreshStatus();
      _locked = _requiresAppLock;
    } catch (_) {
      _unlockError = 'Device authentication is unavailable. Try again.';
      _unlockActionRequired = true;
    }
    _initialized = true;
    _notify();
  }

  bool get _requiresAppLock =>
      _status == null ||
      (_status == DeviceSecurityStatus.secured &&
          _appLockEnabled &&
          (_hasWallet || _protectedSetup));

  Future<void> refreshStatus() async {
    final DeviceSecurityStatus status;
    try {
      status = await _device.status();
    } catch (_) {
      _status = null;
      _locked = true;
      _unlockActionRequired = true;
      _generation++;
      _notify();
      rethrow;
    }
    if (_disposed) return;
    _status = status;
    _captured = _device.isCaptured;
    if (status == DeviceSecurityStatus.unsecured) _finishUnlock();
    _notify();
  }

  /// Capability is not cached across backgrounding: the user may have added or
  /// removed device security in Settings. Keep the opaque cover throughout.
  Future<bool> prepareForeground() async {
    if (_disposed || _authenticating) return false;
    // The system sheet's own resume must not replay a cancelled/failed prompt.
    // A genuine background sets this flag and permits automatic unlock again.
    if (_unlockActionRequired && !_needsForegroundAuthentication) return false;
    _unlockActionRequired = false;
    _obscured = true;
    _notify();
    try {
      await refreshStatus();
      if (_disposed || _lifecycle != AppLifecycleState.resumed) return false;
      if (_needsForegroundAuthentication && _requiresAppLock) _locked = true;
      _obscured = false;
      _needsForegroundAuthentication = false;
      _notify();
      return _locked ? await unlock() : true;
    } catch (_) {
      if (!_disposed && _lifecycle == AppLifecycleState.resumed) {
        _obscured = false;
        _locked = true;
        _unlockError = 'Device authentication is unavailable. Try again.';
        _unlockActionRequired = true;
        _notify();
      }
      return false;
    }
  }

  /// Startup awaits this before constructing a native wallet owner.
  Future<void> waitForUnlock() async {
    if (!_locked) return;
    final pending = _unlocked ??= Completer<void>();
    await unlock();
    if (_locked) await pending.future;
  }

  Future<bool> unlock() async {
    if (_authenticating || _disposed) return false;
    final generation = _generation;
    _unlockActionRequired = false;
    _needsForegroundAuthentication = false;
    _unlockError = null;
    try {
      final result = await _authenticate('Unlock Aster');
      if (_disposed ||
          generation != _generation ||
          _lifecycle != AppLifecycleState.resumed ||
          _obscured) {
        return false;
      }
      if (!result) {
        _unlockActionRequired = _locked;
        _notify();
        return false;
      }
      _finishUnlock();
      _needsForegroundAuthentication = false;
      _notify();
      return true;
    } catch (_) {
      if (!_disposed) {
        _locked = true;
        _unlockError = 'Device authentication is unavailable. Try again.';
        _unlockActionRequired = true;
        _notify();
      }
      return false;
    }
  }

  Future<SensitiveAuthorization?> authorize(
    SecurityPurpose purpose, {
    String? walletId,
  }) async {
    if (_authenticating || _disposed || !canAccessWallet) return null;
    final currentWallet = _walletId;
    final generation = _generation;
    final success = await _authenticate(switch (purpose) {
      SecurityPurpose.revealSeed => 'Reveal your recovery phrase',
      SecurityPurpose.exportXpubs => 'Export your wallet public keys',
      SecurityPurpose.exportBurnProof => 'Export your USDT burn proof',
      SecurityPurpose.changeAppLock => 'Change Aster app lock',
      SecurityPurpose.walletSetup => 'Set up your wallet',
      SecurityPurpose.deleteWallet => 'Delete this wallet',
    });
    if (!success ||
        _disposed ||
        !canAccessWallet ||
        generation != _generation ||
        currentWallet != _walletId ||
        (walletId != null && walletId != _walletId)) {
      return null;
    }
    if (purpose == SecurityPurpose.walletSetup) _protectedSetup = true;
    return SensitiveAuthorization._(this, purpose, walletId, _generation);
  }

  bool consume(
    SensitiveAuthorization? grant,
    SecurityPurpose purpose, {
    String? walletId,
  }) {
    if (grant == null ||
        grant._used ||
        !identical(grant._owner, this) ||
        grant._purpose != purpose ||
        grant._walletId != walletId ||
        grant._generation != _generation ||
        !(purpose == SecurityPurpose.changeAppLock ||
                purpose == SecurityPurpose.deleteWallet
            ? canAccessWallet
            : sensitiveVisible) ||
        (walletId != null && _walletId != walletId)) {
      return false;
    }
    grant._used = true;
    return true;
  }

  Future<bool> _authenticate(String reason) async {
    final request = ++_requestRevision;
    var presentationFinished = false;
    Future<void> finishPresentation() async {
      if (presentationFinished || _ownedPromptRevision == null) return;
      presentationFinished = true;
      if (_device case final DeviceAuthenticationPresentation presentation) {
        try {
          await presentation.finishAuthenticationPresentation();
        } catch (_) {
          // A lost acknowledgement must not leave a native visual exemption
          // alive. Cancel also revokes completed presentation ownership.
          await _device.cancel().catchError((Object _) {});
          rethrow;
        }
      }
    }

    _authenticating = true;
    _notify();
    try {
      await refreshStatus();
      if (_disposed || request != _requestRevision) return false;
      // A capability RPC must not turn unrelated inactivity into ownership of
      // a system prompt, or start a prompt after the user has left the app.
      if (_lifecycle != AppLifecycleState.resumed || _obscured) return false;
      if (_status == DeviceSecurityStatus.unsecured) return true;
      _ownedPromptRevision = request;
      final result = await _device.authenticate(reason);
      if (_disposed || request != _requestRevision) {
        return false;
      }
      // A system credential activity may finish just before Flutter resumes.
      // No grant is issued while the application is still in the background.
      if (!await _authenticationForeground(request)) return false;
      if (result == DeviceAuthenticationResult.cancelled) {
        await finishPresentation();
        await _authenticationForeground(request);
        return false;
      }
      // Recheck removal/addition while the system sheet was open. Only the OS
      // can classify an unsecured device; a generic prompt error never can.
      await refreshStatus();
      // The credential sheet may deliver its result before Flutter observes
      // inactivity. That event can arrive during the status RPC above. Keep
      // ownership of the prompt until its final check is foreground again;
      // otherwise a successful authentication silently loses its grant.
      if (!await _authenticationForeground(request)) return false;
      await finishPresentation();
      if (!await _authenticationForeground(request)) return false;
      if (result == DeviceAuthenticationResult.unsecured &&
          _status != DeviceSecurityStatus.unsecured) {
        return false;
      }
      return true;
    } catch (_) {
      throw const AppFailureException(
        AppFailure(
          code: 'device_authentication_unavailable',
          kind: AppFailureKind.authentication,
          userMessage: 'Device authentication is unavailable. Try again.',
          retryable: true,
        ),
      );
    } finally {
      // Also release native ownership after cancellation, error and revocation.
      // Cleanup failure cannot turn any of those paths into authorization.
      if (!presentationFinished && _ownedPromptRevision != null) {
        await finishPresentation().catchError((Object _) {});
      }
      _ownedPromptRevision = null;
      _authenticating = false;
      // Cancellation, platform failure or a foreground timeout can finish
      // while the host is still inactive. The visual exemption ends with the
      // owned prompt; never leave a route exposed to an unrelated interruption.
      if (_lifecycle != AppLifecycleState.resumed) _obscured = true;
      _notify();
    }
  }

  Future<bool> _authenticationForeground(int request) async {
    if (_disposed || request != _requestRevision) return false;
    if (_lifecycle != AppLifecycleState.resumed) {
      final foreground = _foreground ??= Completer<void>();
      try {
        await foreground.future.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        return false;
      }
    }
    return !_disposed &&
        request == _requestRevision &&
        _lifecycle == AppLifecycleState.resumed &&
        !_obscured;
  }

  Future<bool> setAppLockEnabled(bool enabled) async {
    if (_savingLock) return false;
    if (enabled == _appLockEnabled) return true;
    _savingLock = true;
    final previous = _appLockEnabled;
    try {
      final grant = await authorize(SecurityPurpose.changeAppLock);
      if (!consume(grant, SecurityPurpose.changeAppLock)) return false;
      final generation = _generation;
      final walletId = _walletId;
      if (_saveAppLock != null && !await _saveAppLock(enabled)) {
        throw const AppFailureException(
          AppFailure(
            code: 'app_lock_save_failed',
            kind: AppFailureKind.storage,
            userMessage: 'App lock could not be saved. Try again.',
            retryable: true,
          ),
        );
      }
      if (_disposed ||
          generation != _generation ||
          walletId != _walletId ||
          !canAccessWallet) {
        // Restore the prior policy if authority expired during persistence.
        // A failed rollback is fail-closed in this process and reported.
        if (_saveAppLock != null && !await _saveAppLock(previous)) {
          throw const AppFailureException(
            AppFailure(
              code: 'app_lock_save_failed',
              kind: AppFailureKind.storage,
              userMessage: 'App lock could not be saved. Try again.',
              retryable: true,
            ),
          );
        }
        return false;
      }
      _appLockEnabled = enabled;
      _notify();
      return true;
    } finally {
      _savingLock = false;
    }
  }

  void updateWallet(String? walletId) {
    if (_walletId == walletId) return;
    _walletId = walletId;
    _hasWallet = walletId != null || _hasWallet;
    _generation++;
    if (_authenticating) {
      _requestRevision++;
      if (_lifecycle != AppLifecycleState.resumed) _obscured = true;
      unawaited(_device.cancel().catchError((Object _) {}));
    }
    _notify();
  }

  /// Called only after durable deletion commits an empty wallet registry.
  /// A transient `updateWallet(null)` during loading must not clear this policy.
  /// The user's app-lock preference survives, so a later wallet is protected.
  void clearWalletPresence() {
    if (_disposed) return;
    _walletId = null;
    _hasWallet = false;
    _protectedSetup = false;
    _generation++;
    _requestRevision++;
    _needsForegroundAuthentication = false;
    if (_authenticating) {
      unawaited(_device.cancel().catchError((Object _) {}));
    }
    // Capability errors remain fail-closed even with no wallet. Known device
    // security no longer requires an app unlock before returning to Welcome.
    if (_requiresAppLock) {
      _locked = true;
      _unlockActionRequired = true;
    } else {
      _finishUnlock();
    }
    _notify();
  }

  void lock() {
    _needsForegroundAuthentication = true;
    _generation++;
    _requestRevision++;
    _locked = _requiresAppLock;
    _unlockActionRequired = _locked;
    _unlockError = null;
    if (_authenticating) unawaited(_device.cancel().catchError((Object _) {}));
    _notify();
  }

  /// Keep the source route painted beneath our own OS prompt, while authority
  /// remains foreground-only. Native background events override this exemption
  /// immediately. Older Android credential activities pause the host as part
  /// of authentication, so only bridges with authoritative background events
  /// may retain the route through hidden/paused states.
  void handleLifecycle(AppLifecycleState state) {
    _lifecycle = state;
    final stopped =
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached;
    final ownedInterruption =
        _ownsSystemPrompt &&
        state != AppLifecycleState.detached &&
        (!stopped || _device is DeviceAuthenticationBackgroundEvents);
    _obscured = state != AppLifecycleState.resumed && !ownedInterruption;
    if (stopped && !ownedInterruption) {
      _generation++;
      _requestRevision++;
      _needsForegroundAuthentication = true;
      _locked = _requiresAppLock;
      if (_authenticating) {
        unawaited(_device.cancel().catchError((Object _) {}));
      }
      // Before the root app mounts, startup owns only a manual resume path.
      // Retain that fallback behind the opaque cover. The mounted app clears
      // it in prepareForeground before its automatic prompt is painted.
      _unlockActionRequired = _locked;
    }
    if (state == AppLifecycleState.resumed) {
      _foreground?.complete();
      _foreground = null;
    }
    _notify();
  }

  Future<void> setSensitive(bool sensitive) {
    _sensitiveLeases = sensitive
        ? _sensitiveLeases + 1
        : (_sensitiveLeases - 1).clamp(0, 1000);
    final protected = _sensitiveLeases > 0;
    final next = _sensitiveTail.then((_) => _device.setSensitive(protected));
    _sensitiveTail = next.catchError((Object _) {});
    return next;
  }

  void _finishUnlock() {
    _locked = false;
    _unlockActionRequired = false;
    _unlockError = null;
    _unlocked?.complete();
    _unlocked = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _requestRevision++;
    unawaited(_captureSubscription.cancel());
    unawaited(_backgroundSubscription?.cancel());
    unawaited(_device.cancel().catchError((Object _) {}));
    super.dispose();
  }
}
