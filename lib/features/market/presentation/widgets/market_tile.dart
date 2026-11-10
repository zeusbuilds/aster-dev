import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';

const _marketArtworkMaximumDecodeDimension = 600;

/// Foreground polarity for the authored light or dark Market artwork.
enum MarketContentTone { light, dark }

/// Semantic Market action with stable squircle geometry and status capsule.
class MarketTile extends StatelessWidget {
  /// Short action name.
  final String label;

  /// Supporting capability or availability copy.
  final String? subtitle;

  /// Compact status rendered in the lower capsule.
  final String? tipText;

  /// Visual identity for this action.
  final IconData icon;

  /// Decorative artwork bundled for this action.
  final String artworkAsset;

  /// Accepted action, or `null` when the capability is unavailable.
  final VoidCallback? onTap;

  /// Tactile feedback emitted only after an enabled activation.
  final HapticIntent? hapticIntent;

  /// Authored Market background recipe.
  final AsterGradientSpec gradient;

  /// Optional tint applied to the decorative texture shadow.
  final Color? shadowColor;
  final MarketContentTone contentTone;
  final bool compact;

  const MarketTile({
    super.key,
    required this.label,
    this.subtitle,
    this.tipText,
    required this.icon,
    required this.artworkAsset,
    this.onTap,
    this.hapticIntent = HapticIntent.lightImpact,
    required this.gradient,
    this.shadowColor,
    this.contentTone = MarketContentTone.light,
    this.compact = false,
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
    final darkContent = contentTone == MarketContentTone.dark;
    final foreground = darkContent
        ? colors.marketDarkText
        : colors.onMarketTile;
    final capsuleBase = darkContent
        ? colors.onMarketTile
        : colors.marketDarkText;
    final artworkSize = compact
        ? metrics.marketTextureSize * 0.75
        : metrics.marketTextureSize;
    final artworkDecodeDimension =
        (artworkSize * MediaQuery.devicePixelRatioOf(context)).ceil().clamp(
          1,
          _marketArtworkMaximumDecodeDimension,
        );

    void activate() {
      if (onTap == null) return;
      if (hapticIntent case final intent?) {
        unawaited(context.haptics.trigger(intent));
      }
      onTap?.call();
    }

    return Semantics(
      button: true,
      enabled: onTap != null,
      onTap: onTap == null ? null : activate,
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
                  top: compact ? -spacing.xs : -spacing.md,
                  right: compact ? -spacing.md : -spacing.xl,
                  child: Container(
                    decoration: BoxDecoration(
                      boxShadow: shadowColor != null
                          ? shadows.modal
                                .map((s) => s.copyWith(color: shadowColor!))
                                .toList(growable: false)
                          : shadows.modal,
                    ),
                    child: ExcludeSemantics(
                      child: Image.asset(
                        artworkAsset,
                        width: artworkSize,
                        height: artworkSize,
                        cacheWidth: artworkDecodeDimension,
                        cacheHeight: artworkDecodeDimension,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: spacing.lg,
                    vertical: compact ? spacing.md : spacing.lg,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              label,
                              style: type.marketLabel.copyWith(
                                color: foreground,
                              ),
                            ),
                            if (subtitle case final value?)
                              Text(
                                value,
                                style: type.marketTitle.copyWith(
                                  color: foreground,
                                ),
                              ),
                            if (tipText case final value?) ...[
                              SizedBox(
                                height: compact ? spacing.sm : spacing.xxl,
                              ),
                              AsterPill(
                                padding: EdgeInsets.fromLTRB(
                                  spacing.xs,
                                  spacing.xs,
                                  spacing.sm,
                                  spacing.xs,
                                ),
                                color: capsuleBase.withValues(
                                  alpha: effects.marketPillSurfaceOpacity,
                                ),
                                child: Row(
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
                                      alignment: Alignment.center,
                                      child: Icon(
                                        icon,
                                        size: context.icons.xxs,
                                        color: colors.onMarketTile,
                                      ),
                                    ),
                                    SizedBox(width: spacing.sm),
                                    Flexible(
                                      child: Text(
                                        value,
                                        style: type.marketTip.copyWith(
                                          color: foreground,
                                        ),
                                      ),
                                    ),
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
