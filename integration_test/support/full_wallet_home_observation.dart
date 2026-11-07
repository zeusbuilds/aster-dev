import 'package:aster/features/home/presentation/view_model/view_models.dart';
import 'package:aster/features/home/presentation/widgets/widgets.dart';
import 'package:aster/features/wallet/domain/models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'full_wallet_qa.dart';

/// Waits for normal Home owners; never invokes refresh/invalidation or an SDK
/// operation to force the UI. The caller has already proved an intact, complete
/// retained checkpoint before mounting the real app.
Future<void> qualifyCompletedHomeObservation({
  required WidgetTester tester,
  required ProviderContainer container,
  required FullWalletQaControl control,
  required Map<String, Object?> checkpoint,
}) async {
  final expected = checkpoint['snapshot']! as Map<String, Object?>;
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(deadline)) {
    final home = container.read(homeViewModelProvider).value;
    if (home != null && !home.refreshing && home.refreshFailure == null) {
      final portfolio = home.portfolio;
      final bitcoin = portfolio.bitcoin;
      final usdt = portfolio.usdt;
      final rows = tester.widgetList<AssetRow>(find.byType(AssetRow)).toList();
      final btc = rows.where((row) => row.kind == WalletAssetKind.bitcoin);
      final rgb = rows.where((row) => row.kind == WalletAssetKind.usdt);
      if (bitcoin.onchainSettled.units == expected['btc_settled_sats'] &&
          bitcoin.onchainFuture.units == expected['btc_future_sats'] &&
          bitcoin.onchainSpendable.units == expected['btc_spendable_sats'] &&
          usdt?.onchainSettled.units == 50 &&
          usdt?.onchainFuture.units == 50 &&
          usdt?.onchainSpendable.units == 50 &&
          btc.length == 1 &&
          rgb.length == 1 &&
          !btc.single.loading &&
          !rgb.single.loading &&
          btc.single.balancesVisible &&
          rgb.single.balancesVisible &&
          btc.single.totalText == '0.00098305 BTC' &&
          rgb.single.totalText == '0.00005 USDT') {
        await tester.pump(const Duration(milliseconds: 250));
        await control.event('funded_home_presentation_observed', {
          'recovery_cohort': checkpoint['recovery_cohort'],
          'public_identity': expected['public_identity'],
          'btc_settled_sats': bitcoin.onchainSettled.units,
          'btc_spendable_sats': bitcoin.onchainSpendable.units,
          'bfa_settled_units': usdt!.onchainSettled.units,
          'bfa_spendable_units': usdt.onchainSpendable.units,
          'bitcoin_rendered': btc.single.totalText,
          'usdt_rendered': rgb.single.totalText,
          'home_refreshing': false,
          'home_refresh_failure': false,
          'ordinary_home_refresh_allowed': true,
          'manual_home_refresh': false,
          'new_payment_commands': false,
        });
        // A deliberate public-only evidence pause gives the host time to
        // capture the actual painted rows before this run disposes its owner.
        await control.request('home_presentation_capture_requested', {
          'public_identity': expected['public_identity'],
          'bitcoin_rendered': btc.single.totalText,
          'usdt_rendered': rgb.single.totalText,
        });
        return;
      }
    }
    await tester.pump(const Duration(milliseconds: 250));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
  }
  throw const FullWalletQaFailure('qa_home_presentation_not_current');
}
