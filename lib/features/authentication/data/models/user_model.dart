import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_model.freezed.dart';
part 'user_model.g.dart';

/// User model
@freezed
class UserModel with _$UserModel {
  const factory UserModel({
    /// Unique identifier for the user
    required String id,

    /// User's email address
    required String email,

    /// User's display name (optional)
    String? name,
  }) = _UserModel;

  factory UserModel.fromJson(Map<String, dynamic> json) =>
      _$UserModelFromJson(json);
}
