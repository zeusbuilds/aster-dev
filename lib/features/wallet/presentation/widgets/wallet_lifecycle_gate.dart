import 'package:flutter/material.dart';

import '../../../../core/errors/errors.dart';
import '../../../../shared/shared.dart';
import '../models/models.dart';
import '../pages/wallet_unavailable_screen.dart';

/// Excludes and blocks wallet UI while native lifecycle state is unresolved.
class WalletLifecycleGate extends StatelessWidget {
  const WalletLifecycleGate({
    super.key,
    required this.state,
    this.accessFailure,
    required this.onRetry,
    required this.child,
  });

  final WalletLifecycleState state;
  final AppFailure? accessFailure;
  final VoidCallback onRetry;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        TickerMode(
          enabled: !state.blocksInteraction,
          child: Offstage(
            offstage: state.blocksInteraction,
            child: ExcludeSemantics(
              excluding: state.blocksInteraction,
              child: IgnorePointer(
                ignoring: state.blocksInteraction,
                child: child,
              ),
            ),
          ),
        ),
        if (state.showsPrivacySplash)
          const Positioned.fill(child: SplashScreen())
        else if (state.showsFailure)
          Positioned.fill(
            child: WalletUnavailableScreen(
              title: 'Wallet could not be reopened',
              failure: state.recoveryFailure(accessFailure)!,
              retrying: state.transitioning,
              onRetry: onRetry,
            ),
          ),
      ],
    );
  }
}
