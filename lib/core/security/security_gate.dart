import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/shared.dart';
import 'security_controller.dart';

/// Covers the complete route and toast trees, including semantics and input.
class SecurityGate extends StatelessWidget {
  const SecurityGate({
    required this.controller,
    required this.child,
    super.key,
  });
  final SecurityController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final blocked = controller.isLocked || controller.isObscured;
      // The OS owns interaction during authentication. Keep the originating
      // route painted (and its button animation running), without permitting
      // taps or accessibility actions behind the system sheet.
      final inert = blocked || controller.isAuthenticating;
      return Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: blocked,
            child: TickerMode(
              enabled: !blocked,
              child: ExcludeSemantics(
                excluding: inert,
                child: ExcludeFocus(
                  excluding: inert,
                  child: IgnorePointer(ignoring: inert, child: child),
                ),
              ),
            ),
          ),
          if (blocked)
            Positioned.fill(child: AsterLockScreen(controller: controller)),
        ],
      );
    },
  );
}

/// Shares the matching launch/lock artwork. Unlock controls appear only after
/// cancel or a failed check, or Lock now; automatic auth keeps this frame quiet.
class AsterLockScreen extends StatelessWidget {
  const AsterLockScreen({required this.controller, super.key});
  final SecurityController controller;

  @override
  Widget build(BuildContext context) => StreamBuilder<DuoDisplayLayout?>(
    stream: DuoDisplayLayout.platformUpdates,
    initialData: DuoDisplayLayout.currentPlatformLayout,
    builder: (context, snapshot) {
      final layout = snapshot.data;
      final viewport = MediaQuery.sizeOf(context);
      final useCompactBottom =
          layout != null &&
          ((layout.isCover && layout.appliesTo(viewport)) ||
              layout.isOpenLandscapeFor(viewport));
      return _buildLockScreen(useCompactBottom);
    },
  );

  Widget _buildLockScreen(bool useCompactBottom) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => BlockSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ExcludeSemantics(child: SplashScreen()),
          if (controller.requiresUnlockAction &&
              controller.initialized &&
              controller.isLocked &&
              !controller.isAuthenticating &&
              !controller.isObscured)
            Positioned(
              left:
                  context.windowInsets.systemPadding.left +
                  context.spacing.screenPadding,
              right:
                  context.windowInsets.systemPadding.right +
                  context.spacing.screenPadding,
              bottom:
                  context.windowInsets.bottomSafe +
                  (useCompactBottom
                      ? context.spacing.lg
                      : context.spacing.xxxl),
              child: Material(
                color: context.appColors.transparentSurface,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      container: true,
                      child: Text(
                        'Aster locked',
                        style: context.type.title.copyWith(
                          color: context.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (controller.unlockError case final error?) ...[
                      SizedBox(height: context.spacing.sm),
                      Text(
                        error,
                        textAlign: TextAlign.center,
                        style: context.type.supportingMeta.copyWith(
                          color: context.appColors.textSecondary,
                        ),
                      ),
                    ],
                    SizedBox(height: context.spacing.xxl),
                    CustomButton(
                      text: 'Unlock',
                      variant: ButtonVariant.primary,
                      onTap: () => unawaited(controller.unlock()),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
