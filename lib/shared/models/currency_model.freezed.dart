// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'currency_model.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

CurrencyModel _$CurrencyModelFromJson(Map<String, dynamic> json) {
  return _CurrencyModel.fromJson(json);
}

/// @nodoc
mixin _$CurrencyModel {
  String get name => throw _privateConstructorUsedError;
  String get symbol => throw _privateConstructorUsedError;
  String get code => throw _privateConstructorUsedError;
  String get countryCode => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $CurrencyModelCopyWith<CurrencyModel> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CurrencyModelCopyWith<$Res> {
  factory $CurrencyModelCopyWith(
          CurrencyModel value, $Res Function(CurrencyModel) then) =
      _$CurrencyModelCopyWithImpl<$Res, CurrencyModel>;
  @useResult
  $Res call({String name, String symbol, String code, String countryCode});
}

/// @nodoc
class _$CurrencyModelCopyWithImpl<$Res, $Val extends CurrencyModel>
    implements $CurrencyModelCopyWith<$Res> {
  _$CurrencyModelCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? symbol = null,
    Object? code = null,
    Object? countryCode = null,
  }) {
    return _then(_value.copyWith(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      symbol: null == symbol
          ? _value.symbol
          : symbol // ignore: cast_nullable_to_non_nullable
              as String,
      code: null == code
          ? _value.code
          : code // ignore: cast_nullable_to_non_nullable
              as String,
      countryCode: null == countryCode
          ? _value.countryCode
          : countryCode // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CurrencyModelImplCopyWith<$Res>
    implements $CurrencyModelCopyWith<$Res> {
  factory _$$CurrencyModelImplCopyWith(
          _$CurrencyModelImpl value, $Res Function(_$CurrencyModelImpl) then) =
      __$$CurrencyModelImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String name, String symbol, String code, String countryCode});
}

/// @nodoc
class __$$CurrencyModelImplCopyWithImpl<$Res>
    extends _$CurrencyModelCopyWithImpl<$Res, _$CurrencyModelImpl>
    implements _$$CurrencyModelImplCopyWith<$Res> {
  __$$CurrencyModelImplCopyWithImpl(
      _$CurrencyModelImpl _value, $Res Function(_$CurrencyModelImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? name = null,
    Object? symbol = null,
    Object? code = null,
    Object? countryCode = null,
  }) {
    return _then(_$CurrencyModelImpl(
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      symbol: null == symbol
          ? _value.symbol
          : symbol // ignore: cast_nullable_to_non_nullable
              as String,
      code: null == code
          ? _value.code
          : code // ignore: cast_nullable_to_non_nullable
              as String,
      countryCode: null == countryCode
          ? _value.countryCode
          : countryCode // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CurrencyModelImpl implements _CurrencyModel {
  const _$CurrencyModelImpl(
      {required this.name,
      required this.symbol,
      required this.code,
      required this.countryCode});

  factory _$CurrencyModelImpl.fromJson(Map<String, dynamic> json) =>
      _$$CurrencyModelImplFromJson(json);

  @override
  final String name;
  @override
  final String symbol;
  @override
  final String code;
  @override
  final String countryCode;

  @override
  String toString() {
    return 'CurrencyModel(name: $name, symbol: $symbol, code: $code, countryCode: $countryCode)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CurrencyModelImpl &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.symbol, symbol) || other.symbol == symbol) &&
            (identical(other.code, code) || other.code == code) &&
            (identical(other.countryCode, countryCode) ||
                other.countryCode == countryCode));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, name, symbol, code, countryCode);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$CurrencyModelImplCopyWith<_$CurrencyModelImpl> get copyWith =>
      __$$CurrencyModelImplCopyWithImpl<_$CurrencyModelImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CurrencyModelImplToJson(
      this,
    );
  }
}

abstract class _CurrencyModel implements CurrencyModel {
  const factory _CurrencyModel(
      {required final String name,
      required final String symbol,
      required final String code,
      required final String countryCode}) = _$CurrencyModelImpl;

  factory _CurrencyModel.fromJson(Map<String, dynamic> json) =
      _$CurrencyModelImpl.fromJson;

  @override
  String get name;
  @override
  String get symbol;
  @override
  String get code;
  @override
  String get countryCode;
  @override
  @JsonKey(ignore: true)
  _$$CurrencyModelImplCopyWith<_$CurrencyModelImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
