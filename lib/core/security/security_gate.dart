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
      return Stack(
        fit: StackFit.expand,
        children: [
          Offstage(
            offstage: blocked,
            child: TickerMode(
              enabled: !blocked,
              child: ExcludeSemantics(
                excluding: blocked,
                child: IgnorePointer(ignoring: blocked, child: child),
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

/// Shares the launch gradient/logo. Unlock controls appear only after cancel or
/// a failed check, or Lock now; automatic authentication keeps this frame quiet.
class AsterLockScreen extends StatelessWidget {
  const AsterLockScreen({required this.controller, super.key});
  final SecurityController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Stack(
      fit: StackFit.expand,
      children: [
        const ExcludeSemantics(child: SplashScreen()),
        if (controller.requiresUnlockAction &&
            controller.initialized &&
            controller.isLocked &&
            !controller.isAuthenticating &&
            !controller.isObscured)
          Positioned(
            left: context.spacing.screenPadding,
            right: context.spacing.screenPadding,
            bottom: context.windowInsets.bottomSafe + context.spacing.xxxl,
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    header: true,
                    container: true,
                    child: Text(
                      'Aster locked',
                      style: context.type.title.copyWith(
                        color: context.appColors.onBrandArt,
                      ),
                    ),
                  ),
                  if (controller.unlockError case final error?) ...[
                    SizedBox(height: context.spacing.sm),
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      style: context.type.supportingMeta.copyWith(
                        color: context.appColors.onBrandArt,
                      ),
                    ),
                  ],
                  SizedBox(height: context.spacing.xxl),
                  CustomButton(
                    text: 'Unlock',
                    variant: ButtonVariant.translucent,
                    onTap: () => unawaited(controller.unlock()),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
