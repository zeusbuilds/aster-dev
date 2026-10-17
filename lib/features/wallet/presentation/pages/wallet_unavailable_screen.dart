import 'package:flutter/material.dart';

import '../../../../core/errors/errors.dart';
import '../../../../shared/shared.dart';

/// Full-screen, persistent wallet failure with an optional in-place retry.
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
    final canRetry = failure.retryable && onRetry != null;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              context.spacing.screenPadding,
              context.spacing.screenPadding,
              context.spacing.screenPadding,
              context.spacing.screenPadding + context.windowInsets.bottomSafe,
            ),
            child: Semantics(
              container: true,
              liveRegion: true,
              explicitChildNodes: true,
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
                  Text(
                    failure.userMessage,
                    style: context.type.statusMessage,
                    textAlign: TextAlign.center,
                  ),
                  if (canRetry) ...[
                    SizedBox(height: context.spacing.xxl),
                    CustomButton(
                      text: 'Retry',
                      loading: retrying,
                      enabled: !retrying,
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
