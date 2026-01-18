// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$authApiServiceHash() => r'35420ed27310d42c3242c719ca8f91491677b0ab';

/// Auth API service provider
///
/// Copied from [authApiService].
@ProviderFor(authApiService)
final authApiServiceProvider = AutoDisposeProvider<AuthApiService>.internal(
  authApiService,
  name: r'authApiServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$authApiServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef AuthApiServiceRef = AutoDisposeProviderRef<AuthApiService>;
String _$authRepositoryHash() => r'de3fc116214d0244a16f76dde70d962f8f9fb2d0';

/// Auth repository provider
///
/// Copied from [authRepository].
@ProviderFor(authRepository)
final authRepositoryProvider = AutoDisposeProvider<AuthRepository>.internal(
  authRepository,
  name: r'authRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$authRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef AuthRepositoryRef = AutoDisposeProviderRef<AuthRepository>;
String _$authTokenHash() => r'8e912dc5497744fd9d89c8575da49bd6a1c1905b';

/// Auth token provider - for getting the current access token
///
/// Copied from [authToken].
@ProviderFor(authToken)
final authTokenProvider = AutoDisposeFutureProvider<String?>.internal(
  authToken,
  name: r'authTokenProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$authTokenHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef AuthTokenRef = AutoDisposeFutureProviderRef<String?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
