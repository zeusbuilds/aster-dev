import 'package:flutter/material.dart';

import '../../../../shared/shared.dart';
import '../../domain/models/models.dart';
import 'wallet_asset_icon.dart';

/// Exact keypad-owned input, never rounded, ellipsized or text-scale limited.
///
/// A visible horizontal scrollbar exposes overflow without shifting the keypad
/// as digits are entered. Updates reveal the fractional tail; users can scroll
/// back to the prefix. The full value remains one accessible label.
class WalletAmountEntry extends StatefulWidget {
  const WalletAmountEntry({
    super.key,
    required this.value,
    required this.unit,
    required this.assetKind,
  });

  final String value;
  final String unit;
  final WalletAssetKind assetKind;

  @override
  State<WalletAmountEntry> createState() => _WalletAmountEntryState();
}

class _WalletAmountEntryState extends State<WalletAmountEntry> {
  final _scrollController = ScrollController();
  bool _revealScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _revealTail();
  }

  @override
  void didUpdateWidget(WalletAmountEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _revealTail();
  }

  void _revealTail() {
    if (_revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayed = widget.value.isEmpty ? '0' : widget.value;
    return Semantics(
      container: true,
      label: 'Amount, $displayed ${widget.unit}',
      child: Row(
        children: [
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.only(bottom: context.spacing.xs),
                child: ExcludeSemantics(
                  child: NumericText(
                    displayed,
                    style: context.type.amountLarge,
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: context.spacing.md),
          ExcludeSemantics(
            child: WalletAssetIcon(
              kind: widget.assetKind,
              size: context.icons.lg,
            ),
          ),
          SizedBox(width: context.spacing.sm),
          ExcludeSemantics(child: Text(widget.unit, style: context.type.title)),
        ],
      ),
    );
  }
}
