import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../wallet/presentation/view_model/view_models.dart';
import '../models/models.dart';

part 'scan_wallet_identity_view_model.g.dart';

/// Projects active-wallet state into the minimal non-secret Scan header shape.
@riverpod
class ScanWalletIdentityViewModel extends _$ScanWalletIdentityViewModel {
  @override
  Future<ScanWalletIdentity?> build() async {
    final wallet = await ref.watch(walletViewModelProvider.future);
    final active = wallet.activeWallet;
    if (active == null) return null;
    return ScanWalletIdentity(name: active.name, displayId: active.displayId);
  }

  /// Retries the durable wallet owner, which republishes this projection.
  Future<void> retry() => ref.read(walletViewModelProvider.notifier).reload();
}
