import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../wallet/presentation/view_model/view_models.dart';
import '../models/models.dart';

part 'scan_wallet_identity_provider.g.dart';

/// Projects the active wallet into the minimal non-secret Scan header shape.
@riverpod
Future<ScanWalletIdentity?> scanWalletIdentity(Ref ref) async {
  final wallet = await ref.watch(walletViewModelProvider.future);
  final active = wallet.activeWallet;
  if (active == null) return null;
  return ScanWalletIdentity(name: active.name, displayId: active.displayId);
}
