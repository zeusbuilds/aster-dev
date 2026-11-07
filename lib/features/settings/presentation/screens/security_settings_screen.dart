import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../core/errors/errors.dart';
import '../../../../core/security/device_authentication.dart';
import '../../../../core/security/security_controller.dart';
import '../../../../shared/shared.dart';

/// Device security preferences shared by every wallet in this installation.
class SecuritySettingsScreen extends ConsumerStatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  ConsumerState<SecuritySettingsScreen> createState() =>
      _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState
    extends ConsumerState<SecuritySettingsScreen> {
  bool _changing = false;

  Future<void> _changeLock(bool enabled) async {
    if (_changing) return;
    final controller = ref.read(securityControllerProvider);
    final toasts = context.toasts;
    setState(() => _changing = true);
    try {
      if (!enabled) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => const AsterConfirmationDialog(
            title: 'Turn off App lock?',
            content: Text(
              'Anyone using this device will be able to open Aster. '
              'Revealing your seed phrase and exporting keys will still '
              'require device authentication.',
            ),
            confirmText: 'Turn off',
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      await controller.setAppLockEnabled(enabled);
    } catch (error, stackTrace) {
      final failure = FailureMapper.from(error, stackTrace);
      toasts.show(
        title: 'Security setting not changed',
        message: failure.userMessage,
        variant: ToastVariant.failure,
      );
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(securityControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final secured = controller.deviceStatus == DeviceSecurityStatus.secured;
        final statusKnown = controller.deviceStatus != null;
        final enabled = secured && controller.appLockEnabled;
        final busy = _changing || controller.isAuthenticating;
        return Scaffold(
          backgroundColor: context.colorScheme.surface,
          appBar: const CustomAppBar(
            title: 'Security',
            leadingIcon: true,
            fallbackLocation: RoutePaths.settings,
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              context.spacing.screenPadding,
              context.spacing.lg,
              context.spacing.screenPadding,
              context.spacing.lg + context.windowInsets.bottomSafe,
            ),
            children: [
              Squircle(
                padding: EdgeInsets.symmetric(vertical: context.spacing.xs),
                child: Column(
                  children: [
                    AsterOptionRow.toggle(
                      key: const ValueKey('security-app-lock-switch'),
                      title: 'App lock',
                      prefixIcon: MingCuteIcons.mgc_lock_line,
                      value: enabled,
                      onChanged: secured && !busy
                          ? (value) => unawaited(_changeLock(value))
                          : null,
                    ),
                    const AsterDivider.inset(),
                    AsterOptionRow(
                      key: const ValueKey('security-lock-now'),
                      title: 'Lock now',
                      prefixIcon: MingCuteIcons.mgc_shield_line,
                      hapticIntent: null,
                      onTap: enabled && !busy ? controller.lock : null,
                    ),
                  ],
                ),
              ),
              SizedBox(height: context.spacing.xxl),
              Squircle(
                padding: EdgeInsets.symmetric(vertical: context.spacing.xs),
                child: AsterOptionRow(
                  title: 'Device screen lock',
                  details: !statusKnown
                      ? 'Unavailable'
                      : secured
                      ? 'On'
                      : 'Off',
                  prefixIcon: MingCuteIcons.mgc_cellphone_line,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
