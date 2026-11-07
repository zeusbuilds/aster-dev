import 'package:aster/core/core.dart';
import 'package:aster/features/send/presentation/view_model/rgb_send_preparation.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late bool owner;
  late RgbWalletSetupPhase phase;
  late List<String> calls;
  late Future<bool> Function(RgbWalletSetupReview) confirmation;
  late Future<AppResult<RgbWalletSetupStatus>> Function(RgbWalletSetupReview)
  dispatch;
  late RgbWalletSetupReview review;
  AppFailure? reviewFailure;

  Future<RgbSendPreparationResult> run({
    WalletBackend backend = WalletBackend.rgbL1,
    WalletPaymentTarget target = WalletPaymentTarget.usdtOnchain,
  }) => prepareRgbSend(
    backend: backend,
    target: target,
    walletId: '1' * 32,
    isCurrent: () => owner,
    clock: () => now,
    status: () async {
      calls.add('status');
      return AppResult.success(RgbWalletSetupStatus(phase));
    },
    review: () async {
      calls.add('review');
      if (reviewFailure case final failure?) return AppResult.failure(failure);
      return AppResult.success(review);
    },
    cancel: (_) async {
      calls.add('cancel');
      return const AppResult.success(null);
    },
    prepare: (review) async {
      calls.add('prepare');
      return dispatch(review);
    },
    confirm: (review) async {
      calls.add('dialog');
      return confirmation(review);
    },
  );

  setUp(() {
    now = DateTime.utc(2026, 11, 7);
    owner = true;
    phase = RgbWalletSetupPhase.required;
    calls = [];
    reviewFailure = null;
    review = RgbWalletSetupReview(
      id: '2' * 32,
      walletId: '1' * 32,
      network: BlockchainEnvironment.regtest,
      runtimeFingerprint: '3' * 64,
      nodePublicKey: '4' * 64,
      identityKind: RgbSetupIdentityKind.nativeWallet,
      feeRateSatPerVbyte: 1,
      expiresAt: now.add(const Duration(minutes: 2)),
    );
    confirmation = (_) async => true;
    dispatch = (_) async {
      phase = RgbWalletSetupPhase.pending;
      return AppResult.success(RgbWalletSetupStatus(phase));
    };
  });

  test('RLN and Bitcoin Send never enter RGB preparation', () async {
    expect(
      await run(backend: WalletBackend.rln),
      RgbSendPreparationResult.ready,
    );
    expect(
      await run(target: WalletPaymentTarget.bitcoinOnchain),
      RgbSendPreparationResult.ready,
    );
    expect(calls, isEmpty);
  });
  test(
    'ready inventory proceeds without a dialog or monetary preparation',
    () async {
      phase = RgbWalletSetupPhase.ready;
      expect(await run(), RgbSendPreparationResult.ready);
      expect(calls, ['status']);
    },
  );
  test('Cancel only cancels the review and never prepares outputs', () async {
    confirmation = (_) async => false;
    expect(await run(), RgbSendPreparationResult.cancelled);
    expect(calls, ['status', 'review', 'dialog', 'cancel']);
  });
  for (final outcomeUnknown in [false, true]) {
    test(
      'blocked prerequisites preserve the complete original failure ($outcomeUnknown)',
      () async {
        reviewFailure = AppFailure(
          code: 'rgb_wallet_setup_insufficient_bitcoin',
          kind: AppFailureKind.storage,
          userMessage: 'Reconciliation is required.',
          retryable: false,
          requiresReconciliation: true,
          outcomeUnknown: outcomeUnknown,
        );
        await expectLater(
          run(),
          throwsA(
            isA<AppFailureException>().having(
              (error) => identical(error.failure, reviewFailure),
              'original protected failure',
              isTrue,
            ),
          ),
        );
        expect(calls, ['status', 'review']);
      },
    );
  }
  test(
    'explicit Prepare dispatches once and never continues to payment',
    () async {
      dispatch = (_) async {
        phase = RgbWalletSetupPhase.ready;
        return AppResult.success(RgbWalletSetupStatus(phase));
      };
      expect(await run(), RgbSendPreparationResult.prepared);
      expect(calls, ['status', 'review', 'dialog', 'prepare']);
      calls.clear();
      expect(await run(), RgbSendPreparationResult.ready);
      expect(calls, ['status']);
    },
  );
  for (final state in [
    RgbWalletSetupPhase.pending,
    RgbWalletSetupPhase.indeterminate,
  ]) {
    test(
      '$state remains read-only across repeated/restarted Send actions',
      () async {
        dispatch = (_) async {
          phase = state;
          return AppResult.success(RgbWalletSetupStatus(phase));
        };
        await run();
        expect(calls.where((call) => call == 'prepare'), hasLength(1));
        calls.clear();
        final expected = state == RgbWalletSetupPhase.pending
            ? RgbSendPreparationResult.pending
            : RgbSendPreparationResult.uncertain;
        expect(await run(), expected);
        expect(await run(), expected);
        expect(calls, ['status', 'status']);
      },
    );
  }
  test('wallet switch while dialog is open prevents preparation', () async {
    confirmation = (_) async {
      owner = false;
      return true;
    };
    await expectLater(run(), throwsA(isA<AppFailureException>()));
    expect(calls, ['status', 'review', 'dialog']);
  });
  test('expired review after confirmation never dispatches', () async {
    confirmation = (_) async {
      now = now.add(const Duration(minutes: 3));
      return true;
    };
    await expectLater(run(), throwsA(isA<AppFailureException>()));
    expect(calls, ['status', 'review', 'dialog']);
  });
  test('expired review cannot open a confirmation dialog', () async {
    now = now.add(const Duration(minutes: 3));
    await expectLater(run(), throwsA(isA<AppFailureException>()));
    expect(calls, ['status', 'review']);
  });
  test(
    'funding prerequisites allow a later explicit check without dispatch',
    () async {
      reviewFailure = const AppFailure(
        code: 'rgb_wallet_setup_insufficient_bitcoin',
        kind: AppFailureKind.conflict,
        userMessage: 'Old setup wording',
        retryable: false,
      );
      await expectLater(
        run(),
        throwsA(
          isA<AppFailureException>().having(
            (error) => error.failure.retryable,
            'explicit retry',
            isTrue,
          ),
        ),
      );
      expect(calls, ['status', 'review']);
    },
  );
}
