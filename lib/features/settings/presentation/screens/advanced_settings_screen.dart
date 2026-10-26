import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../core/errors/errors.dart';
import '../../../../shared/shared.dart';

/// Advanced wallet options, with per-action authentication for disclosures.
class AdvancedSettingsScreen extends StatelessWidget {
  const AdvancedSettingsScreen({super.key});

  Future<void> _openDisclosure(BuildContext context, String route) async {
    final failure = await context.pushNamed<AppFailure>(route);
    if (failure == null ||
        !context.mounted ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    // The disclosure route owns its error result. Capture feedback only after
    // it returns: pushing/popping deliberately invalidates older toast scopes.
    context.toasts.show(
      title: 'Wallet information unavailable',
      message: failure.userMessage,
      variant: ToastVariant.failure,
    );
  }

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
              bottom: false,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  spacing.screenPadding,
                  spacing.lg,
                  spacing.screenPadding,
                  spacing.lg + context.windowInsets.bottomSafe,
                ),
                children: [
                  Squircle(
                    padding: EdgeInsets.symmetric(vertical: spacing.xs),
                    child: Column(
                      children: [
                        AsterOptionRow(
                          title: 'Export xpubs',
                          prefixIcon: MingCuteIcons.mgc_key_2_line,
                          hapticIntent: null,
                          onTap: navigation.inFlight
                              ? null
                              : () => unawaited(
                                  navigation.openRoute(
                                    command: () => _openDisclosure(
                                      context,
                                      RouteNames.exportXpubs,
                                    ),
                                    failureTitle: 'Export could not open',
                                  ),
                                ),
                        ),
                        const AsterDivider.inset(),
                        AsterOptionRow(
                          title: 'Reveal seed phrase',
                          prefixIcon: MingCuteIcons.mgc_shield_line,
                          hapticIntent: null,
                          onTap: navigation.inFlight
                              ? null
                              : () => unawaited(
                                  navigation.openRoute(
                                    command: () => _openDisclosure(
                                      context,
                                      RouteNames.revealSeed,
                                    ),
                                    failureTitle: 'Seed phrase could not open',
                                  ),
                                ),
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
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
