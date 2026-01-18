// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'verify_request.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

VerifyRequest _$VerifyRequestFromJson(Map<String, dynamic> json) {
  return _VerifyRequest.fromJson(json);
}

/// @nodoc
mixin _$VerifyRequest {
  String get email => throw _privateConstructorUsedError;
  String get code => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $VerifyRequestCopyWith<VerifyRequest> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $VerifyRequestCopyWith<$Res> {
  factory $VerifyRequestCopyWith(
          VerifyRequest value, $Res Function(VerifyRequest) then) =
      _$VerifyRequestCopyWithImpl<$Res, VerifyRequest>;
  @useResult
  $Res call({String email, String code});
}

/// @nodoc
class _$VerifyRequestCopyWithImpl<$Res, $Val extends VerifyRequest>
    implements $VerifyRequestCopyWith<$Res> {
  _$VerifyRequestCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? email = null,
    Object? code = null,
  }) {
    return _then(_value.copyWith(
      email: null == email
          ? _value.email
          : email // ignore: cast_nullable_to_non_nullable
              as String,
      code: null == code
          ? _value.code
          : code // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$VerifyRequestImplCopyWith<$Res>
    implements $VerifyRequestCopyWith<$Res> {
  factory _$$VerifyRequestImplCopyWith(
          _$VerifyRequestImpl value, $Res Function(_$VerifyRequestImpl) then) =
      __$$VerifyRequestImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String email, String code});
}

/// @nodoc
class __$$VerifyRequestImplCopyWithImpl<$Res>
    extends _$VerifyRequestCopyWithImpl<$Res, _$VerifyRequestImpl>
    implements _$$VerifyRequestImplCopyWith<$Res> {
  __$$VerifyRequestImplCopyWithImpl(
      _$VerifyRequestImpl _value, $Res Function(_$VerifyRequestImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? email = null,
    Object? code = null,
  }) {
    return _then(_$VerifyRequestImpl(
      email: null == email
          ? _value.email
          : email // ignore: cast_nullable_to_non_nullable
              as String,
      code: null == code
          ? _value.code
          : code // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$VerifyRequestImpl implements _VerifyRequest {
  const _$VerifyRequestImpl({required this.email, required this.code});

  factory _$VerifyRequestImpl.fromJson(Map<String, dynamic> json) =>
      _$$VerifyRequestImplFromJson(json);

  @override
  final String email;
  @override
  final String code;

  @override
  String toString() {
    return 'VerifyRequest(email: $email, code: $code)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$VerifyRequestImpl &&
            (identical(other.email, email) || other.email == email) &&
            (identical(other.code, code) || other.code == code));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, email, code);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$VerifyRequestImplCopyWith<_$VerifyRequestImpl> get copyWith =>
      __$$VerifyRequestImplCopyWithImpl<_$VerifyRequestImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$VerifyRequestImplToJson(
      this,
    );
  }
}

abstract class _VerifyRequest implements VerifyRequest {
  const factory _VerifyRequest(
      {required final String email,
      required final String code}) = _$VerifyRequestImpl;

  factory _VerifyRequest.fromJson(Map<String, dynamic> json) =
      _$VerifyRequestImpl.fromJson;

  @override
  String get email;
  @override
  String get code;
  @override
  @JsonKey(ignore: true)
  _$$VerifyRequestImplCopyWith<_$VerifyRequestImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
