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
  final List<Color> gradientColors;
  final Color? shadowColor;

  const MarketTile({
    super.key,
    required this.label,
    this.subtitle,
    this.tipText,
    required this.icon,
    this.onTap,
    required this.gradientColors,
    this.shadowColor,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.appColors;
    final effects = context.effects;
    final metrics = context.metrics;
    final radius = context.radii;
    final textTheme = context.textTheme;
    final shadows = context.shadows;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius.card),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
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
                          Text(
                            label,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: colors.onMarketTile.withValues(
                                alpha: effects.marketContentMutedOpacity,
                              ),
                            ),
                          ),
                          Text(
                            subtitle ?? '',
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colors.onMarketTile,
                            ),
                          ),
                          SizedBox(height: spacing.xxl),
                          if (tipText != null) ...[
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: spacing.xs,
                                vertical: spacing.xs,
                              ),
                              decoration: BoxDecoration(
                                color: colors.onMarketTile.withValues(
                                  alpha: effects.marketPillSurfaceOpacity,
                                ),
                                borderRadius: BorderRadius.circular(
                                  radius.pill,
                                ),
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
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: colors.onMarketTile.withValues(
                                        alpha:
                                            effects.marketContentMutedOpacity,
                                      ),
                                      fontWeight: FontWeight.w600,
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
    );
  }
}
