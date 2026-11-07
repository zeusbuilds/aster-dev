import 'dart:async';

import 'package:aster/core/core.dart';
import 'package:aster/features/scan/data/services/scan_payment_validator.dart';
import 'package:aster/features/scan/data/services/scan_session.dart';
import 'package:aster/features/scan/domain/models/models.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scan_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 10, 27);
  const bitcoin = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
  ScanPayload payload(String value) =>
      ScanPayload.parse(value, source: ScanCaptureSource.camera);
  WalletPaymentPreview rgb({DateTime? expiry}) => WalletPaymentPreview(
    route: PaymentRoute(
      asset: WalletAsset.rgbUsdt(assetId: 'rgb:configured', precision: 6),
      rail: PaymentRail.onchain,
    ),
    encodedDestination: 'rgb:invoice',
    displayDestination: 'rgb:invoice',
    expiresAt: expiry,
  );

  test(
    'recognizes checksum-valid Bitcoin locally for this network only',
    () async {
      var nativeCalls = 0;
      final validator = ScanPaymentValidator(
        environment: BlockchainEnvironment.mainnet,
        now: () => now,
        previewRgb: (_) async {
          nativeCalls++;
          return AppResult.success(rgb());
        },
      );
      expect(await validator.accepts(payload(bitcoin)), isTrue);
      expect(
        await validator.accepts(payload('bitcoin:$bitcoin?amount=0.1')),
        isTrue,
      );
      for (final value in [
        'hello',
        'https://example.com',
        'lightning:lnbc...',
        'lnbc...',
        'bitcoin:invalid',
        '${bitcoin.substring(0, bitcoin.length - 1)}q',
        'tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0gdcccefvpysxf3q0sl5k7',
      ]) {
        expect(await validator.accepts(payload(value)), isFalse, reason: value);
      }
      expect(nativeCalls, 0);
    },
  );

  test('RGB requires an authoritative usable unexpired USDT preview', () async {
    AppResult<WalletPaymentPreview> result = AppResult.success(rgb());
    final validator = ScanPaymentValidator(
      environment: BlockchainEnvironment.mainnet,
      now: () => now,
      previewRgb: (_) async => result,
    );
    expect(await validator.accepts(payload('rgb:invoice')), isTrue);
    result = AppResult.success(rgb(expiry: now));
    expect(await validator.accepts(payload('rgb:invoice')), isFalse);
    result = const AppResult.failure(
      AppFailure(
        code: 'invoice_network_or_asset_mismatch',
        kind: AppFailureKind.validation,
        userMessage: 'Not valid here.',
        retryable: false,
      ),
    );
    expect(await validator.accepts(payload('rgb:invoice')), isFalse);
    result = AppResult.success(
      WalletPaymentPreview(
        route: const PaymentRoute(
          asset: WalletAsset.bitcoin,
          rail: PaymentRail.lightning,
        ),
        encodedDestination: 'rgb:invalid',
        displayDestination: 'rgb:invalid',
      ),
    );
    expect(await validator.accepts(payload('rgb:invoice')), isFalse);
  });

  test(
    'one pending RGB read cannot queue repeated native work; BTC stays usable',
    () async {
      final gate = Completer<AppResult<WalletPaymentPreview>>();
      var nativeCalls = 0;
      final validator = ScanPaymentValidator(
        environment: BlockchainEnvironment.mainnet,
        now: () => now,
        previewRgb: (_) {
          nativeCalls++;
          return gate.future;
        },
      );
      final pending = validator.accepts(payload('rgb:pending'));
      for (var frame = 0; frame < 30; frame++) {
        expect(await validator.accepts(payload('rgb:pending')), isFalse);
        expect(await validator.accepts(payload('rgb:other')), isFalse);
      }
      expect(await validator.accepts(payload(bitcoin)), isTrue);
      expect(nativeCalls, 1);
      gate.complete(AppResult.success(rgb()));
      expect(await pending, isTrue);
      expect(await validator.accepts(payload('rgb:recovered')), isTrue);
      expect(nativeCalls, 2);
    },
  );
  testWidgets('camera timeout leaves only one native RGB read pending', (
    tester,
  ) async {
    final gate = Completer<AppResult<WalletPaymentPreview>>();
    var nativeCalls = 0;
    final validator = ScanPaymentValidator(
      environment: BlockchainEnvironment.mainnet,
      now: () => now,
      previewRgb: (_) {
        nativeCalls++;
        return gate.future;
      },
    );
    final driver = FakeScanCameraDriver();
    final session = ManagedScanSession(
      driver,
      FakeScanGallerySource(),
      validatePayload: validator.accepts,
    );
    final captures = <ScanPayload>[];
    await tester.pumpWidget(
      MaterialApp(
        home: session.buildCameraSurface(
          scanWindow: const Rect.fromLTWH(0, 0, 100, 100),
          placeholderColor: Colors.black,
          onCaptured: captures.add,
        ),
      ),
    );
    await tester.pump();
    driver.emit(['rgb:slow']);
    await tester.pump(const Duration(seconds: 6));
    for (var frame = 0; frame < 10; frame++) {
      driver.emit(['rgb:other$frame']);
      await tester.idle();
    }
    expect(nativeCalls, 1);
    expect(captures, isEmpty);
    expect(session.snapshot.captureLocked, isFalse);
    expect(session.snapshot.failure, isNull);
    gate.complete(AppResult.success(rgb()));
    await tester.idle();
    // The old timed-out result must never navigate after it eventually returns.
    expect(captures, isEmpty);
    driver.emit(['rgb:fresh']);
    await tester.idle();
    expect(nativeCalls, 2);
    expect(captures.map((value) => value.value), ['rgb:fresh']);
    await tester.pumpWidget(const SizedBox.shrink());
    await session.close();
  });
}
