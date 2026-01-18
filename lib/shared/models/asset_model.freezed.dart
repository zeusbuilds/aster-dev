// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'asset_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

AssetModel _$AssetModelFromJson(Map<String, dynamic> json) {
  return _AssetModel.fromJson(json);
}

/// @nodoc
mixin _$AssetModel {
  String get token => throw _privateConstructorUsedError;
  String get chain => throw _privateConstructorUsedError;
  String get icon => throw _privateConstructorUsedError;
  int get color => throw _privateConstructorUsedError;
  String get unit => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $AssetModelCopyWith<AssetModel> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AssetModelCopyWith<$Res> {
  factory $AssetModelCopyWith(
          AssetModel value, $Res Function(AssetModel) then) =
      _$AssetModelCopyWithImpl<$Res, AssetModel>;
  @useResult
  $Res call({String token, String chain, String icon, int color, String unit});
}

/// @nodoc
class _$AssetModelCopyWithImpl<$Res, $Val extends AssetModel>
    implements $AssetModelCopyWith<$Res> {
  _$AssetModelCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? token = null,
    Object? chain = null,
    Object? icon = null,
    Object? color = null,
    Object? unit = null,
  }) {
    return _then(_value.copyWith(
      token: null == token
          ? _value.token
          : token // ignore: cast_nullable_to_non_nullable
              as String,
      chain: null == chain
          ? _value.chain
          : chain // ignore: cast_nullable_to_non_nullable
              as String,
      icon: null == icon
          ? _value.icon
          : icon // ignore: cast_nullable_to_non_nullable
              as String,
      color: null == color
          ? _value.color
          : color // ignore: cast_nullable_to_non_nullable
              as int,
      unit: null == unit
          ? _value.unit
          : unit // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AssetModelImplCopyWith<$Res>
    implements $AssetModelCopyWith<$Res> {
  factory _$$AssetModelImplCopyWith(
          _$AssetModelImpl value, $Res Function(_$AssetModelImpl) then) =
      __$$AssetModelImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String token, String chain, String icon, int color, String unit});
}

/// @nodoc
class __$$AssetModelImplCopyWithImpl<$Res>
    extends _$AssetModelCopyWithImpl<$Res, _$AssetModelImpl>
    implements _$$AssetModelImplCopyWith<$Res> {
  __$$AssetModelImplCopyWithImpl(
      _$AssetModelImpl _value, $Res Function(_$AssetModelImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? token = null,
    Object? chain = null,
    Object? icon = null,
    Object? color = null,
    Object? unit = null,
  }) {
    return _then(_$AssetModelImpl(
      token: null == token
          ? _value.token
          : token // ignore: cast_nullable_to_non_nullable
              as String,
      chain: null == chain
          ? _value.chain
          : chain // ignore: cast_nullable_to_non_nullable
              as String,
      icon: null == icon
          ? _value.icon
          : icon // ignore: cast_nullable_to_non_nullable
              as String,
      color: null == color
          ? _value.color
          : color // ignore: cast_nullable_to_non_nullable
              as int,
      unit: null == unit
          ? _value.unit
          : unit // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$AssetModelImpl implements _AssetModel {
  const _$AssetModelImpl(
      {required this.token,
      required this.chain,
      required this.icon,
      required this.color,
      required this.unit});

  factory _$AssetModelImpl.fromJson(Map<String, dynamic> json) =>
      _$$AssetModelImplFromJson(json);

  @override
  final String token;
  @override
  final String chain;
  @override
  final String icon;
  @override
  final int color;
  @override
  final String unit;

  @override
  String toString() {
    return 'AssetModel(token: $token, chain: $chain, icon: $icon, color: $color, unit: $unit)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AssetModelImpl &&
            (identical(other.token, token) || other.token == token) &&
            (identical(other.chain, chain) || other.chain == chain) &&
            (identical(other.icon, icon) || other.icon == icon) &&
            (identical(other.color, color) || other.color == color) &&
            (identical(other.unit, unit) || other.unit == unit));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, token, chain, icon, color, unit);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$AssetModelImplCopyWith<_$AssetModelImpl> get copyWith =>
      __$$AssetModelImplCopyWithImpl<_$AssetModelImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AssetModelImplToJson(
      this,
    );
  }
}

abstract class _AssetModel implements AssetModel {
  const factory _AssetModel(
      {required final String token,
      required final String chain,
      required final String icon,
      required final int color,
      required final String unit}) = _$AssetModelImpl;

  factory _AssetModel.fromJson(Map<String, dynamic> json) =
      _$AssetModelImpl.fromJson;

  @override
  String get token;
  @override
  String get chain;
  @override
  String get icon;
  @override
  int get color;
  @override
  String get unit;
  @override
  @JsonKey(ignore: true)
  _$$AssetModelImplCopyWith<_$AssetModelImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
