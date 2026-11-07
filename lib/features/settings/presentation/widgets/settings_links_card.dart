import 'package:flutter/material.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../shared/shared.dart';
import '../../domain/models/models.dart';
import '../models/models.dart';

typedef _LinkDescriptor = ({
  SettingsExternalLink link,
  String title,
  IconData icon,
});

const _links = <_LinkDescriptor>[
  (
    link: SettingsExternalLink.termsOfService,
    title: 'Terms of Service',
    icon: MingCuteIcons.mgc_document_2_line,
  ),
  (
    link: SettingsExternalLink.privacyPolicy,
    title: 'Privacy Policy',
    icon: MingCuteIcons.mgc_file_check_line,
  ),
];

/// Public-link group with quiet, guarded external-page handoffs.
class SettingsLinksCard extends StatelessWidget {
  const SettingsLinksCard({
    super.key,
    required this.state,
    required this.loading,
    required this.onOpen,
  });

  /// Current public-link configuration and launch state.
  final SettingsAppState? state;

  /// Whether configuration is still resolving.
  final bool loading;

  /// Requests one available destination by semantic identity.
  final ValueChanged<SettingsExternalLink> onOpen;

  @override
  Widget build(BuildContext context) {
    final openingLink = state?.openingLink;
    final rows = <Widget>[];
    for (var index = 0; index < _links.length; index++) {
      final descriptor = _links[index];
      final available = state?.isAvailable(descriptor.link) ?? false;
      final enabled = available && !loading;
      rows.add(
        QuietPendingAction(
          pending: enabled && openingLink != null,
          label: descriptor.title,
          child: AsterOptionRow(
            key: ValueKey('settings-link-${descriptor.link.name}'),
            title: descriptor.title,
            prefixIcon: descriptor.icon,
            onTap: enabled ? () => onOpen(descriptor.link) : null,
            hapticIntent: null,
          ),
        ),
      );
      if (index != _links.length - 1) {
        rows.add(const AsterDivider.inset());
      }
    }

    return Squircle(
      padding: EdgeInsets.symmetric(vertical: context.spacing.xs),
      child: Column(children: rows),
    );
  }
}
