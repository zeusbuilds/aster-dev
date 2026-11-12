import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/errors/errors.dart';
import '../../../../shared/shared.dart';
import '../../domain/models/wallet_access_recovery.dart';

/// Shared blocking view for startup, wallet access and foreground recovery.
class WalletUnavailableScreen extends StatelessWidget {
  const WalletUnavailableScreen({
    super.key,
    required this.failure,
    required this.title,
    required this.retrying,
    this.onRetry,
  });

  final AppFailure failure;
  final String title;
  final bool retrying;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final bottomGap = context.isOpenDuoLandscape
        ? spacing.lg
        : spacing.screenPadding;
    final action = switch (WalletAccessRecovery.forFailure(failure)) {
      WalletAccessRecovery.retry => 'Retry',
      WalletAccessRecovery.finishRemoval => 'Finish removal',
      WalletAccessRecovery.openNextWallet => 'Open wallet',
      null => null,
    };
    final surface = context.colorScheme.surface;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: context.appColors.transparentSurface,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: surface,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Material(
        color: surface,
        child: AsterCenteredSafeArea(
          bottom: false,
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                spacing.screenPadding,
                spacing.screenPadding,
                spacing.screenPadding,
                bottomGap + context.windowInsets.bottomSafe,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    color: context.appColors.danger,
                    size: context.icons.xl,
                  ),
                  SizedBox(height: context.spacing.lg),
                  Text(
                    title,
                    style: context.type.title,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: context.spacing.sm),
                  Semantics(
                    container: true,
                    liveRegion: true,
                    label: failure.userMessage,
                    excludeSemantics: true,
                    child: Text(
                      failure.userMessage,
                      style: context.type.statusMessage,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (action != null && onRetry != null) ...[
                    SizedBox(height: context.spacing.xxl),
                    CustomButton(
                      text: action,
                      width: DuoDisplayLayout.landscapeOverlayMaxWidth(
                        MediaQuery.sizeOf(context),
                        spacing.xxl,
                      ),
                      loading: retrying,
                      hapticIntent: null,
                      onTap: onRetry,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
