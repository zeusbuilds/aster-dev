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
    link: SettingsExternalLink.contactSupport,
    title: 'Contact Support',
    icon: MingCuteIcons.mgc_lifebuoy_line,
  ),
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
  (
    link: SettingsExternalLink.twitter,
    title: 'Twitter',
    icon: MingCuteIcons.mgc_twitter_line,
  ),
  (
    link: SettingsExternalLink.telegram,
    title: 'Telegram',
    icon: MingCuteIcons.mgc_telegram_line,
  ),
  (
    link: SettingsExternalLink.instagram,
    title: 'Instagram',
    icon: MingCuteIcons.mgc_instagram_line,
  ),
];

/// Public-link group with explicit loading, disabled, and opening states.
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
    final configurationFailure = state?.linkConfigurationFailure;
    final rows = <Widget>[];
    for (var index = 0; index < _links.length; index++) {
      final descriptor = _links[index];
      final available = state?.isAvailable(descriptor.link) ?? false;
      final opening = openingLink == descriptor.link;
      final enabled = available && openingLink == null && !loading;
      rows.add(
        AsterOptionRow(
          key: ValueKey('settings-link-${descriptor.link.name}'),
          title: descriptor.title,
          details: loading
              ? 'Loading'
              : opening
              ? 'Opening'
              : available
              ? null
              : 'Unavailable',
          prefixIcon: descriptor.icon,
          onTap: enabled ? () => onOpen(descriptor.link) : null,
          hapticIntent: null,
        ),
      );
      if (index != _links.length - 1) {
        rows.add(const AsterDivider.inset());
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (configurationFailure != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              configurationFailure.userMessage,
              style: context.type.errorMessage,
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: context.spacing.md),
        ],
        Semantics(
          container: true,
          liveRegion: loading,
          label: loading ? 'Loading app information' : null,
          excludeSemantics: loading,
          child: Squircle(
            padding: EdgeInsets.symmetric(vertical: context.spacing.xs),
            child: Column(children: rows),
          ),
        ),
      ],
    );
  }
}
