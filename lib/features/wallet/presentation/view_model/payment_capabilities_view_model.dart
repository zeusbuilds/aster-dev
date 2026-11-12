import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../domain/models/models.dart';

part 'payment_capabilities_view_model.g.dart';

/// The four stable payment choices and their deployment-owned availability.
@riverpod
List<WalletPaymentCapability> walletPaymentCapabilities(Ref ref) =>
    WalletPaymentCapability.forServices(
      ref.watch(walletServiceConfigurationProvider),
    );
