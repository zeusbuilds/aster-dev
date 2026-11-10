import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../core/core.dart';
import '../../../../shared/shared.dart';
import '../../../shell/presentation/providers/app_shell_index_provider.dart';
import '../../../wallet/domain/models/models.dart';
import '../../../wallet/presentation/view_model/view_models.dart';

/// Reads only the active wallet's non-secret application profile.
class WalletDetailsScreen extends ConsumerStatefulWidget {
  const WalletDetailsScreen({super.key});

  @override
  ConsumerState<WalletDetailsScreen> createState() =>
      _WalletDetailsScreenState();
}

class _WalletDetailsScreenState extends ConsumerState<WalletDetailsScreen> {
  bool _confirming = false;
  bool _deleting = false;

  bool _ownsWallet(String id) {
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;
    final wallet = ref.read(walletViewModelProvider);
    return !wallet.isLoading &&
        !wallet.hasError &&
        wallet.value?.activeWallet?.id == id &&
        wallet.value?.isChangingWallet != true;
  }

  Future<void> _delete(WalletProfile profile, bool lastWallet) async {
    if (_confirming || _deleting || !_ownsWallet(profile.id)) return;
    setState(() => _confirming = true);
    final toasts = context.toasts;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AsterConfirmationDialog(
          title: 'Delete wallet?',
          content: Text(
            'Remove “${profile.name}” and its wallet data from this device. '
            'Keep your seed phrase safe. A seed phrase alone cannot restore '
            'USDT or other RGB assets. '
            '${lastWallet ? 'You will return to the welcome screen.' : 'Your other wallets will stay. Aster will open the next wallet.'}',
          ),
          confirmText: 'Delete',
        ),
      );
      if (confirmed != true || !_ownsWallet(profile.id)) return;
      setState(() => _deleting = true);
      final security = ref.read(securityControllerProvider);
      final authorization = await security.authorize(
        SecurityPurpose.deleteWallet,
        walletId: profile.id,
      );
      if (authorization == null || !_ownsWallet(profile.id)) return;
      final viewModel = ref.read(walletViewModelProvider.notifier);
      final deleted = await viewModel.deleteWallet(
        profile.id,
        authorization: authorization,
      );
      if (!mounted) return;
      if (deleted) {
        ref.read(appShellIndexProvider.notifier).setIndex(0);
        final hasWallet =
            ref.read(walletViewModelProvider).value?.activeWallet != null;
        context.goNamed(
          hasWallet ? RouteNames.home : RouteNames.onboardingWelcome,
        );
        return;
      }
      if (!_ownsWallet(profile.id)) return;
      final failure = ref.read(walletViewModelProvider).value?.operationFailure;
      if (failure != null) {
        toasts.show(
          title: 'Wallet not deleted',
          message: failure.userMessage,
          variant:
              failure.kind == AppFailureKind.validation ||
                  failure.kind == AppFailureKind.conflict
              ? ToastVariant.warning
              : ToastVariant.failure,
        );
        viewModel.clearOperationFailure();
      }
    } catch (error, stackTrace) {
      if (_ownsWallet(profile.id)) {
        toasts.show(
          title: 'Wallet not deleted',
          message: FailureMapper.from(error, stackTrace).userMessage,
          variant: ToastVariant.failure,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _confirming = false;
          _deleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletViewModelProvider);
    final isDuoCover =
        ref
            .watch(duoCoverLayoutProvider)
            .value
            ?.appliesTo(MediaQuery.sizeOf(context)) ==
        true;
    final profile = wallet.value?.activeWallet;
    final loading = wallet.isLoading || wallet.value?.switchingWalletId != null;
    final failure = wallet.hasError
        ? FailureMapper.from(
            wallet.error!,
            wallet.stackTrace ?? StackTrace.current,
          )
        : null;
    return PopScope(
      canPop: !_deleting,
      child: Scaffold(
        backgroundColor: context.colorScheme.surface,
        appBar: CustomAppBar(
          title: 'Wallet details',
          leadingIcon: true,
          leadingEnabled: !_deleting,
          fallbackLocation: RoutePaths.settings,
        ),
        body: AsterHorizontalSafeArea(
          child: loading
              ? const Center(
                  child: GridLoader(semanticLabel: 'Loading wallet details'),
                )
              : failure != null ||
                    profile == null ||
                    profile.state != WalletProfileState.ready
              ? _Unavailable(
                  onRetry:
                      failure?.retryable == true ||
                          (failure != null &&
                              WalletViewModel.canResumeDeletion(failure))
                      ? () => unawaited(
                          ref.read(walletViewModelProvider.notifier).reload(),
                        )
                      : null,
                )
              : Column(
                  children: [
                    Expanded(
                      child: _WalletDetails(
                        profile: profile,
                        footerOwnsBottomInset: isDuoCover,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        context.spacing.screenPadding,
                        context.spacing.lg,
                        context.spacing.screenPadding,
                        context.spacing.lg + context.windowInsets.bottomSafe,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final size = unwrappedSpanSize(
                            context,
                            TextSpan(
                              text: 'Delete wallet',
                              style: context.type.buttonLabel,
                            ),
                          );
                          final labelLines = size.width > constraints.maxWidth
                              ? 2
                              : 1;
                          return Theme(
                            data: Theme.of(context).copyWith(
                              extensions: [
                                ...Theme.of(context).extensions.values.where(
                                  (extension) =>
                                      extension is! AsterComponentMetrics &&
                                      extension is! AsterSpacing,
                                ),
                                context.metrics.copyWith(
                                  buttonHeight: math.max(
                                    context.metrics.buttonHeight,
                                    size.height * labelLines +
                                        context.spacing.sm * 2,
                                  ),
                                ),
                                context.spacing.copyWith(
                                  xxl: math.min(
                                    context.spacing.xxl,
                                    labelLines > 1
                                        ? context.spacing.xxl
                                        : math.max(
                                            0,
                                            (constraints.maxWidth -
                                                    size.width) /
                                                2,
                                          ),
                                  ),
                                ),
                              ],
                            ),
                            child: CustomButton(
                              key: const ValueKey('delete-wallet'),
                              text: 'Delete wallet',
                              labelMaxLines: labelLines,
                              variant: ButtonVariant.danger,
                              loading: _deleting,
                              enabled:
                                  !_confirming &&
                                  wallet.value?.isChangingWallet != true,
                              onTap: () => unawaited(
                                _delete(
                                  profile,
                                  wallet.value!.wallets.length == 1,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

final class _WalletDetails extends StatelessWidget {
  const _WalletDetails({
    required this.profile,
    required this.footerOwnsBottomInset,
  });

  final WalletProfile profile;
  final bool footerOwnsBottomInset;

  @override
  Widget build(BuildContext context) {
    final rows = [
      (label: 'Name', value: profile.name),
      (label: 'Wallet ID', value: profile.displayId),
      (
        label: 'Network',
        value: switch (profile.environment) {
          BlockchainEnvironment.mainnet => 'Mainnet',
          BlockchainEnvironment.signet =>
            profile.signetDeployment == SignetDeployment.utexoDev
                ? 'Dev Signet'
                : 'Signet',
          BlockchainEnvironment.regtest => 'Regtest',
        },
      ),
      (
        label: 'Added',
        value: DateFormat.yMMMd(Localizations.localeOf(context).toString())
            .format(profile.createdAt.toLocal()),
      ),
    ];
    return SafeArea(
      top: false,
      bottom: false,
      child: ListView.separated(
        padding: EdgeInsets.only(
          bottom:
              context.spacing.lg +
              (footerOwnsBottomInset ? 0 : context.windowInsets.bottomSafe),
        ),
        itemCount: rows.length,
        separatorBuilder: (context, index) => const AsterDivider.inset(),
        itemBuilder: (context, index) => Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.spacing.screenPadding,
            vertical: context.spacing.lg,
          ),
          child: Semantics(
            label: '${rows[index].label}, ${rows[index].value}',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(rows[index].label, style: context.type.rowMeta),
                SizedBox(height: context.spacing.xs),
                Text(rows[index].value, style: context.type.rowValue),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _Unavailable extends StatelessWidget {
  const _Unavailable({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          context.spacing.screenPadding,
          context.spacing.lg,
          context.spacing.screenPadding,
          context.spacing.lg + context.windowInsets.bottomSafe,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              MingCuteIcons.mgc_information_line,
              color: context.appColors.textSecondary,
              size: context.icons.xl,
            ),
            SizedBox(height: context.spacing.md),
            Semantics(
              liveRegion: true,
              child: Text(
                'Wallet unavailable',
                style: context.type.title,
                textAlign: TextAlign.center,
              ),
            ),
            if (onRetry != null) ...[
              SizedBox(height: context.spacing.lg),
              CustomButton(text: 'Retry', hapticIntent: null, onTap: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}
