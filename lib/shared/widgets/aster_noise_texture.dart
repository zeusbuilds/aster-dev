import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Decorative brand noise with a bounded, viewport-aware image decode.
class AsterNoiseTexture extends StatelessWidget {
  const AsterNoiseTexture({super.key});

  static const _assetName = 'assets/texture/noise.jpg';
  static const _sourceWidth = 1600;
  static const _sourceAspectRatio = 1600 / 1066;

  @override
  Widget build(BuildContext context) {
    final mediaSize = MediaQuery.sizeOf(context);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final colors = context.appColors;
    final effects = context.effects;

    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : mediaSize.width;
          final height = constraints.hasBoundedHeight
              ? constraints.maxHeight
              : mediaSize.height;
          final coverWidth = math.max(width, height * _sourceAspectRatio);
          final cacheWidth = (coverWidth * devicePixelRatio).ceil().clamp(
            1,
            _sourceWidth,
          );

          return Opacity(
            opacity: effects.artNoiseOpacity,
            child: Image.asset(
              _assetName,
              cacheWidth: cacheWidth,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              color: colors.artNoiseTint.withValues(
                alpha: effects.artNoiseTintOpacity,
              ),
              colorBlendMode: BlendMode.overlay,
            ),
          );
        },
      ),
    );
  }
}
