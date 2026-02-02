import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_svg/flutter_svg.dart';

import 'package:aster/shared/shared.dart';

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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final radius = context.radius;
    final textTheme = context.textTheme;

    return Column(
      children: [
        Squircle(
          border: BorderRadius.only(
            topLeft: Radius.circular(radius.radius24),
            topRight: Radius.circular(radius.radius24),
          ),
          padding: EdgeInsets.symmetric(
            vertical: spacing.spacing16,
            horizontal: spacing.spacing18,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recipient Address',
                style: textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600, color: colors.text3)
                    .toNumeric(context),
              ),
              SizedBox(height: spacing.spacing4),
              TextField(
                controller: _addressController,
                style: textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w500, color: colors.text1)
                    .toNumeric(context),
                cursorColor: colors.brand6,
                minLines: 2,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText:
                      'bc1p5d7rjq7g6rdk2yhzks9smlaqtedr4dekq08ge8ztwac72sfr9rusxg3297',
                  hintStyle: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.text4,
                  ),
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
            bottomLeft: Radius.circular(radius.radius24),
            bottomRight: Radius.circular(radius.radius24),
          ),
          padding: EdgeInsets.symmetric(
            vertical: spacing.spacing16,
            horizontal: spacing.spacing18,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SvgPicture.asset(
                widget.asset.icon,
                height: spacing.spacing24,
                width: spacing.spacing24,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.circle,
                  size: spacing.spacing24,
                  color: Color(widget.asset.color),
                ),
              ),
              SizedBox(width: spacing.spacing8),
              Text(
                widget.asset.chain,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.text1,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _addressController.text.isNotEmpty
                    ? () {
                        setState(() {
                          _addressController.clear();
                        });
                      }
                    : () {
                        Clipboard.getData('text/plain').then((value) {
                          if (value != null && value.text != null) {
                            setState(() {
                              _addressController.text = value.text!;
                            });
                          }
                        });
                      },
                child: Squircle(
                  padding: EdgeInsets.symmetric(
                    horizontal: spacing.spacing12,
                    vertical: spacing.spacing4,
                  ),
                  borderRadius: radius.radius8,
                  borderColor: colors.brand1,
                  color: colors.brand1,
                  child: Text(
                    _addressController.text.isNotEmpty ? 'clear' : 'paste',
                    style: textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.brand6,
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
