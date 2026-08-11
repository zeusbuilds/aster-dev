import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../shared/shared.dart';
import '../../domain/models/models.dart';
import '../models/models.dart';

/// Token-aware visual for one typed wallet asset.
class WalletAssetIcon extends StatelessWidget {
  const WalletAssetIcon({super.key, required this.kind, required this.size});

  final WalletAssetKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      kind.iconAsset,
      width: size,
      height: size,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.circle,
        size: size,
        color: switch (kind) {
          WalletAssetKind.bitcoin => context.appColors.bitcoin,
          WalletAssetKind.usdt => context.appColors.success,
        },
      ),
    );
  }
}
