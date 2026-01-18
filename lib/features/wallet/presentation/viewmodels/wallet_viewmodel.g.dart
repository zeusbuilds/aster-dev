// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wallet_viewmodel.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$walletViewModelHash() => r'78c36e1bde85390801a172b67a7b8579e428bccc';

/// ViewModel for managing wallet state and operations
/// Handles loading wallets, switching active wallet, adding new wallets, and retrieving seed phrases
///
/// Copied from [WalletViewModel].
@ProviderFor(WalletViewModel)
final walletViewModelProvider =
    AutoDisposeNotifierProvider<WalletViewModel, WalletState>.internal(
  WalletViewModel.new,
  name: r'walletViewModelProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$walletViewModelHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$WalletViewModel = AutoDisposeNotifier<WalletState>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
