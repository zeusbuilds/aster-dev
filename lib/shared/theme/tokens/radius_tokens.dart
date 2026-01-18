import 'package:freezed_annotation/freezed_annotation.dart';

part 'radius_tokens.freezed.dart';

/// Shape tokens configuration
@freezed
class RadiusTokens with _$RadiusTokens {
  const factory RadiusTokens({
    @Default(2.0) double radius2,
    @Default(4.0) double radius4,
    @Default(6.0) double radius6,
    @Default(8.0) double radius8,
    @Default(10.0) double radius10,
    @Default(12.0) double radius12,
    @Default(14.0) double radius14,
    @Default(16.0) double radius16,
    @Default(18.0) double radius18,
    @Default(20.0) double radius20,
    @Default(22.0) double radius22,
    @Default(24.0) double radius24,
    @Default(26.0) double radius26,
    @Default(28.0) double radius28,
    @Default(30.0) double radius30,
    @Default(32.0) double radius32,
    @Default(34.0) double radius34,
    @Default(36.0) double radius36,
    @Default(38.0) double radius38,
    @Default(40.0) double radius40,
    @Default(42.0) double radius42,
    @Default(44.0) double radius44,
    @Default(46.0) double radius46,
    @Default(48.0) double radius48,
    @Default(50.0) double radius50,
  }) = _RadiusTokens;
}
