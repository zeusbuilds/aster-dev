import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/errors.dart';
import '../../../../shared/shared.dart';
import '../models/models.dart';
import '../view_model/view_models.dart';

/// Displays validated, non-secret network configuration and live node health.
class NetworkConfigurationScreen extends ConsumerWidget {
  const NetworkConfigurationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configuration = ref.watch(networkConfigurationViewModelProvider);
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: const CustomAppBar(
        title: 'Network Configuration',
        leadingIcon: true,
      ),
      body: configuration.when(
        loading: () => const Center(child: GridLoader()),
        error: (error, _) => _NetworkLoadFailure(
          message: FailureMapper.from(error, StackTrace.current).userMessage,
          onRetry: () => ref.invalidate(networkConfigurationViewModelProvider),
        ),
        data: (state) => _NetworkConfigurationContent(state: state),
      ),
    );
  }
}

class _NetworkConfigurationContent extends ConsumerWidget {
  const _NetworkConfigurationContent({required this.state});

  final NetworkConfigurationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final configuration = state.configuration;
    final status = state.status;
    return SafeArea(
      top: false,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          spacing.screenPadding,
          spacing.lg,
          spacing.screenPadding,
          spacing.xxl,
        ),
        children: [
          _ConfigurationGroup(
            children: [
              _ConfigurationRow(
                label: 'Network',
                value: configuration.environment.name,
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
            ],
          ),
          SizedBox(height: spacing.xxl),
          Text('Node Health', style: context.type.sectionLabel),
          SizedBox(height: spacing.md),
          _ConfigurationGroup(
            children: [
              _ConfigurationRow(
                label: 'Status',
                value: status == null ? 'Unavailable' : 'Connected',
                valueColor: status == null
                    ? context.appColors.warning
                    : context.appColors.success,
              ),
              if (status != null) ...[
                _ConfigurationRow(
                  label: 'Block height',
                  value: status.blockHeight.toString(),
                ),
                _ConfigurationRow(
                  label: 'Channels',
                  value: '${status.usableChannelCount}/${status.channelCount}',
                ),
                _ConfigurationRow(
                  label: 'Peers',
                  value: status.peerCount.toString(),
                ),
              ],
            ],
          ),
          if (state.healthFailure != null) ...[
            SizedBox(height: spacing.lg),
            Text(
              state.healthFailure!.userMessage,
              style: context.type.errorMessage,
            ),
            SizedBox(height: spacing.md),
            CustomButton(
              text: 'Retry health check',
              variant: ButtonVariant.secondary,
              loading: state.refreshing,
              onTap: state.refreshing
                  ? null
                  : () => ref
                        .read(networkConfigurationViewModelProvider.notifier)
                        .retryHealth(),
            ),
          ],
        ],
      ),
    );
  }

  static String _publicEndpoint(String? raw) {
    if (raw == null) return 'Not configured';
    final withScheme = raw.contains('://') ? raw : 'tcp://$raw';
    final uri = Uri.parse(withScheme);
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
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
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label, $value',
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: context.spacing.md),
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

class _NetworkLoadFailure extends StatelessWidget {
  const _NetworkLoadFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(context.spacing.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: context.type.errorMessage,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: context.spacing.xxl),
            CustomButton(text: 'Retry', onTap: onRetry),
          ],
        ),
      ),
    );
  }
}
