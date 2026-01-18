import 'package:aster/features/send/presentation/widgets/widgets.dart';
import 'package:aster/shared/shared.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

/// Screen for entering recipient address when sending Bitcoin
/// Displays address input field with QR code scanner option
class SendAddressScreen extends StatelessWidget {
  const SendAddressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: context.colors.fill1,
        appBar: CustomAppBar(
          title: 'Send',
          leadingIcon: true,
          centerTitle: false,
          action: IconButton(
            onPressed: () {},
            icon: Icon(
              MingCuteIcons.mgc_scan_line,
              size: context.spacing.spacing20,
              color: context.colors.text1,
            ),
          ),
        ),
        body: Padding(
          padding: EdgeInsets.symmetric(horizontal: context.spacing.spacing20),
          child: Column(
            children: [
              SendAddressCard(asset: AssetModel.bitcoin),
              const Spacer(),
              CustomButton(
                text: 'Continue',
                onTap: () {
                  context.pushNamed(RouteNames.send);
                },
              ),
              SizedBox(height: context.spacing.bottomSafeHeightDynamic),
            ],
          ),
        ),
      ),
    );
  }
}
