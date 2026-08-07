import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../shared/shared.dart';
import '../widgets/widgets.dart';

/// Screen for entering recipient address when sending Bitcoin
///
/// Displays address input field with QR code scanner option
class SendAddressScreen extends StatefulWidget {
  const SendAddressScreen({super.key});

  @override
  State<SendAddressScreen> createState() => _SendAddressScreenState();
}

class _SendAddressScreenState extends State<SendAddressScreen> {
  final TextEditingController _addressController = TextEditingController();

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _openScan(BuildContext context) async {
    final result = await context.push<String?>(RoutePaths.scan);
    if (result != null && mounted) {
      _addressController.text = result;
    }
  }

  @override
  Widget build(BuildContext context) {
    final icons = context.icons;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: context.colorScheme.surface,
        appBar: CustomAppBar(
          title: 'Send',
          leadingIcon: true,
          centerTitle: false,
          action: IconButton(
            onPressed: () async => _openScan(context),
            icon: Icon(
              MingCuteIcons.mgc_scan_line,
              size: icons.sm,
              color: context.colorScheme.onSurface,
            ),
          ),
        ),
        body: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.spacing.screenPadding,
          ),
          child: Column(
            children: [
              SendAddressCard(
                asset: AssetModel.bitcoin,
                controller: _addressController,
              ),
              const Spacer(),
              CustomButton(
                text: 'Continue',
                onTap: () async => context.pushNamed(RouteNames.send),
              ),
              SizedBox(height: context.spacing.bottomSafe(context)),
            ],
          ),
        ),
      ),
    );
  }
}
