import 'package:flutter/material.dart';

import 'package:aster/shared/shared.dart';

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
    final colors = context.colors;
    final spacing = context.spacing;
    final radius = context.radius;
    final textTheme = context.textTheme;
    final shadows = context.shadows;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius.radius24),
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
                top: -spacing.spacing10,
                right: -spacing.spacing30,
                child: Container(
                  decoration: BoxDecoration(
                    boxShadow: shadowColor != null
                        ? shadows.shadow20
                              .map(
                                (s) => BoxShadow(
                                  color: shadowColor!,
                                  offset: s.offset,
                                  blurRadius: s.blurRadius,
                                  spreadRadius: s.spreadRadius,
                                ),
                              )
                              .toList()
                        : shadows.shadow20,
                  ),
                  child: Image.asset(
                    'assets/texture/shape.png',
                    width: spacing.spacing96 * 2,
                    height: spacing.spacing96 * 2,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.all(spacing.spacing16),
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
                              color: colors.text5.withValues(alpha: 0.75),
                            ),
                          ),
                          Text(
                            subtitle ?? '',
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colors.text5,
                            ),
                          ),
                          SizedBox(height: spacing.spacing24),
                          if (tipText != null) ...[
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: spacing.spacing4,
                                vertical: spacing.spacing4,
                              ),
                              decoration: BoxDecoration(
                                color: colors.text5.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(
                                  radius.radius50,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color: colors.text5.withValues(
                                        alpha: 0.5,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    width: spacing.spacing20,
                                    height: spacing.spacing20,
                                  ),
                                  SizedBox(width: spacing.spacing8),
                                  Text(
                                    tipText!,
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: colors.text5.withValues(
                                        alpha: 0.75,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(width: spacing.spacing10),
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
