import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../models/models.dart';
import '../view_model/view_models.dart';

/// Displays validated, non-secret network configuration and live node health.
class NetworkConfigurationScreen extends ConsumerWidget {
  const NetworkConfigurationScreen({
    super.key,
    this.onClose,
    this.showBack = true,
  });

  final VoidCallback? onClose;
  final bool showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(networkConfigurationViewModelProvider);
    final state = health.when(
      skipLoadingOnRefresh: false,
      loading: () => NetworkConfigurationState(
        configuration: ref.watch(walletServiceConfigurationProvider),
        refreshing: true,
      ),
      error: (error, stackTrace) => NetworkConfigurationState(
        configuration: ref.watch(walletServiceConfigurationProvider),
        healthFailure: FailureMapper.from(error, stackTrace),
      ),
      data: (state) => state,
    );
    return AsterPageScaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: CustomAppBar(
        title: 'Network Configuration',
        leadingIcon: showBack,
        automaticallyImplyLeading: showBack,
        onBack: onClose,
        fallbackLocation: RoutePaths.advancedSettingsLocation,
      ),
      body: _NetworkConfigurationContent(
        state: state,
        showRefreshControl: !health.isLoading,
        onRefresh: health.hasError
            ? () => ref.invalidate(networkConfigurationViewModelProvider)
            : () => ref
                  .read(networkConfigurationViewModelProvider.notifier)
                  .refreshHealth(),
      ),
    );
  }
}

class _NetworkConfigurationContent extends StatelessWidget {
  const _NetworkConfigurationContent({
    required this.state,
    required this.showRefreshControl,
    required this.onRefresh,
  });

  final NetworkConfigurationState state;
  final bool showRefreshControl;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final configuration = state.configuration;
    // Only a successful, completed check may present live node metrics.
    final status = state.healthFailure == null && !state.refreshing
        ? state.status
        : null;
    final healthFailure = state.healthFailure;
    return SafeArea(
      top: false,
      bottom: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          spacing.screenPadding,
          spacing.lg,
          spacing.screenPadding,
          (context.isOpenDuoLandscape ? spacing.lg : spacing.xxl) +
              context.windowInsets.bottomSafe,
        ),
        children: [
          _ConfigurationGroup(
            children: [
              _ConfigurationRow(
                label: 'Network',
                value: configuration.devBridgeEnabled
                    ? 'Dev Signet'
                    : configuration.environment.name,
              ),
              _ConfigurationRow(
                label: 'Indexer',
                value: _publicEndpoint(configuration.indexerUrl),
              ),
              _ConfigurationRow(
                label: 'RGB transport proxy',
                value: _publicEndpoint(configuration.rgbTransportProxy),
              ),
              _ConfigurationRow(
                label: 'LSP',
                value: _publicEndpoint(configuration.lspBaseUrl),
              ),
              _ConfigurationRow(
                label: 'VSS',
                value: _publicEndpoint(configuration.vssUrl),
              ),
              _ConfigurationRow(
                label: 'Ethereum validation RPC',
                value: _publicEndpoint(configuration.ethRpcUrl),
              ),
              _ConfigurationRow(
                label: 'Explorer',
                value: _publicEndpoint(configuration.explorerBaseUrl),
              ),
            ],
          ),
          SizedBox(height: spacing.xxl),
          Text('Node Health', style: context.type.sectionLabel),
          SizedBox(height: spacing.md),
          _ConfigurationGroup(
            children: [
              _ConfigurationRow(
                label: 'Status',
                value: state.refreshing
                    ? 'Checking'
                    : status == null
                    ? 'Unavailable'
                    : 'Responding',
                valueColor: context.appColors.statusForeground,
                announce: true,
              ),
              if (status != null) ...[
                _ConfigurationRow(
                  label: 'Block height',
                  value: status.blockHeight?.toString() ?? '—',
                ),
                if (status.channelCount != null &&
                    status.usableChannelCount != null)
                  _ConfigurationRow(
                    label: 'Channels',
                    value:
                        '${status.usableChannelCount}/${status.channelCount}',
                  ),
                if (status.peerCount != null)
                  _ConfigurationRow(
                    label: 'Peers',
                    value: status.peerCount.toString(),
                  ),
              ],
            ],
          ),
          if (showRefreshControl &&
              (state.refreshing ||
                  healthFailure?.retryable == true ||
                  (healthFailure == null && status != null))) ...[
            SizedBox(height: spacing.md),
            CustomButton(
              text: state.healthFailure == null
                  ? 'Refresh health'
                  : 'Retry health check',
              variant: ButtonVariant.secondary,
              loading: state.refreshing,
              hapticIntent: null,
              onTap: state.refreshing ? null : onRefresh,
            ),
          ],
        ],
      ),
    );
  }

  static String _publicEndpoint(String? raw) {
    if (raw == null) return 'Not configured';
    final withScheme = raw.contains('://') ? raw : 'tcp://$raw';
    return Uri.parse(withScheme).toString();
  }
}

class _ConfigurationGroup extends StatelessWidget {
  const _ConfigurationGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Squircle(
      padding: EdgeInsets.symmetric(
        horizontal: context.spacing.lg,
        vertical: context.spacing.xs,
      ),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index < children.length - 1) const AsterDivider(),
          ],
        ],
      ),
    );
  }
}

class _ConfigurationRow extends StatelessWidget {
  const _ConfigurationRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.announce = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool announce;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.spacing.md),
      child: Semantics(
        container: true,
        label: '$label, $value',
        liveRegion: announce,
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: context.type.rowMeta),
            SizedBox(height: context.spacing.xs),
            NumericText(
              value,
              style: context.type.rowValue.copyWith(color: valueColor),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
