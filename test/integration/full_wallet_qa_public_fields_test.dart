import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/full_wallet_qa.dart';

void main() {
  void validate(Object? fields) =>
      FullWalletQaControl.validatePublicFields(fields);
  final rejected = throwsA(
    isA<FullWalletQaFailure>().having(
      (error) => error.code,
      'code',
      'qa_private_field_rejected',
    ),
  );
  final maximum = ((BigInt.one << 256) - BigInt.one).toString();

  test(
    'accepts the real public mint acknowledgement and uint256 boundaries',
    () {
      for (final amount in ['0', '5000000', maximum]) {
        validate({
          'ok': true,
          'evm_token_balance': amount,
          'mint': {'tokenCommission': amount, 'amount': '5000000'},
          'receiverBalanceVerified': false,
        });
      }
    },
  );

  for (final value in <Object?>[
    '',
    '00',
    '01',
    '-1',
    '+1',
    '1.0',
    '1e6',
    '0x10',
    ' 1',
    '1 ',
    '1\n',
    'credential-text',
    (BigInt.one << 256).toString(),
    '1' * 79,
    1,
    1.0,
    true,
    null,
    {'amount': '1'},
  ]) {
    test(
      'rejects invalid public amount encoding ${value.runtimeType}: $value',
      () {
        expect(() => validate({'evm_token_balance': value}), rejected);
        expect(
          () => validate({
            'mint': {'tokenCommission': value},
          }),
          rejected,
        );
      },
    );
  }

  test('does not extend exceptions to other paths, lists or case variants', () {
    for (final fields in <Object?>[
      {'tokenCommission': '1'},
      {'mint.tokenCommission': '1'},
      {'EVM_TOKEN_BALANCE': '1'},
      {
        'mint': {'TokenCommission': '1'},
      },
      {
        'other': {'evm_token_balance': '1'},
      },
      {
        'other': {
          'mint': {'tokenCommission': '1'},
        },
      },
      [
        {'evm_token_balance': '1'},
      ],
      {
        'mint': [
          {'tokenCommission': '1'},
        ],
      },
    ]) {
      expect(() => validate(fields), rejected);
    }
  });

  test(
    'public amounts cannot permit credential siblings or nested secrets',
    () {
      for (final key in [
        'access_token',
        'refreshToken',
        'token',
        'password',
        'mnemonic',
        'seed',
        'private_key',
        'secret',
        'cookie',
      ]) {
        expect(
          () => validate({
            'evm_token_balance': '0',
            'mint': {'tokenCommission': '0', key: 'redacted-fixture'},
          }),
          rejected,
        );
      }
    },
  );
  test(
    'read-only coordination rejects financial requests before network I/O',
    () async {
      final control = FullWalletQaControl(
        runId: 'qa-read-only',
        controlUrl: 'http://127.0.0.1:29671',
        readOnly: true,
      );
      try {
        for (final name in [
          'fund_requested',
          'identity_requested',
          'bfa_mint_requested',
          'bfa_burn_requested',
          'btc_confirm_requested',
        ]) {
          final rejection = throwsA(
            isA<FullWalletQaFailure>().having(
              (error) => error.code,
              'code',
              'qa_read_only_financial_request_rejected',
            ),
          );
          await expectLater(control.event(name), rejection);
          await expectLater(control.request(name, const {}), rejection);
        }
      } finally {
        control.close();
      }
    },
  );
  test(
    'caller fields cannot replace event, ownership, timestamp or request ID',
    () async {
      final control = FullWalletQaControl(
        runId: 'qa-owned-fields',
        controlUrl: 'http://127.0.0.1:29671',
        readOnly: true,
      );
      try {
        for (final key in ['event', 'run_id', 'role', 'time_utc', 'id']) {
          final rejection = throwsA(
            isA<FullWalletQaFailure>().having(
              (error) => error.code,
              'code',
              'qa_reserved_field_rejected',
            ),
          );
          final fields = <String, Object?>{key: 'bfa_mint_requested'};
          await expectLater(control.event('test_started', fields), rejection);
          await expectLater(
            control.request('fixture_restore_requested', fields),
            rejection,
          );
        }
      } finally {
        control.close();
      }
    },
  );
}
