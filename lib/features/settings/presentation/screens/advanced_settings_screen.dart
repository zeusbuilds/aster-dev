import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';
import 'package:remixicon/remixicon.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../controllers/wallet_disclosure_handoff.dart';

/// Advanced wallet options, with per-action authentication for disclosures.
class AdvancedSettingsScreen extends ConsumerStatefulWidget {
  const AdvancedSettingsScreen({
    super.key,
    this.embedded = false,
    this.onOpenNetworkConfiguration,
  });

  final bool embedded;
  final VoidCallback? onOpenNetworkConfiguration;

  @override
  ConsumerState<AdvancedSettingsScreen> createState() =>
      _AdvancedSettingsScreenState();
}

class _AdvancedSettingsScreenState
    extends ConsumerState<AdvancedSettingsScreen> {
  bool _openingDisclosure = false;

  Future<void> _openDisclosure(
    BuildContext context,
    SecurityPurpose purpose,
  ) async {
    bool sourceCurrent() =>
        mounted &&
        context.mounted &&
        ModalRoute.of(context)?.isCurrent == true &&
        (!widget.embedded || TickerMode.valuesOf(context).enabled);
    if (_openingDisclosure || !sourceCurrent()) return;
    setState(() => _openingDisclosure = true);
    final handoff = ref.read(walletDisclosureHandoffProvider);
    WalletDisclosureSession? session;
    try {
      session = await handoff.prepare(purpose, sourceCurrent: sourceCurrent);
      if (session == null ||
          !context.mounted ||
          !sourceCurrent() ||
          !session.valid) {
        return;
      }
      // The ready screen claims this process-local handoff. No grant or wallet
      // material enters navigation arguments, and no loading route is pushed.
      await context.pushNamed<void>(
        purpose == SecurityPurpose.revealSeed
            ? RouteNames.revealSeed
            : RouteNames.exportXpubs,
      );
    } catch (error, stackTrace) {
      if (context.mounted && sourceCurrent()) {
        final failure = FailureMapper.from(error, stackTrace);
        context.toasts.show(
          title: 'Wallet information unavailable',
          message: failure.userMessage,
          variant: ToastVariant.failure,
        );
      }
    } finally {
      if (session != null) handoff.discard(session);
      if (mounted) setState(() => _openingDisclosure = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = Builder(
      builder: (context) {
        final spacing = context.spacing;
        final navigation = AsterNavigationScope.of(context);
        return AsterPageScaffold(
          backgroundColor: context.colorScheme.surface,
          appBar: CustomAppBar(
            title: 'Advanced',
            leadingIcon: !widget.embedded,
            automaticallyImplyLeading: !widget.embedded,
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
                        suffixIcon: RemixIcons.arrow_right_s_line,
                        hapticIntent: null,
                        onTap: navigation.inFlight || _openingDisclosure
                            ? null
                            : () => unawaited(
                                navigation.openRoute(
                                  command: () => _openDisclosure(
                                    context,
                                    SecurityPurpose.exportXpubs,
                                  ),
                                  failureTitle: 'Export could not open',
                                ),
                              ),
                      ),
                      const AsterDivider.inset(),
                      AsterOptionRow(
                        title: 'Reveal seed phrase',
                        prefixIcon: MingCuteIcons.mgc_shield_line,
                        suffixIcon: RemixIcons.arrow_right_s_line,
                        hapticIntent: null,
                        onTap: navigation.inFlight || _openingDisclosure
                            ? null
                            : () => unawaited(
                                navigation.openRoute(
                                  command: () => _openDisclosure(
                                    context,
                                    SecurityPurpose.revealSeed,
                                  ),
                                  failureTitle: 'Seed phrase could not open',
                                ),
                              ),
                      ),
                      const AsterDivider.inset(),
                      AsterOptionRow(
                        title: 'Network configuration',
                        prefixIcon: MingCuteIcons.mgc_route_line,
                        suffixIcon: RemixIcons.arrow_right_s_line,
                        hapticIntent: null,
                        onTap: navigation.inFlight || _openingDisclosure
                            ? null
                            : widget.onOpenNetworkConfiguration ??
                                  () => unawaited(
                                    navigation.openRoute(
                                      command: () => context.pushNamed<void>(
                                        RouteNames.networkConfiguration,
                                      ),
                                      failureTitle: 'Network configuration could not open',
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
    );
    return widget.embedded ? screen : AsterNavigationScope(child: screen);
  }
}
