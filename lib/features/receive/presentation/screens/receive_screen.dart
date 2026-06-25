import 'package:flutter/material.dart';

import 'package:ming_cute_icons/ming_cute_icons.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../../shared/shared.dart';
import '../../../settings/presentation/widgets/widgets.dart';

/// Screen for receiving Bitcoin
///
/// Displays QR code, address, and options for setting amount, generating new address, etc.
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final String _address =
      'bc1p5d7rjq7g6rdk2yhzks9smlaqtedr4dekq08ge8ztwac72sfr9rusxg3297';

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radii;
    final icons = context.icons;
    final type = context.type;

    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: CustomAppBar(
        title: 'Receive Bitcoin',
        leadingIcon: true,
        centerTitle: false,
      ),
      body: SafeArea(
        bottom: true,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.screenPadding),
          child: Column(
            children: [
              Squircle(
                borderRadius: radius.sheet,
                padding: EdgeInsets.all(spacing.xxl),
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(spacing.xxl),
                      child: PrettyQrView.data(
                        data: _address,
                        decoration: PrettyQrDecoration(
                          shape: PrettyQrDotsSymbol(
                            color: context.colorScheme.onSurface,
                          ),
                          image: PrettyQrDecorationImage(
                            image: const AssetImage(
                              'assets/icons/images/bitcoin.png',
                            ),
                            padding: EdgeInsets.all(spacing.lg),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: spacing.xxl),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          MingCuteIcons.mgc_copy_2_line,
                          size: icons.sm,
                          color: context.colorScheme.onSurface,
                        ),
                        SizedBox(width: spacing.xs),
                        Expanded(
                          child: Text(
                            _address,
                            style: type.addressSmall,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: spacing.md),
                    Text(
                      'tap to copy',
                      style: type.addressSmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing.xxl),
              Squircle(
                padding: EdgeInsets.symmetric(vertical: spacing.xs),
                child: Column(
                  children: [
                    SettingsOptionRow(
                      title: 'Set amount',
                      prefixIcon: MingCuteIcons.mgc_edit_2_line,
                    ),
                    const AsterDivider.inset(),
                    SettingsOptionRow(
                      title: 'Generate new address',
                      prefixIcon: MingCuteIcons.mgc_refresh_2_line,
                    ),
                    const AsterDivider.inset(),
                    SettingsOptionRow(
                      title: 'Direct Peg In',
                      prefixIcon: MingCuteIcons.mgc_selector_vertical_line,
                    ),
                    const AsterDivider.inset(),
                    SettingsOptionRow(
                      title: 'Share',
                      prefixIcon: MingCuteIcons.mgc_share_forward_line,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
