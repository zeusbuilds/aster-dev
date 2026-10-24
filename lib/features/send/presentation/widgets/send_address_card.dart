import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../shared/shared.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/domain/validation/validation.dart';
import '../../../wallet/presentation/models/models.dart';
import '../../../wallet/presentation/widgets/widgets.dart';

/// Controlled destination field for the selected Send asset and rail.
class SendAddressCard extends StatelessWidget {
  SendAddressCard({
    super.key,
    required this.target,
    required TextEditingController controller,
    required this.enabled,
    required ValueChanged<String> onChanged,
    required VoidCallback onClear,
    required VoidCallback onPaste,
    required VoidCallback onSubmitted,
    this.pasting = false,
  }) : _behavior = _SendAddressCardBehavior(
         controller: controller,
         onChanged: onChanged,
         onClear: onClear,
         onPaste: onPaste,
         onSubmitted: onSubmitted,
       );

  /// Inert content skeleton with the same responsive geometry as the form.
  const SendAddressCard.loading({super.key, required this.target})
    : enabled = false,
      pasting = false,
      _behavior = null;

  final WalletPaymentTarget target;
  final bool enabled;
  final bool pasting;
  final _SendAddressCardBehavior? _behavior;

  @override
  Widget build(BuildContext context) {
    final input = _behavior?.controller;
    final hasValue = input?.text.isNotEmpty ?? false;
    final card = AsterSplitCard(
      tonalFooter: false,
      content: Column(
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
            controller: input,
            enabled: enabled,
            style: context.type.address,
            cursorColor: context.colorScheme.primary,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            inputFormatters: <TextInputFormatter>[
              LengthLimitingTextInputFormatter(
                WalletProtocolText.maximumEncodedCharacters,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
              ),
            ],
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
            onChanged: _behavior?.onChanged,
            onSubmitted: enabled
                ? (value) {
                    if (value.trim().isNotEmpty) {
                      _behavior?.onSubmitted();
                    }
                  }
                : null,
          ),
        ],
      ),
      footer: Row(
        children: [
          WalletAssetIcon(kind: target.assetKind, size: context.icons.md),
          SizedBox(width: context.spacing.sm),
          Expanded(
            child: Text(target.assetLabel, style: context.type.rowTitleStrong),
          ),
          CustomButton.compact(
            text: hasValue ? 'Clear' : 'Paste',
            variant: ButtonVariant.tonal,
            loading: pasting,
            enabled: enabled,
            hapticIntent: hasValue ? HapticIntent.lightImpact : null,
            onTap: hasValue ? _behavior?.onClear : _behavior?.onPaste,
          ),
        ],
      ),
    );
    if (_behavior != null) return card;
    return Semantics(
      liveRegion: true,
      label: 'Loading recipient form',
      excludeSemantics: true,
      child: AppSkeletonizer(enabled: true, child: card),
    );
  }
}

final class _SendAddressCardBehavior {
  const _SendAddressCardBehavior({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onPaste,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onPaste;
  final VoidCallback onSubmitted;
}
