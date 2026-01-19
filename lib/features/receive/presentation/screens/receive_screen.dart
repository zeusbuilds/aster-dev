import 'package:aster/features/settings/presentation/widgets/widgets.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

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
    final colors = context.colors;
    final textTheme = context.textTheme;
    final radius = context.radius;

    return Scaffold(
      backgroundColor: colors.fill1,
      appBar: CustomAppBar(
        title: 'Receive Bitcoin',
        leadingIcon: true,
        centerTitle: false,
      ),
      body: SafeArea(
        bottom: true,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.spacing20),
          child: Column(
            children: [
              Squircle(
                borderRadius: radius.radius28,
                padding: EdgeInsets.all(spacing.spacing24),
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(spacing.spacing24),
                      child: PrettyQrView.data(
                        data: _address,
                        decoration: PrettyQrDecoration(
                          shape: PrettyQrDotsSymbol(color: colors.text1),
                          image: PrettyQrDecorationImage(
                            image: const AssetImage(
                              'assets/icons/images/bitcoin.png',
                            ),
                            padding: EdgeInsets.all(spacing.spacing16),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: spacing.spacing24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          MingCuteIcons.mgc_copy_2_line,
                          size: spacing.spacing20,
                          color: colors.text1,
                        ),
                        SizedBox(width: spacing.spacing4),
                        Expanded(
                          child: Text(
                            _address,
                            style: textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: colors.text1,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: spacing.spacing12),
                    Text(
                      'tap to copy',
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colors.text1,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              SizedBox(height: spacing.spacing24),
              Squircle(
                padding: EdgeInsets.symmetric(vertical: spacing.spacing4),
                child: Column(
                  children: [
                    SettingsOptionRow(
                      title: 'Set amount',
                      prefixIcon: MingCuteIcons.mgc_edit_2_line,
                    ),
                    Divider(
                      color: colors.fill2,
                      height: 1,
                      thickness: 1,
                      indent: spacing.spacing20,
                    ),
                    SettingsOptionRow(
                      title: 'Generate new address',
                      prefixIcon: MingCuteIcons.mgc_refresh_2_line,
                    ),
                    Divider(
                      color: colors.fill2,
                      height: 1,
                      thickness: 1,
                      indent: spacing.spacing20,
                    ),
                    SettingsOptionRow(
                      title: 'Direct Peg In',
                      prefixIcon: MingCuteIcons.mgc_selector_vertical_line,
                    ),
                    Divider(
                      color: colors.fill2,
                      height: 1,
                      thickness: 1,
                      indent: spacing.spacing20,
                    ),
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
