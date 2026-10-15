import 'dart:convert';

import '../../../../core/config/app_environment.dart';
import '../../../../core/errors/errors.dart';
import '../../domain/models/models.dart';
import '../runtime/runtime.dart';
import '../storage/storage.dart';

enum _Phase { review, committing, acknowledged, confirmed, cancelled }

final class _Journal {
  _Journal(this.review, this.phase, this.baseline, [this.txid]);
  final RgbWalletSetupReview review;
  final _Phase phase;
  final List<String> baseline;
  final String? txid;

  String encode() => jsonEncode({
    'version': 1,
    'review': review.toJson(),
    'phase': phase.name,
    'baseline': baseline,
    'txid': txid,
  });

  factory _Journal.decode(String text) {
    try {
      if (text.length > 400000) throw const FormatException();
      final value = jsonDecode(text);
      if (value is! Map<String, Object?> ||
          value.length != 5 ||
          value.keys.toSet().difference({
            'version',
            'review',
            'phase',
            'baseline',
            'txid',
          }).isNotEmpty ||
          value['version'] != 1 ||
          value['review'] is! Map<String, Object?> ||
          value['baseline'] is! List ||
          value['phase'] is! String) {
        throw const FormatException();
      }
      final phase = _Phase.values.byName(value['phase']! as String);
      final baseline = List<String>.from(value['baseline']! as List);
      final txid = value['txid'];
      if (baseline.length > 5000 ||
          baseline.toSet().length != baseline.length ||
          baseline.any((id) => !RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) ||
          (txid != null &&
              (txid is! String ||
                  !RegExp(r'^[a-f0-9]{64}$').hasMatch(txid) ||
                  baseline.contains(txid))) ||
          ((phase == _Phase.review || phase == _Phase.cancelled) &&
              (baseline.isNotEmpty || txid != null)) ||
          (phase == _Phase.confirmed && txid == null)) {
        throw const FormatException();
      }
      return _Journal(
        RgbWalletSetupReview.fromJson(value['review']! as Map<String, Object?>),
        phase,
        baseline,
        txid as String?,
      );
    } catch (_) {
      throw const StoredDataCorruptionException();
    }
  }
}

/// Called only inside WalletRepository's shared command queue. The native
/// runtime remains exclusively leased through journal commit and dispatch.
final class WalletRgbSetupOperations {
  WalletRgbSetupOperations(
    this.runtime,
    this.profiles,
    this.services,
    this.store, {
    required this.newId,
    required this.clock,
  });

  final WalletRuntime runtime;
  final WalletProfilePersistence profiles;
  final WalletServiceConfiguration services;
  final RgbWalletSetupStore? store;
  final String Function() newId;
  final DateTime Function() clock;
  final _reviewOwners = <String, WalletRuntimeSnapshot>{};

  Future<AppResult<RgbWalletSetupReview>> prepare() => _owner((
    profile,
    engine,
    capability,
  ) async {
    final existing = await _read(profile);
    if (existing != null &&
        !_isUnsubmitted(existing) &&
        existing.phase != _Phase.confirmed) {
      throw const AppFailureException(rgbWalletSetupPendingFailure);
    }
    if (existing?.phase == _Phase.confirmed) {
      final resolved = await _observe(existing!, capability);
      if (resolved.phase != RgbWalletSetupPhase.ready &&
          resolved.phase != RgbWalletSetupPhase.required) {
        throw const AppFailureException(rgbWalletSetupPendingFailure);
      }
    }
    final inventory = await capability.rgbSetupInventory();
    if (inventory.freeAllocationCount > 0) {
      throw _failure(
        'rgb_wallet_setup_already_ready',
        'An RGB output is already available. Create a receive request instead.',
      );
    }
    final history = await _history(capability);
    if (history.any((item) => !item.confirmed)) {
      throw const AppFailureException(rgbWalletSetupPendingFailure);
    }
    _requireFunding(inventory);
    final rate = await engine.estimateFeeRate(6);
    if (rate.isStaleAt(clock())) {
      throw _failure(
        'rgb_wallet_setup_fee_stale',
        'The network fee rate is unavailable. Try preparing again.',
      );
    }
    final review = RgbWalletSetupReview(
      id: newId(),
      walletId: profile.id,
      network: profile.environment,
      runtimeFingerprint: inventory.runtimeFingerprint,
      nodePublicKey: inventory.nodePublicKey,
      feeRateSatPerVbyte: rate.satsPerVbyte,
      feeSource: rate.source,
      expiresAt: clock().toUtc().add(RgbWalletSetupReview.lifetime),
    );
    await _write(_Journal(review, _Phase.review, const []));
    _reviewOwners.clear();
    _reviewOwners[review.id] = runtime.snapshot;
    return review;
  });

  Future<AppResult<void>> cancel(RgbWalletSetupReview review) async {
    try {
      final journal = await _readId(review.walletId);
      if (journal == null || !_sameReview(journal.review, review)) {
        throw _failure(
          'rgb_wallet_setup_review_changed',
          'This review is no longer current.',
        );
      }
      if (journal.phase != _Phase.review && journal.phase != _Phase.cancelled) {
        throw const AppFailureException(rgbWalletSetupPendingFailure);
      }
      if (journal.phase == _Phase.review) {
        await _write(_Journal(journal.review, _Phase.cancelled, const []));
      }
      _reviewOwners.remove(review.id);
      return const AppResult.success(null);
    } catch (error, stack) {
      return AppResult.failure(FailureMapper.from(error, stack));
    }
  }

  Future<AppResult<RgbWalletSetupStatus>> confirm(
    RgbWalletSetupReview review,
  ) => _owner((profile, engine, capability) async {
    final journal = await _read(profile);
    if (journal == null ||
        journal.phase != _Phase.review ||
        !_sameReview(journal.review, review) ||
        review.walletId != profile.id ||
        !identical(_reviewOwners[review.id], runtime.snapshot) ||
        !clock().toUtc().isBefore(review.expiresAt)) {
      throw _failure(
        'rgb_wallet_setup_review_changed',
        'The wallet or review changed. Prepare again before confirming.',
      );
    }
    final inventory = await capability.rgbSetupInventory();
    _requireIdentity(journal, inventory);
    if (inventory.freeAllocationCount > 0) {
      throw _failure(
        'rgb_wallet_setup_already_ready',
        'An RGB output is already available.',
      );
    }
    _requireFunding(inventory);
    final history = await _history(capability);
    if (history.any((item) => !item.confirmed)) {
      throw const AppFailureException(rgbWalletSetupPendingFailure);
    }
    // IO can outlive the review. Recheck immediately before writing the marker.
    if (!identical(_reviewOwners[review.id], runtime.snapshot) ||
        !clock().toUtc().isBefore(review.expiresAt)) {
      throw _failure(
        'rgb_wallet_setup_review_changed',
        'The wallet or review changed. Prepare again before confirming.',
      );
    }
    final committing = _Journal(
      journal.review,
      _Phase.committing,
      history.map((tx) => tx.txid).toList(growable: false),
    );
    // The durable marker must succeed before entering native code. A failed
    // marker write also fails closed; a possibly committed marker is retained.
    await _write(committing);
    _reviewOwners.remove(review.id);
    // An expired marker is safely cancelled only while dispatch is known not
    // to have happened. A failed cancellation remains conservatively blocked.
    if (!clock().toUtc().isBefore(review.expiresAt)) {
      await _write(_Journal(journal.review, _Phase.cancelled, const []));
      throw _failure(
        'rgb_wallet_setup_review_changed',
        'The review expired. Prepare again before confirming.',
      );
    }
    try {
      await capability.createRgbSetupOutputs(journal.review.feeRateSatPerVbyte);
      final acknowledged = _Journal(
        journal.review,
        _Phase.acknowledged,
        committing.baseline,
      );
      await _write(acknowledged);
      return await _observe(acknowledged, capability);
    } catch (_) {
      // Includes a malformed/lost acknowledgement or a failed journal update.
      // Native may have broadcast: never clear the marker or repeat dispatch.
      return const RgbWalletSetupStatus(RgbWalletSetupPhase.indeterminate);
    }
  });

  Future<AppResult<RgbWalletSetupStatus>> status() =>
      _owner((profile, engine, capability) async {
        final journal = await _read(profile);
        if (journal != null && !_isUnsubmitted(journal)) {
          return _observe(journal, capability);
        }
        final inventory = await capability.rgbSetupInventory();
        return RgbWalletSetupStatus(
          inventory.freeAllocationCount > 0
              ? RgbWalletSetupPhase.ready
              : RgbWalletSetupPhase.required,
        );
      });

  /// Read-only gate immediately before other on-chain mutations, inside the
  /// repository queue. Reconciliation is explicit and never repeats creation.
  Future<AppResult<void>> assertResolved() async {
    if (store == null) return const AppResult.success(null);
    try {
      final result = await profiles.read();
      if (result case AppFailureResult<WalletRegistry>(:final failure)) {
        return AppResult.failure(failure);
      }
      final active = (result as AppSuccess<WalletRegistry>).value.activeProfile;
      if (active == null) return const AppResult.success(null);
      final journal = await _read(active);
      if (journal != null && !_isUnsubmitted(journal)) {
        final reconciliation = await status();
        if (reconciliation case AppFailureResult<RgbWalletSetupStatus>(
          :final failure,
        )) {
          return AppResult.failure(failure);
        }
        final phase =
            (reconciliation as AppSuccess<RgbWalletSetupStatus>).value.phase;
        if (phase != RgbWalletSetupPhase.ready &&
            phase != RgbWalletSetupPhase.required) {
          return const AppResult.failure(rgbWalletSetupPendingFailure);
        }
      }
      return const AppResult.success(null);
    } catch (error, stack) {
      return AppResult.failure(FailureMapper.from(error, stack));
    }
  }

  Future<RgbWalletSetupStatus> _observe(
    _Journal journal,
    RgbSetupWalletEngine engine,
  ) async {
    final inventory = await engine.rgbSetupInventory();
    _requireIdentity(journal, inventory);
    final history = await _history(engine);
    final ids = history.map((tx) => tx.txid).toSet();
    final baseline = journal.baseline.toSet();
    if (!baseline.every(ids.contains)) {
      await _retainUncertainty(journal);
      return RgbWalletSetupStatus(
        RgbWalletSetupPhase.indeterminate,
        transactionId: journal.txid,
      );
    }
    final candidates = history
        .where((tx) => !baseline.contains(tx.txid))
        .toList();
    RgbWalletSetupTransaction? matched;
    if (journal.txid != null) {
      matched = history.where((tx) => tx.txid == journal.txid).firstOrNull;
    } else if (candidates.length == 1) {
      matched = candidates.single;
    }
    if (matched == null || candidates.length != 1) {
      await _retainUncertainty(journal);
      return RgbWalletSetupStatus(
        RgbWalletSetupPhase.indeterminate,
        transactionId: journal.txid,
      );
    }
    final next = _Journal(
      journal.review,
      matched.confirmed ? _Phase.confirmed : _Phase.acknowledged,
      journal.baseline,
      matched.txid,
    );
    if (next.encode() != journal.encode()) await _write(next);
    return RgbWalletSetupStatus(
      matched.confirmed
          ? (inventory.freeAllocationCount > 0
                ? RgbWalletSetupPhase.ready
                : RgbWalletSetupPhase.required)
          : RgbWalletSetupPhase.pending,
      transactionId: matched.txid,
    );
  }

  Future<void> _retainUncertainty(_Journal journal) async {
    if (journal.phase == _Phase.confirmed) {
      await _write(
        _Journal(
          journal.review,
          _Phase.acknowledged,
          journal.baseline,
          journal.txid,
        ),
      );
    }
  }

  Future<List<RgbWalletSetupTransaction>> _history(
    RgbSetupWalletEngine engine,
  ) async {
    final history = await engine.rgbSetupTransactions();
    if (history.length > 5000 ||
        history.map((tx) => tx.txid).toSet().length != history.length) {
      throw const StoredDataCorruptionException();
    }
    return history;
  }

  Future<AppResult<T>> _owner<T>(
    Future<T> Function(WalletProfile, WalletEngine, RgbSetupWalletEngine)
    operation,
  ) async {
    try {
      if (store == null || services.usdtAsset == null) {
        throw _failure(
          'rgb_wallet_setup_unavailable',
          'RGB wallet preparation is not available for this deployment.',
        );
      }
      final result = await profiles.read();
      if (result case AppFailureResult<WalletRegistry>(:final failure)) {
        return AppResult.failure(failure);
      }
      final profile =
          (result as AppSuccess<WalletRegistry>).value.activeProfile;
      if (profile == null ||
          profile.environment != services.environment ||
          runtime.snapshot.walletId != profile.id ||
          runtime.snapshot.phase != WalletRuntimePhase.active) {
        throw _failure(
          'rgb_wallet_setup_wallet_changed',
          'Open the selected wallet before preparing RGB outputs.',
        );
      }
      return await runtime.run((engine) async {
        if (engine is! RgbSetupWalletEngine) {
          throw _failure(
            'rgb_wallet_setup_unsupported',
            'RGB wallet preparation is unavailable in this runtime.',
          );
        }
        return operation(profile, engine, engine as RgbSetupWalletEngine);
      });
    } catch (error, stack) {
      return AppResult.failure(FailureMapper.from(error, stack));
    }
  }

  Future<_Journal?> _read(WalletProfile profile) async {
    final journal = await _readId(profile.id);
    if (journal != null &&
        (journal.review.walletId != profile.id ||
            journal.review.network != profile.environment)) {
      throw const StoredDataCorruptionException();
    }
    return journal;
  }

  Future<_Journal?> _readId(String id) async {
    final text = await store!.read(id);
    return text == null ? null : _Journal.decode(text);
  }

  Future<void> _write(_Journal journal) =>
      store!.write(journal.review.walletId, journal.encode());
  static bool _isUnsubmitted(_Journal journal) =>
      journal.phase == _Phase.review || journal.phase == _Phase.cancelled;
  static bool _sameReview(RgbWalletSetupReview a, RgbWalletSetupReview b) =>
      jsonEncode(a.toJson()) == jsonEncode(b.toJson());
  static void _requireIdentity(
    _Journal journal,
    RgbWalletSetupInventory inventory,
  ) {
    if (journal.review.runtimeFingerprint != inventory.runtimeFingerprint ||
        journal.review.nodePublicKey != inventory.nodePublicKey) {
      throw const StoredDataCorruptionException();
    }
  }

  static void _requireFunding(RgbWalletSetupInventory inventory) {
    if (inventory.vanillaSpendableSats <=
        RgbWalletSetupReview.outputCount *
            RgbWalletSetupReview.outputValueSats) {
      throw _failure(
        'rgb_wallet_setup_insufficient_bitcoin',
        'Add spendable Bitcoin for up to four 20,000-sat outputs and the network fee.',
      );
    }
  }

  static AppFailureException _failure(String code, String message) =>
      AppFailureException(
        AppFailure(
          code: code,
          kind: AppFailureKind.conflict,
          userMessage: message,
          retryable: false,
        ),
      );
}
