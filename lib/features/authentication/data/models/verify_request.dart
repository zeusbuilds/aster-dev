import 'package:freezed_annotation/freezed_annotation.dart';

part 'verify_request.freezed.dart';
part 'verify_request.g.dart';

/// Verify request model
@freezed
class VerifyRequest with _$VerifyRequest {
  const factory VerifyRequest({required String email, required String code}) =
      _VerifyRequest;

  factory VerifyRequest.fromJson(Map<String, dynamic> json) =>
      _$VerifyRequestFromJson(json);
}
