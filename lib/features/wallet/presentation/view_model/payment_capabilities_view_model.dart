import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../domain/models/models.dart';

part 'payment_capabilities_view_model.g.dart';

/// Loads the four stable product targets with deployment-owned availability.
@riverpod
Future<List<WalletPaymentCapability>> walletPaymentCapabilities(Ref ref) async {
  try {
    final repository = await ref.watch(walletRepositoryProvider.future);
    return repository.paymentCapabilities;
  } catch (error, stackTrace) {
    throw AppFailureException(FailureMapper.from(error, stackTrace));
  }
}
