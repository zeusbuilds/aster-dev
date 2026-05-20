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
                              .map(
                                (s) => BoxShadow(
                                  color: shadowColor!,
                                  offset: s.offset,
                                  blurRadius: s.blurRadius,
                                  spreadRadius: s.spreadRadius,
                                ),
                              )
                              .toList()
                        : shadows.modal,
                  ),
                  child: Image.asset(
                    'assets/texture/shape.png',
                    width: spacing.giant * 2,
                    height: spacing.giant * 2,
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
                              color: AsterColors.white.withValues(alpha: 0.75),
                            ),
                          ),
                          Text(
                            subtitle ?? '',
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AsterColors.white,
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
                                color: AsterColors.white.withValues(
                                  alpha: 0.15,
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
                                      color: AsterColors.white.withValues(
                                        alpha: 0.5,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    width: spacing.screenPadding,
                                    height: spacing.screenPadding,
                                  ),
                                  SizedBox(width: spacing.sm),
                                  Text(
                                    tipText!,
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: AsterColors.white.withValues(
                                        alpha: 0.75,
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
