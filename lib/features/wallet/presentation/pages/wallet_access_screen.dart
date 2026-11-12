import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../../shared/screens/screens.dart';
import '../models/models.dart';
import '../view_model/wallet_view_model.dart';
import 'wallet_unavailable_screen.dart';

/// Route-level wallet access gate shown only while session state is unresolved.
class WalletAccessScreen extends ConsumerStatefulWidget {
  const WalletAccessScreen({super.key});

  @override
  ConsumerState<WalletAccessScreen> createState() => _WalletAccessScreenState();
}

class _WalletAccessScreenState extends ConsumerState<WalletAccessScreen> {
  AppFailure? _retryingFailure;

  Future<void> _retry(AppFailure failure) async {
    if (_retryingFailure != null) return;
    setState(() => _retryingFailure = failure);
    try {
      await ref.read(walletViewModelProvider.notifier).reload();
    } finally {
      if (mounted) setState(() => _retryingFailure = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(walletViewModelProvider);
    final failure =
        _retryingFailure ??
        switch (state) {
          AsyncError<WalletState>(:final error, :final stackTrace) =>
            FailureMapper.from(error, stackTrace),
          _ => null,
        };
    if (failure == null) return const SplashScreen();
    return WalletUnavailableScreen(
      failure: failure,
      title: 'Wallet access unavailable',
      retrying: _retryingFailure != null,
      onRetry: () => unawaited(_retry(failure)),
    );
  }
}
