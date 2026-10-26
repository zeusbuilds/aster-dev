import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';

/// Accessible circular command used within the Scan frame control pill.
class ScanControlButton extends StatelessWidget {
  const ScanControlButton({
    super.key,
    required this.child,
    required this.semanticLabel,
    this.onTap,
    this.selected,
    this.value,
    this.loading = false,
    this.busy = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String semanticLabel;
  final bool? selected;
  final String? value;
  final bool loading;

  /// Silently guards a command without replacing or dimming its content.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final icons = context.icons;
    final metrics = context.metrics;
    final stateLayers = context.stateLayers;

    void activate() => onTap?.call();

    final enabled = onTap != null && !loading && !busy;

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: semanticLabel,
      value: value,
      onTap: enabled ? activate : null,
      excludeSemantics: true,
      child: Material(
        color: colors.transparentSurface,
        child: InkResponse(
          onTap: enabled ? activate : null,
          containedInkWell: true,
          highlightShape: BoxShape.circle,
          radius: metrics.minTouchTarget / 2,
          child: Opacity(
            opacity: enabled || loading || busy
                ? stateLayers.visible
                : stateLayers.disabled,
            child: SizedBox(
              width: metrics.minTouchTarget,
              height: metrics.minTouchTarget,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.scanControlSurface,
                  ),
                  child: SizedBox(
                    width: icons.md,
                    height: icons.md,
                    child: Center(
                      child: loading
                          ? GridLoader(
                              size: GridLoaderSize.small,
                              colorStyle: GridLoaderColorStyle.custom,
                              color: colors.onScan,
                            )
                          : child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
