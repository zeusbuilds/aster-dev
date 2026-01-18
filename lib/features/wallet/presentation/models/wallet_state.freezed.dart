// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'wallet_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$WalletState {
  /// Whether wallets are currently being loaded
  bool get isLoading => throw _privateConstructorUsedError;

  /// List of all available wallets
  List<WalletModel> get wallets => throw _privateConstructorUsedError;

  /// Currently active/selected wallet
  WalletModel? get activeWallet => throw _privateConstructorUsedError;

  /// Error message if any operation failed
  String? get errorMessage => throw _privateConstructorUsedError;

  @JsonKey(ignore: true)
  $WalletStateCopyWith<WalletState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $WalletStateCopyWith<$Res> {
  factory $WalletStateCopyWith(
          WalletState value, $Res Function(WalletState) then) =
      _$WalletStateCopyWithImpl<$Res, WalletState>;
  @useResult
  $Res call(
      {bool isLoading,
      List<WalletModel> wallets,
      WalletModel? activeWallet,
      String? errorMessage});
}

/// @nodoc
class _$WalletStateCopyWithImpl<$Res, $Val extends WalletState>
    implements $WalletStateCopyWith<$Res> {
  _$WalletStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? isLoading = null,
    Object? wallets = null,
    Object? activeWallet = freezed,
    Object? errorMessage = freezed,
  }) {
    return _then(_value.copyWith(
      isLoading: null == isLoading
          ? _value.isLoading
          : isLoading // ignore: cast_nullable_to_non_nullable
              as bool,
      wallets: null == wallets
          ? _value.wallets
          : wallets // ignore: cast_nullable_to_non_nullable
              as List<WalletModel>,
      activeWallet: freezed == activeWallet
          ? _value.activeWallet
          : activeWallet // ignore: cast_nullable_to_non_nullable
              as WalletModel?,
      errorMessage: freezed == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$WalletStateImplCopyWith<$Res>
    implements $WalletStateCopyWith<$Res> {
  factory _$$WalletStateImplCopyWith(
          _$WalletStateImpl value, $Res Function(_$WalletStateImpl) then) =
      __$$WalletStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {bool isLoading,
      List<WalletModel> wallets,
      WalletModel? activeWallet,
      String? errorMessage});
}

/// @nodoc
class __$$WalletStateImplCopyWithImpl<$Res>
    extends _$WalletStateCopyWithImpl<$Res, _$WalletStateImpl>
    implements _$$WalletStateImplCopyWith<$Res> {
  __$$WalletStateImplCopyWithImpl(
      _$WalletStateImpl _value, $Res Function(_$WalletStateImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? isLoading = null,
    Object? wallets = null,
    Object? activeWallet = freezed,
    Object? errorMessage = freezed,
  }) {
    return _then(_$WalletStateImpl(
      isLoading: null == isLoading
          ? _value.isLoading
          : isLoading // ignore: cast_nullable_to_non_nullable
              as bool,
      wallets: null == wallets
          ? _value._wallets
          : wallets // ignore: cast_nullable_to_non_nullable
              as List<WalletModel>,
      activeWallet: freezed == activeWallet
          ? _value.activeWallet
          : activeWallet // ignore: cast_nullable_to_non_nullable
              as WalletModel?,
      errorMessage: freezed == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc

class _$WalletStateImpl implements _WalletState {
  const _$WalletStateImpl(
      {this.isLoading = false,
      final List<WalletModel> wallets = const [],
      this.activeWallet,
      this.errorMessage})
      : _wallets = wallets;

  /// Whether wallets are currently being loaded
  @override
  @JsonKey()
  final bool isLoading;

  /// List of all available wallets
  final List<WalletModel> _wallets;

  /// List of all available wallets
  @override
  @JsonKey()
  List<WalletModel> get wallets {
    if (_wallets is EqualUnmodifiableListView) return _wallets;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_wallets);
  }

  /// Currently active/selected wallet
  @override
  final WalletModel? activeWallet;

  /// Error message if any operation failed
  @override
  final String? errorMessage;

  @override
  String toString() {
    return 'WalletState(isLoading: $isLoading, wallets: $wallets, activeWallet: $activeWallet, errorMessage: $errorMessage)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WalletStateImpl &&
            (identical(other.isLoading, isLoading) ||
                other.isLoading == isLoading) &&
            const DeepCollectionEquality().equals(other._wallets, _wallets) &&
            (identical(other.activeWallet, activeWallet) ||
                other.activeWallet == activeWallet) &&
            (identical(other.errorMessage, errorMessage) ||
                other.errorMessage == errorMessage));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      isLoading,
      const DeepCollectionEquality().hash(_wallets),
      activeWallet,
      errorMessage);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$WalletStateImplCopyWith<_$WalletStateImpl> get copyWith =>
      __$$WalletStateImplCopyWithImpl<_$WalletStateImpl>(this, _$identity);
}

abstract class _WalletState implements WalletState {
  const factory _WalletState(
      {final bool isLoading,
      final List<WalletModel> wallets,
      final WalletModel? activeWallet,
      final String? errorMessage}) = _$WalletStateImpl;

  @override

  /// Whether wallets are currently being loaded
  bool get isLoading;
  @override

  /// List of all available wallets
  List<WalletModel> get wallets;
  @override

  /// Currently active/selected wallet
  WalletModel? get activeWallet;
  @override

  /// Error message if any operation failed
  String? get errorMessage;
  @override
  @JsonKey(ignore: true)
  _$$WalletStateImplCopyWith<_$WalletStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
