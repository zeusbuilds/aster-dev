import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../models/models.dart';

/// Installed version without operational messages or manual recovery controls.
class SettingsVersionFooter extends StatelessWidget {
  const SettingsVersionFooter({super.key, required this.appInfo});

  /// Independent package-metadata state.
  final AsyncValue<SettingsAppState> appInfo;

  @override
  Widget build(BuildContext context) {
    final state = appInfo.value;
    final metadata = state?.metadata;
    final version = metadata == null
        ? '${AppConstants.appName} • Version —'
        : '${AppConstants.appName} • Version ${metadata.version}'
              '${metadata.buildNumber.isEmpty ? '' : ' • Build ${metadata.buildNumber}'}';

    return SizedBox(
      width: double.infinity,
      child: NumericText(
        version,
        key: const ValueKey('settings-version-label'),
        style: context.type.versionLabel,
        textAlign: TextAlign.center,
      ),
    );
  }
}
