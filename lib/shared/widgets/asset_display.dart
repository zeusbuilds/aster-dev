import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/theme.dart';

class AssetDisplay {
  AssetDisplay._();

  static Color colorOf(BuildContext context, AssetModel asset) {
    final colors = context.appColors;
    return switch (asset.token.toUpperCase()) {
      'BTC' => colors.bitcoin,
      'LBTC' => colors.liquid,
      'USDT' => colors.success,
      _ => context.colorScheme.primary,
    };
  }
}
