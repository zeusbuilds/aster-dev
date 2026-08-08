import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_svg/flutter_svg.dart';

import '../../../../shared/shared.dart';

/// Card widget for entering recipient address
///
/// Displays address input field with paste/clear functionality.
/// Optionally accepts [controller] from parent (e.g. to set address from scan result).
class SendAddressCard extends StatefulWidget {
  /// Asset model for the send operation
  final AssetModel asset;

  /// Optional controller; if provided, parent owns it and can set text (e.g. from scan).
  final TextEditingController? controller;

  const SendAddressCard({super.key, required this.asset, this.controller});

  @override
  State<SendAddressCard> createState() => _SendAddressCardState();
}

class _SendAddressCardState extends State<SendAddressCard> {
  TextEditingController? _internalController;
  TextEditingController get _addressController =>
      widget.controller ?? _internalController!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _internalController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  void _clearAddress(BuildContext context) {
    _addressController.clear();
    setState(() {});
    unawaited(context.haptics.trigger(HapticIntent.lightImpact));
  }

  Future<void> _pasteAddress(BuildContext context) async {
    try {
      final clipboard = await Clipboard.getData('text/plain');
      if (!context.mounted) return;
      final value = clipboard?.text?.trim();
      if (value == null || value.isEmpty) {
        context.toasts.show(
          title: 'Clipboard is empty',
          variant: ToastVariant.info,
        );
        return;
      }
      _addressController.text = value;
      setState(() {});
      unawaited(context.haptics.trigger(HapticIntent.lightImpact));
    } catch (_) {
      if (!context.mounted) return;
      unawaited(context.haptics.trigger(HapticIntent.error));
      context.toasts.show(
        title: 'Could not read the clipboard',
        message: 'Enter the address manually and try again.',
        variant: ToastVariant.failure,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.spacing;
    final radius = context.radii;
    final type = context.type;
    final icons = context.icons;

    return Column(
      children: [
        Squircle(
          border: BorderRadius.only(
            topLeft: Radius.circular(radius.card),
            topRight: Radius.circular(radius.card),
          ),
          padding: EdgeInsets.symmetric(
            vertical: spacing.lg,
            horizontal: spacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recipient Address',
                style: type.addressLabel.copyWith(color: colors.textSecondary),
              ),
              SizedBox(height: spacing.xs),
              TextField(
                controller: _addressController,
                style: type.address,
                cursorColor: context.colorScheme.primary,
                minLines: 2,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText:
                      'bc1p5d7rjq7g6rdk2yhzks9smlaqtedr4dekq08ge8ztwac72sfr9rusxg3297',
                  hintStyle: type.addressHint,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                onChanged: (value) {
                  setState(() {});
                },
              ),
            ],
          ),
        ),
        Squircle(
          border: BorderRadius.only(
            bottomLeft: Radius.circular(radius.card),
            bottomRight: Radius.circular(radius.card),
          ),
          padding: EdgeInsets.symmetric(
            vertical: spacing.lg,
            horizontal: spacing.xl,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SvgPicture.asset(
                widget.asset.icon,
                height: icons.md,
                width: icons.md,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.circle,
                  size: icons.md,
                  color: AssetDisplay.colorOf(context, widget.asset),
                ),
              ),
              SizedBox(width: spacing.sm),
              Text(widget.asset.chain, style: type.rowTitleStrong),
              const Spacer(),
              Semantics(
                button: true,
                label: _addressController.text.isNotEmpty
                    ? 'Clear address'
                    : 'Paste address',
                excludeSemantics: true,
                child: Material(
                  color: colors.transparentSurface,
                  child: InkWell(
                    onTap: _addressController.text.isNotEmpty
                        ? () => _clearAddress(context)
                        : () => unawaited(_pasteAddress(context)),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: context.metrics.minTouchTarget,
                      ),
                      child: Center(
                        child: Squircle(
                          padding: EdgeInsets.symmetric(
                            horizontal: spacing.md,
                            vertical: spacing.xs,
                          ),
                          borderRadius: radius.badge,
                          borderColor: context.colorScheme.primaryContainer,
                          color: context.colorScheme.primaryContainer,
                          child: Text(
                            _addressController.text.isNotEmpty
                                ? 'clear'
                                : 'paste',
                            style: type.badgeLabel.copyWith(
                              color: context.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
