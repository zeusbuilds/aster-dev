import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';

/// The last available wallet identity, without operational status or loaders.
class ScanWalletHeader extends StatelessWidget {
  const ScanWalletHeader({super.key, this.walletName, this.walletId});

  final String? walletName;
  final String? walletId;

  @override
  Widget build(BuildContext context) {
    final name = walletName;
    if (name == null) return const SizedBox.shrink();
    final id = walletId;
    return Semantics(
      container: true,
      label: id == null
          ? 'Active wallet, $name'
          : 'Active wallet, $name, ID $id',
      excludeSemantics: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            name,
            style: context.type.scanHeaderTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          if (id != null) ...[
            SizedBox(height: context.spacing.sm),
            Text(
              id,
              style: context.type.scanWalletId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
