// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'currency_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$CurrencyModelImpl _$$CurrencyModelImplFromJson(Map<String, dynamic> json) =>
    _$CurrencyModelImpl(
      name: json['name'] as String,
      symbol: json['symbol'] as String,
      code: json['code'] as String,
      countryCode: json['countryCode'] as String,
    );

Map<String, dynamic> _$$CurrencyModelImplToJson(_$CurrencyModelImpl instance) =>
    <String, dynamic>{
      'name': instance.name,
      'symbol': instance.symbol,
      'code': instance.code,
      'countryCode': instance.countryCode,
    };
