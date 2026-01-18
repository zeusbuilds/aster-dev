import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../core/core.dart';
import '../../data/datasource/auth_api_service.dart';
import '../../data/repositories/auth_repository.dart';

part 'auth_providers.g.dart';

/// Auth API service provider
@riverpod
AuthApiService authApiService(AuthApiServiceRef ref) {
  final chopperClient = ref.watch(chopperClientProvider);
  return AuthApiService.create(chopperClient);
}

/// Auth repository provider
@riverpod
AuthRepository authRepository(AuthRepositoryRef ref) {
  return AuthRepositoryImpl(
    apiService: ref.watch(authApiServiceProvider),
    secureStorage: ref.watch(secureStorageServiceProvider),
    networkInfo: ref.watch(networkInfoProvider),
  );
}

/// Auth token provider - for getting the current access token
@riverpod
Future<String?> authToken(AuthTokenRef ref) async {
  final repository = ref.watch(authRepositoryProvider);
  return await repository.getAccessToken();
}
