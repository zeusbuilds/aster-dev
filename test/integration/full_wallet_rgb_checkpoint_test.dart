import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/full_wallet_qa.dart';
import '../../integration_test/support/full_wallet_rgb_checkpoint.dart';

void main() {
  const run = 'owned-funded-run';
  Map<String, Object?> valid() => {
    'version': 1,
    'complete': true,
    'storage_run_id': run,
    'wallet_id': '1' * 32,
    'asset_id': 'rgb:qualification',
    'recovery_cohort': '2' * 32,
    'pending_fence': false,
    'snapshot': {
      'public_identity': '3' * 64,
      'identity_kind': 'native-wallet',
      'btc_settled_sats': 90000,
      'btc_spendable_sats': 89000,
      'btc_future_sats': 90000,
      'bfa_settled_units': 50,
      'bfa_spendable_units': 50,
      'bfa_future_units': 50,
    },
    'sent': [
      {
        'asset': 'bitcoin',
        'txid': '4' * 64,
        'gross_units': 1000,
        'status': 'succeeded',
      },
      {
        'asset': 'usdt',
        'txid': '5' * 64,
        'gross_units': 50,
        'status': 'succeeded',
      },
    ],
  };

  test('completed checkpoint retains only exact public confirmed outcomes', () {
    final value = valid();
    expect(validateQaFundedCheckpoint(value, run), same(value));
  });
  final mutations = <String, void Function(Map<String, Object?>)>{
    'wrong run': (v) => v['storage_run_id'] = 'other-run',
    'incomplete': (v) => v['complete'] = false,
    'pending fence': (v) => v['pending_fence'] = true,
    'invalid cohort': (v) => v['recovery_cohort'] = 'short',
    'extra authority': (v) => v['send_allowed'] = true,
    'wrong remaining amount': (v) =>
        (v['snapshot'] as Map)['bfa_spendable_units'] = 100,
    'wrong gross amount': (v) =>
        ((v['sent'] as List)[1] as Map)['gross_units'] = 100,
    'unconfirmed': (v) => ((v['sent'] as List)[1] as Map)['status'] = 'pending',
    'invalid transaction identity': (v) =>
        ((v['sent'] as List)[1] as Map)['txid'] = '',
    'duplicate asset': (v) =>
        ((v['sent'] as List)[1] as Map)['asset'] = 'bitcoin',
  };
  for (final mutation in mutations.entries) {
    test('checkpoint rejects ${mutation.key} without a fresh fallback', () {
      final value = jsonDecode(jsonEncode(valid())) as Map<String, Object?>;
      mutation.value(value);
      expect(
        () => validateQaFundedCheckpoint(value, run),
        throwsA(isA<FullWalletQaFailure>()),
      );
    });
  }
  test(
    'read-only controller refuses every financial request before dispatch',
    () async {
      var dispatches = 0;
      final control = FullWalletQaControl(
        runId: run,
        controlUrl: 'http://127.0.0.1:29671',
        readOnly: true,
        initialSequence: 1000,
        beforeFinancialDispatch: () => dispatches += 1,
      );
      addTearDown(control.close);
      for (final event in [
        'fund_requested',
        'rgb_witness_funding_requested',
        'rgb_setup_confirm_requested',
        'btc_confirm_requested',
        'bfa_mint_requested',
        'bfa_burn_requested',
      ]) {
        await expectLater(
          control.request(event, const {}),
          throwsA(
            isA<FullWalletQaFailure>().having(
              (e) => e.code,
              'code',
              'qa_read_only_financial_request_rejected',
            ),
          ),
        );
      }
      expect(dispatches, 0);
    },
  );
}
