import 'package:chopper/chopper.dart';

import '../models/models.dart';

part 'auth_api_service.chopper.dart';

/// Authentication API service using Chopper
@ChopperApi(baseUrl: '/api/v1/auth')
abstract class AuthApiService extends ChopperService {
  /// Login endpoint
  @Post(path: '/login/')
  Future<Response<AuthResponse>> login(@Body() LoginRequest request);

  /// Verify endpoint
  @Post(path: '/verify/')
  Future<Response<AuthResponse>> verify(@Body() VerifyRequest request);

  /// Factory to create the service
  static AuthApiService create(ChopperClient client) {
    return _$AuthApiService(client);
  }
}
