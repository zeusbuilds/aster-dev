// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'asset_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$AssetModelImpl _$$AssetModelImplFromJson(Map<String, dynamic> json) =>
    _$AssetModelImpl(
      token: json['token'] as String,
      chain: json['chain'] as String,
      icon: json['icon'] as String,
      color: (json['color'] as num).toInt(),
      unit: json['unit'] as String,
    );

Map<String, dynamic> _$$AssetModelImplToJson(_$AssetModelImpl instance) =>
    <String, dynamic>{
      'token': instance.token,
      'chain': instance.chain,
      'icon': instance.icon,
      'color': instance.color,
      'unit': instance.unit,
    };
