import 'package:flutter/material.dart';

import 'package:aster/shared/shared.dart';

/// Market tile widget displaying text on left and SVG on right
///
/// Two texts in a column on the left, SVG icon on the right
class MarketTile extends StatelessWidget {
  final String label;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  const MarketTile({
    super.key,
    required this.label,
    this.subtitle,
    required this.icon,
    this.onTap,
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
              colors: [
                Color.fromARGB(255, 105, 105, 105),
                Color.fromARGB(255, 105, 105, 105),
              ],
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
                  decoration: BoxDecoration(boxShadow: shadows.shadow20),
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
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: spacing.spacing4,
                              vertical: spacing.spacing4,
                            ),
                            decoration: BoxDecoration(
                              color: colors.text5.withValues(alpha: 0.2),
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
                                    color: colors.text5.withValues(alpha: 0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  width: spacing.spacing20,
                                  height: spacing.spacing20,
                                ),
                                SizedBox(width: spacing.spacing8),
                                Text(
                                  '12.4% APY',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: colors.text5.withValues(alpha: 0.75),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(width: spacing.spacing10),
                              ],
                            ),
                          ),
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
