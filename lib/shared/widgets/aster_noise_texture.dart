import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Decorative brand noise with a bounded, viewport-aware image decode.
class AsterNoiseTexture extends StatefulWidget {
  const AsterNoiseTexture({super.key, this.onImageReady});

  static const _assetName = 'assets/texture/noise.jpg';
  static const _sourceWidth = 1600;
  static const _sourceAspectRatio = 1600 / 1066;

  /// Called after the texture's first decoded frame is available for paint.
  final VoidCallback? onImageReady;

  @override
  State<AsterNoiseTexture> createState() => _AsterNoiseTextureState();
}

class _AsterNoiseTextureState extends State<AsterNoiseTexture> {
  var _didScheduleImageReady = false;

  void _notifyImageReady(int? frame, {required bool wasSynchronouslyLoaded}) {
    if ((frame == null && !wasSynchronouslyLoaded) ||
        widget.onImageReady == null ||
        _didScheduleImageReady) {
      return;
    }
    _didScheduleImageReady = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onImageReady?.call();
    });
  }

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
          final coverWidth = math.max(
            width,
            height * AsterNoiseTexture._sourceAspectRatio,
          );
          final cacheWidth = (coverWidth * devicePixelRatio).ceil().clamp(
            1,
            AsterNoiseTexture._sourceWidth,
          );

          return Opacity(
            opacity: effects.artNoiseOpacity,
            child: Image.asset(
              AsterNoiseTexture._assetName,
              cacheWidth: cacheWidth,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              color: colors.artNoiseTint.withValues(
                alpha: effects.artNoiseTintOpacity,
              ),
              colorBlendMode: BlendMode.overlay,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                _notifyImageReady(
                  frame,
                  wasSynchronouslyLoaded: wasSynchronouslyLoaded,
                );
                return child;
              },
            ),
          );
        },
      ),
    );
  }
}
