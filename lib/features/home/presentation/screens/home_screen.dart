import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/shared.dart';
import '../../../settings/presentation/view_model/view_models.dart';
import '../view_model/view_models.dart';
import '../widgets/widgets.dart';

/// Active-wallet overview with truthful market and cross-rail balance states.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeViewModelProvider);
    ref.watch(settingsViewModelProvider);
    final heroMinimumHeight =
        MediaQuery.sizeOf(context).height *
        context.metrics.homeHeroHeightFactor;
    final bottomContentInset =
        context.windowInsets.bottomSystem +
        context.spacing.sm +
        context.metrics.bottomNavHeight +
        context.spacing.xxl;

    Future<void> refresh() async {
      final homeNotifier = ref.read(homeViewModelProvider.notifier);
      if (ref.read(homeViewModelProvider).value == null) {
        await homeNotifier.retry();
        return;
      }
      if (ref.read(settingsViewModelProvider).value == null) {
        await ref.read(settingsViewModelProvider.notifier).retry();
        return;
      }
      final completed = await homeNotifier.refresh();
      if (!context.mounted || completed) return;
      final failure = ref.read(homeViewModelProvider).value?.refreshFailure;
      if (failure == null) return;
      context.toasts.show(
        title: 'Wallet refresh failed',
        message: failure.userMessage,
        variant: ToastVariant.failure,
      );
      homeNotifier.clearRefreshFailure();
    }

    return AsterNavigationScope(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: context.appColors.transparentSurface,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: context.colorScheme.surface,
          body: RefreshIndicator(
            onRefresh: refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: heroMinimumHeight),
                    child: ClipRect(
                      child: Stack(
                        fit: StackFit.passthrough,
                        children: [
                          const Positioned.fill(
                            child: MeshGradientBackground(),
                          ),
                          Padding(
                            padding: EdgeInsets.only(
                              top: context.windowInsets.topSystem,
                              bottom: context.spacing.lg,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const HomeHeader(),
                                const PriceCard(),
                                SizedBox(height: context.spacing.lg),
                                const HomeActionButtons(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: AssetsSection(home: home)),
                SliverToBoxAdapter(child: SizedBox(height: bottomContentInset)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
