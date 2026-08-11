import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../shared/shared.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/models/models.dart';

/// Controlled destination field for the selected Send asset and rail.
class SendAddressCard extends StatelessWidget {
  const SendAddressCard({
    super.key,
    required this.target,
    required this.controller,
    required this.enabled,
    required this.onChanged,
    required this.onClear,
    required this.onPaste,
    this.failureMessage,
    this.pasting = false,
  });

  final WalletPaymentTarget target;
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onPaste;
  final String? failureMessage;
  final bool pasting;

  @override
  Widget build(BuildContext context) {
    final asset = target.assetModel;
    return Column(
      children: [
        Squircle(
          border: BorderRadius.only(
            topLeft: Radius.circular(context.radii.card),
            topRight: Radius.circular(context.radii.card),
          ),
          padding: EdgeInsets.symmetric(
            vertical: context.spacing.lg,
            horizontal: context.spacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                target.destinationLabel,
                style: context.type.addressLabel.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
              SizedBox(height: context.spacing.xs),
              TextField(
                controller: controller,
                enabled: enabled,
                style: context.type.address,
                cursorColor: context.colorScheme.primary,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: target.destinationHint,
                  hintStyle: context.type.addressHint,
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
                onChanged: onChanged,
              ),
              if (failureMessage case final message?) ...[
                SizedBox(height: context.spacing.sm),
                Text(
                  message,
                  style: context.type.errorMessage.copyWith(
                    color: context.appColors.danger,
                  ),
                ),
              ],
            ],
          ),
        ),
        Squircle(
          color: context.appColors.surfaceSubtle,
          borderColor: context.appColors.surfaceSubtle,
          border: BorderRadius.only(
            bottomLeft: Radius.circular(context.radii.card),
            bottomRight: Radius.circular(context.radii.card),
          ),
          padding: EdgeInsets.symmetric(
            vertical: context.spacing.sm,
            horizontal: context.spacing.xl,
          ),
          child: Row(
            children: [
              SvgPicture.asset(
                asset.icon,
                height: context.icons.md,
                width: context.icons.md,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.circle,
                  size: context.icons.md,
                  color: AssetDisplay.colorOf(context, asset),
                ),
              ),
              SizedBox(width: context.spacing.sm),
              Expanded(
                child: Text(
                  target.railLabel,
                  style: context.type.rowTitleStrong,
                ),
              ),
              CustomButton.compact(
                text: controller.text.isEmpty ? 'Paste' : 'Clear',
                loading: pasting,
                enabled: enabled,
                hapticIntent: controller.text.isEmpty
                    ? null
                    : HapticIntent.lightImpact,
                onTap: controller.text.isEmpty ? onPaste : onClear,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
