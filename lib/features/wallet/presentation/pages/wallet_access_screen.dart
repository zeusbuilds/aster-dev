import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../../shared/screens/screens.dart';
import '../models/models.dart';
import '../view_model/wallet_view_model.dart';
import 'wallet_unavailable_screen.dart';

/// Route-level wallet access gate shown only while session state is unresolved.
class WalletAccessScreen extends ConsumerWidget {
  const WalletAccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(walletViewModelProvider);
    return switch (state) {
      AsyncError<WalletState>(:final error, :final stackTrace) =>
        WalletUnavailableScreen(
          failure: FailureMapper.from(error, stackTrace),
          title: 'Wallet access unavailable',
          retrying: false,
          canResumeCommittedDeletion: WalletViewModel.canResumeDeletion(
            FailureMapper.from(error, stackTrace),
          ),
          onRetry: () => ref.read(walletViewModelProvider.notifier).reload(),
        ),
      _ => const SplashScreen(),
    };
  }
}
