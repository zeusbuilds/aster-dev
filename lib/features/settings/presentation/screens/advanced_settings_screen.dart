import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../shared/shared.dart';

/// Advanced wallet options, with sensitive disclosures gated by SEC-007.
class AdvancedSettingsScreen extends StatelessWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AsterNavigationScope(
      child: Builder(
        builder: (context) {
          final spacing = context.spacing;
          final navigation = AsterNavigationScope.of(context);
          return Scaffold(
            backgroundColor: context.colorScheme.surface,
            appBar: const CustomAppBar(
              title: 'Advanced',
              leadingIcon: true,
              fallbackLocation: RoutePaths.settings,
            ),
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
                        AsterOptionRow(
                          title: 'Export xpubs',
                          details: 'Unavailable',
                          prefixIcon: MingCuteIcons.mgc_key_2_line,
                          suffixIcon: MingCuteIcons.mgc_lock_line,
                        ),
                        const AsterDivider.inset(),
                        AsterOptionRow(
                          title: 'Check seed phrase',
                          details: 'Unavailable',
                          prefixIcon: MingCuteIcons.mgc_shield_line,
                          suffixIcon: MingCuteIcons.mgc_lock_line,
                        ),
                        const AsterDivider.inset(),
                        AsterOptionRow(
                          title: 'Network configuration',
                          prefixIcon: MingCuteIcons.mgc_route_line,
                          hapticIntent: null,
                          onTap: navigation.inFlight
                              ? null
                              : () => unawaited(
                                  navigation.openRoute(
                                    command: () => context.pushNamed<void>(
                                      RouteNames.networkConfiguration,
                                    ),
                                    failureTitle:
                                        'Network configuration could not open',
                                  ),
                                ),
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
        },
      ),
    );
  }
}
