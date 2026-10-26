import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

import '../../../../shared/shared.dart';

/// One details value with optional app-owned copy behavior.
class TransactionDetailRow extends StatelessWidget {
  const TransactionDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.monetary = false,
    this.identifier = false,
    this.onCopy,
    this.copying = false,
    this.copyEnabled = true,
  }) : assert(!monetary || !identifier);

  final String label;
  final String value;

  /// Whether [value] is a monetary quantity rather than ordinary numeric text.
  final bool monetary;
  final bool identifier;
  final VoidCallback? onCopy;
  final bool copying;
  final bool copyEnabled;

  @override
  Widget build(BuildContext context) {
    final copy = onCopy;
    final content = Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: context.type.rowMeta)),
              if (copy != null)
                QuietPendingAction(
                  pending: !copyEnabled || copying,
                  label: 'Copy $label',
                  child: AsterIconButton(
                    icon: RemixIcons.file_copy_line,
                    tooltip: 'Copy $label',
                    hapticIntent: null,
                    onPressed: copy,
                  ),
                ),
            ],
          ),
          if (copy == null) SizedBox(height: context.spacing.xs),
          if (monetary)
            AmountText(
              value,
              style: context.type.rowValue,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            )
          else if (identifier)
            Text(
              value,
              style: context.type.addressSmall,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            )
          else
            NumericText(
              value,
              style: context.type.rowValue,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
    if (copy != null) {
      return Semantics(container: true, child: content);
    }
    return Semantics(
      label: '$label, $value',
      excludeSemantics: true,
      child: content,
    );
  }
}
