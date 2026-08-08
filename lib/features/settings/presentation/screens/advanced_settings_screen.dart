import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../shared/shared.dart';
import '../widgets/widgets.dart';

/// Advanced wallet options, with sensitive disclosures gated by SEC-007.
class AdvancedSettingsScreen extends StatelessWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: const CustomAppBar(title: 'Advanced', leadingIcon: true),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.screenPadding,
            vertical: spacing.lg,
          ),
          children: [
            Squircle(
              padding: EdgeInsets.symmetric(vertical: spacing.xs),
              child: Column(
                children: [
                  SettingsOptionRow(
                    title: 'Export xpubs',
                    details: 'Unavailable',
                    prefixIcon: MingCuteIcons.mgc_key_2_line,
                    suffixIcon: MingCuteIcons.mgc_lock_line,
                  ),
                  const AsterDivider.inset(),
                  SettingsOptionRow(
                    title: 'Check seed phrase',
                    details: 'Unavailable',
                    prefixIcon: MingCuteIcons.mgc_shield_line,
                    suffixIcon: MingCuteIcons.mgc_lock_line,
                  ),
                  const AsterDivider.inset(),
                  SettingsOptionRow(
                    title: 'Network configuration',
                    prefixIcon: MingCuteIcons.mgc_route_line,
                    onTap: () =>
                        context.pushNamed(RouteNames.networkConfiguration),
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.lg),
            Text(
              'Sensitive wallet disclosures stay unavailable until an '
              'authentication policy is configured.',
              style: context.type.supportingMeta,
            ),
          ],
        ),
      ),
    );
  }
}
