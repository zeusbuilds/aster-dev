import 'package:flutter/material.dart';

import 'color_tokens.dart';
import 'effects_tokens.dart';

/// Semantic text roles used by feature UI.
///
/// Material `TextTheme` remains the size/role foundation. This extension adds
/// product-level emphasis and color decisions so screens do not re-decide
/// weights locally.
@immutable
class AsterTypeRoles extends ThemeExtension<AsterTypeRoles> {
  const AsterTypeRoles({
    required this.appBarTitle,
    required this.pageTitle,
    required this.buttonLabel,
    required this.compactButtonLabel,
    required this.sectionLabel,
    required this.sectionTitle,
    required this.title,
    required this.rowTitle,
    required this.rowTitleStrong,
    required this.rowValue,
    required this.rowMeta,
    required this.rowMetaStrong,
    required this.statusMessage,
    required this.amountLarge,
    required this.amountInline,
    required this.assetTitle,
    required this.assetValue,
    required this.assetMeta,
    required this.brandHero,
    required this.brandTitle,
    required this.brandWordmark,
    required this.brandAmount,
    required this.brandMetric,
    required this.brandBody,
    required this.brandAction,
    required this.toastTitle,
    required this.toastMessage,
    required this.badgeLabel,
    required this.supportingMeta,
    required this.errorMessage,
    required this.versionLabel,
    required this.addressLabel,
    required this.address,
    required this.addressHint,
    required this.addressSmall,
    required this.keypadNumber,
    required this.marketLabel,
    required this.marketTitle,
    required this.marketTip,
    required this.scanControl,
    required this.scanCta,
    required this.scanHeaderTitle,
    required this.scanWalletId,
  });

  final TextStyle appBarTitle;
  final TextStyle pageTitle;
  final TextStyle buttonLabel;
  final TextStyle compactButtonLabel;
  final TextStyle sectionLabel;
  final TextStyle sectionTitle;
  final TextStyle title;
  final TextStyle rowTitle;
  final TextStyle rowTitleStrong;
  final TextStyle rowValue;
  final TextStyle rowMeta;
  final TextStyle rowMetaStrong;
  final TextStyle statusMessage;
  final TextStyle amountLarge;
  final TextStyle amountInline;
  final TextStyle assetTitle;
  final TextStyle assetValue;
  final TextStyle assetMeta;
  final TextStyle brandHero;
  final TextStyle brandTitle;
  final TextStyle brandWordmark;
  final TextStyle brandAmount;
  final TextStyle brandMetric;
  final TextStyle brandBody;
  final TextStyle brandAction;
  final TextStyle toastTitle;
  final TextStyle toastMessage;
  final TextStyle badgeLabel;
  final TextStyle supportingMeta;
  final TextStyle errorMessage;
  final TextStyle versionLabel;
  final TextStyle addressLabel;
  final TextStyle address;
  final TextStyle addressHint;
  final TextStyle addressSmall;
  final TextStyle keypadNumber;
  final TextStyle marketLabel;
  final TextStyle marketTitle;
  final TextStyle marketTip;
  final TextStyle scanControl;
  final TextStyle scanCta;
  final TextStyle scanHeaderTitle;
  final TextStyle scanWalletId;

  factory AsterTypeRoles.fromTheme({
    required TextTheme textTheme,
    required ColorScheme colorScheme,
    required AsterColors colors,
    required AsterEffects effects,
  }) {
    TextStyle role(TextStyle? style, FontWeight weight, Color color) {
      return (style ?? const TextStyle()).copyWith(
        fontWeight: weight,
        color: color,
      );
    }

    final brandStrong = colors.onBrandArt.withValues(
      alpha: effects.brandContentStrongOpacity,
    );
    final scanSecondary = colors.onScan.withValues(
      alpha: effects.scanSecondaryContentOpacity,
    );

    return AsterTypeRoles(
      appBarTitle: role(
        textTheme.titleMedium,
        FontWeight.w600,
        colorScheme.onSurface,
      ),
      pageTitle: role(
        textTheme.headlineLarge,
        FontWeight.w700,
        colorScheme.onSurface,
      ),
      buttonLabel: role(
        textTheme.labelLarge,
        FontWeight.w600,
        colorScheme.onSurface,
      ),
      compactButtonLabel: role(
        textTheme.labelMedium,
        FontWeight.w500,
        colorScheme.onSurface,
      ),
      sectionLabel: role(
        textTheme.bodyMedium,
        FontWeight.w600,
        colorScheme.onSurface,
      ),
      sectionTitle: role(
        textTheme.bodyLarge,
        FontWeight.w700,
        colorScheme.onSurface,
      ),
      title: role(
        textTheme.titleMedium,
        FontWeight.w600,
        colorScheme.onSurface,
      ),
      rowTitle: role(
        textTheme.bodyMedium,
        FontWeight.w500,
        colorScheme.onSurface,
      ),
      rowTitleStrong: role(
        textTheme.bodyMedium,
        FontWeight.w600,
        colorScheme.onSurface,
      ),
      rowValue: role(
        textTheme.bodyMedium,
        FontWeight.w600,
        colorScheme.onSurface,
      ),
      rowMeta: role(
        textTheme.bodyMedium,
        FontWeight.w500,
        colors.textSecondary,
      ),
      rowMetaStrong: role(
        textTheme.bodyMedium,
        FontWeight.w600,
        colors.textSecondary,
      ),
      statusMessage: role(
        textTheme.bodyMedium,
        FontWeight.w400,
        colorScheme.onSurface,
      ),
      amountLarge: role(
        textTheme.headlineSmall,
        FontWeight.w700,
        colorScheme.onSurface,
      ),
      amountInline: role(
        textTheme.bodyMedium,
        FontWeight.w600,
        colorScheme.onSurface,
      ),
      assetTitle: role(
        textTheme.bodyLarge,
        FontWeight.w600,
        colorScheme.onSurface,
      ),
      assetValue: role(
        textTheme.bodyLarge,
        FontWeight.w500,
        colorScheme.onSurface,
      ),
      assetMeta: role(
        textTheme.bodySmall,
        FontWeight.w500,
        colors.textSecondary,
      ),
      brandHero: role(
        textTheme.displaySmall,
        FontWeight.w600,
        colors.onBrandArt,
      ),
      brandTitle: role(
        textTheme.titleMedium,
        FontWeight.w500,
        colors.onBrandArt,
      ),
      brandWordmark: role(
        textTheme.displaySmall,
        FontWeight.w600,
        colors.onBrandArt,
      ),
      brandAmount: role(
        textTheme.displaySmall,
        FontWeight.w500,
        colors.onBrandArt,
      ),
      brandMetric: role(
        textTheme.labelLarge,
        FontWeight.w600,
        colors.onBrandArt,
      ),
      brandBody: (textTheme.bodyLarge ?? const TextStyle()).copyWith(
        color: brandStrong,
      ),
      brandAction: role(textTheme.bodyLarge, FontWeight.w600, brandStrong),
      toastTitle: role(
        textTheme.bodyMedium,
        FontWeight.w600,
        colorScheme.onSurface,
      ),
      toastMessage: role(
        textTheme.bodySmall,
        FontWeight.w400,
        colors.textSecondary,
      ),
      badgeLabel: role(
        textTheme.labelSmall,
        FontWeight.w600,
        colorScheme.onSurface,
      ),
      supportingMeta: role(
        textTheme.bodySmall,
        FontWeight.w400,
        colors.textSecondary,
      ),
      errorMessage: role(
        textTheme.bodyMedium,
        FontWeight.w500,
        colors.textSecondary,
      ),
      versionLabel: role(
        textTheme.bodySmall,
        FontWeight.w400,
        colors.textSecondary,
      ),
      addressLabel: role(
        textTheme.bodyMedium,
        FontWeight.w600,
        colors.textSecondary,
      ),
      address: role(
        textTheme.bodyLarge,
        FontWeight.w500,
        colorScheme.onSurface,
      ),
      addressHint: role(
        textTheme.bodyLarge,
        FontWeight.w500,
        colors.textSecondary,
      ),
      addressSmall: role(
        textTheme.bodySmall,
        FontWeight.w500,
        colorScheme.onSurface,
      ),
      keypadNumber: role(
        textTheme.headlineSmall,
        FontWeight.w600,
        colorScheme.onSurface,
      ),
      marketLabel: role(
        textTheme.bodyMedium,
        FontWeight.w500,
        colors.onMarketTile,
      ),
      marketTitle: role(
        textTheme.titleLarge,
        FontWeight.w600,
        colors.onMarketTile,
      ),
      marketTip: role(
        textTheme.bodyMedium,
        FontWeight.w600,
        colors.onMarketTile,
      ),
      scanControl: role(
        textTheme.bodyMedium,
        FontWeight.w600,
        colors.onScan,
      ).copyWith(fontSize: 16, height: 1),
      scanCta: role(textTheme.bodyMedium, FontWeight.w500, scanSecondary),
      scanHeaderTitle: role(
        textTheme.bodyMedium,
        FontWeight.w600,
        colors.onScan,
      ),
      scanWalletId: role(textTheme.bodySmall, FontWeight.w400, scanSecondary),
    );
  }

  @override
  AsterTypeRoles copyWith({
    TextStyle? appBarTitle,
    TextStyle? pageTitle,
    TextStyle? buttonLabel,
    TextStyle? compactButtonLabel,
    TextStyle? sectionLabel,
    TextStyle? sectionTitle,
    TextStyle? title,
    TextStyle? rowTitle,
    TextStyle? rowTitleStrong,
    TextStyle? rowValue,
    TextStyle? rowMeta,
    TextStyle? rowMetaStrong,
    TextStyle? statusMessage,
    TextStyle? amountLarge,
    TextStyle? amountInline,
    TextStyle? assetTitle,
    TextStyle? assetValue,
    TextStyle? assetMeta,
    TextStyle? brandHero,
    TextStyle? brandTitle,
    TextStyle? brandWordmark,
    TextStyle? brandAmount,
    TextStyle? brandMetric,
    TextStyle? brandBody,
    TextStyle? brandAction,
    TextStyle? toastTitle,
    TextStyle? toastMessage,
    TextStyle? badgeLabel,
    TextStyle? supportingMeta,
    TextStyle? errorMessage,
    TextStyle? versionLabel,
    TextStyle? addressLabel,
    TextStyle? address,
    TextStyle? addressHint,
    TextStyle? addressSmall,
    TextStyle? keypadNumber,
    TextStyle? marketLabel,
    TextStyle? marketTitle,
    TextStyle? marketTip,
    TextStyle? scanControl,
    TextStyle? scanCta,
    TextStyle? scanHeaderTitle,
    TextStyle? scanWalletId,
  }) {
    return AsterTypeRoles(
      appBarTitle: appBarTitle ?? this.appBarTitle,
      pageTitle: pageTitle ?? this.pageTitle,
      buttonLabel: buttonLabel ?? this.buttonLabel,
      compactButtonLabel: compactButtonLabel ?? this.compactButtonLabel,
      sectionLabel: sectionLabel ?? this.sectionLabel,
      sectionTitle: sectionTitle ?? this.sectionTitle,
      title: title ?? this.title,
      rowTitle: rowTitle ?? this.rowTitle,
      rowTitleStrong: rowTitleStrong ?? this.rowTitleStrong,
      rowValue: rowValue ?? this.rowValue,
      rowMeta: rowMeta ?? this.rowMeta,
      rowMetaStrong: rowMetaStrong ?? this.rowMetaStrong,
      statusMessage: statusMessage ?? this.statusMessage,
      amountLarge: amountLarge ?? this.amountLarge,
      amountInline: amountInline ?? this.amountInline,
      assetTitle: assetTitle ?? this.assetTitle,
      assetValue: assetValue ?? this.assetValue,
      assetMeta: assetMeta ?? this.assetMeta,
      brandHero: brandHero ?? this.brandHero,
      brandTitle: brandTitle ?? this.brandTitle,
      brandWordmark: brandWordmark ?? this.brandWordmark,
      brandAmount: brandAmount ?? this.brandAmount,
      brandMetric: brandMetric ?? this.brandMetric,
      brandBody: brandBody ?? this.brandBody,
      brandAction: brandAction ?? this.brandAction,
      toastTitle: toastTitle ?? this.toastTitle,
      toastMessage: toastMessage ?? this.toastMessage,
      badgeLabel: badgeLabel ?? this.badgeLabel,
      supportingMeta: supportingMeta ?? this.supportingMeta,
      errorMessage: errorMessage ?? this.errorMessage,
      versionLabel: versionLabel ?? this.versionLabel,
      addressLabel: addressLabel ?? this.addressLabel,
      address: address ?? this.address,
      addressHint: addressHint ?? this.addressHint,
      addressSmall: addressSmall ?? this.addressSmall,
      keypadNumber: keypadNumber ?? this.keypadNumber,
      marketLabel: marketLabel ?? this.marketLabel,
      marketTitle: marketTitle ?? this.marketTitle,
      marketTip: marketTip ?? this.marketTip,
      scanControl: scanControl ?? this.scanControl,
      scanCta: scanCta ?? this.scanCta,
      scanHeaderTitle: scanHeaderTitle ?? this.scanHeaderTitle,
      scanWalletId: scanWalletId ?? this.scanWalletId,
    );
  }

  @override
  AsterTypeRoles lerp(ThemeExtension<AsterTypeRoles>? other, double t) {
    if (other is! AsterTypeRoles) return this;
    return AsterTypeRoles(
      appBarTitle: TextStyle.lerp(appBarTitle, other.appBarTitle, t)!,
      pageTitle: TextStyle.lerp(pageTitle, other.pageTitle, t)!,
      buttonLabel: TextStyle.lerp(buttonLabel, other.buttonLabel, t)!,
      compactButtonLabel: TextStyle.lerp(
        compactButtonLabel,
        other.compactButtonLabel,
        t,
      )!,
      sectionLabel: TextStyle.lerp(sectionLabel, other.sectionLabel, t)!,
      sectionTitle: TextStyle.lerp(sectionTitle, other.sectionTitle, t)!,
      title: TextStyle.lerp(title, other.title, t)!,
      rowTitle: TextStyle.lerp(rowTitle, other.rowTitle, t)!,
      rowTitleStrong: TextStyle.lerp(rowTitleStrong, other.rowTitleStrong, t)!,
      rowValue: TextStyle.lerp(rowValue, other.rowValue, t)!,
      rowMeta: TextStyle.lerp(rowMeta, other.rowMeta, t)!,
      rowMetaStrong: TextStyle.lerp(rowMetaStrong, other.rowMetaStrong, t)!,
      statusMessage: TextStyle.lerp(statusMessage, other.statusMessage, t)!,
      amountLarge: TextStyle.lerp(amountLarge, other.amountLarge, t)!,
      amountInline: TextStyle.lerp(amountInline, other.amountInline, t)!,
      assetTitle: TextStyle.lerp(assetTitle, other.assetTitle, t)!,
      assetValue: TextStyle.lerp(assetValue, other.assetValue, t)!,
      assetMeta: TextStyle.lerp(assetMeta, other.assetMeta, t)!,
      brandHero: TextStyle.lerp(brandHero, other.brandHero, t)!,
      brandTitle: TextStyle.lerp(brandTitle, other.brandTitle, t)!,
      brandWordmark: TextStyle.lerp(brandWordmark, other.brandWordmark, t)!,
      brandAmount: TextStyle.lerp(brandAmount, other.brandAmount, t)!,
      brandMetric: TextStyle.lerp(brandMetric, other.brandMetric, t)!,
      brandBody: TextStyle.lerp(brandBody, other.brandBody, t)!,
      brandAction: TextStyle.lerp(brandAction, other.brandAction, t)!,
      toastTitle: TextStyle.lerp(toastTitle, other.toastTitle, t)!,
      toastMessage: TextStyle.lerp(toastMessage, other.toastMessage, t)!,
      badgeLabel: TextStyle.lerp(badgeLabel, other.badgeLabel, t)!,
      supportingMeta: TextStyle.lerp(supportingMeta, other.supportingMeta, t)!,
      errorMessage: TextStyle.lerp(errorMessage, other.errorMessage, t)!,
      versionLabel: TextStyle.lerp(versionLabel, other.versionLabel, t)!,
      addressLabel: TextStyle.lerp(addressLabel, other.addressLabel, t)!,
      address: TextStyle.lerp(address, other.address, t)!,
      addressHint: TextStyle.lerp(addressHint, other.addressHint, t)!,
      addressSmall: TextStyle.lerp(addressSmall, other.addressSmall, t)!,
      keypadNumber: TextStyle.lerp(keypadNumber, other.keypadNumber, t)!,
      marketLabel: TextStyle.lerp(marketLabel, other.marketLabel, t)!,
      marketTitle: TextStyle.lerp(marketTitle, other.marketTitle, t)!,
      marketTip: TextStyle.lerp(marketTip, other.marketTip, t)!,
      scanControl: TextStyle.lerp(scanControl, other.scanControl, t)!,
      scanCta: TextStyle.lerp(scanCta, other.scanCta, t)!,
      scanHeaderTitle: TextStyle.lerp(
        scanHeaderTitle,
        other.scanHeaderTitle,
        t,
      )!,
      scanWalletId: TextStyle.lerp(scanWalletId, other.scanWalletId, t)!,
    );
  }
}
