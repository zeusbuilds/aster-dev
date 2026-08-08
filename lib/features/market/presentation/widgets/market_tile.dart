import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';

/// Market tile widget displaying text on left and SVG on right
///
/// Two texts in a column on the left, SVG icon on the right
/// & tip text on bottom right
class MarketTile extends StatelessWidget {
  final String label;
  final String? subtitle;
  final String? tipText;
  final IconData icon;
  final VoidCallback? onTap;
  final AsterGradientSpec gradient;
  final Color? shadowColor;

  const MarketTile({
    super.key,
    required this.label,
    this.subtitle,
    this.tipText,
    required this.icon,
    this.onTap,
    required this.gradient,
    this.shadowColor,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.appColors;
    final effects = context.effects;
    final metrics = context.metrics;
    final radius = context.radii;
    final shadows = context.shadows;
    final type = context.type;

    void activate() {
      unawaited(context.haptics.trigger(HapticIntent.lightImpact));
      onTap?.call();
    }

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: [label, subtitle, tipText].whereType<String>().join(', '),
      excludeSemantics: true,
      child: Squircle(
        borderRadius: radius.card,
        borderColor: colors.transparentSurface,
        borderWidth: 0,
        gradient: gradient.toLinearGradient(),
        padding: EdgeInsets.zero,
        child: Material(
          color: colors.transparentSurface,
          child: InkWell(
            onTap: onTap == null ? null : activate,
            child: Stack(
              children: [
                Positioned(
                  top: -spacing.md,
                  right: -spacing.xxxl,
                  child: Container(
                    decoration: BoxDecoration(
                      boxShadow: shadowColor != null
                          ? shadows.modal
                                .map((s) => s.copyWith(color: shadowColor!))
                                .toList()
                          : shadows.modal,
                    ),
                    child: Image.asset(
                      'assets/texture/shape.png',
                      width: metrics.marketTextureSize,
                      height: metrics.marketTextureSize,
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.all(spacing.lg),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(label, style: type.marketLabel),
                            Text(subtitle ?? '', style: type.marketTitle),
                            SizedBox(height: spacing.xxl),
                            if (tipText != null) ...[
                              AsterPill(
                                padding: EdgeInsets.symmetric(
                                  horizontal: spacing.xs,
                                  vertical: spacing.xs,
                                ),
                                color: colors.onMarketTile.withValues(
                                  alpha: effects.marketPillSurfaceOpacity,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        color: colors.onMarketTile.withValues(
                                          alpha: effects.marketPillDotOpacity,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      width: metrics.marketBadgeDotSize,
                                      height: metrics.marketBadgeDotSize,
                                    ),
                                    SizedBox(width: spacing.sm),
                                    Text(
                                      tipText!,
                                      style: type.marketTip.copyWith(
                                        color: colors.onMarketTile.withValues(
                                          alpha:
                                              effects.marketContentMutedOpacity,
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: spacing.md),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
