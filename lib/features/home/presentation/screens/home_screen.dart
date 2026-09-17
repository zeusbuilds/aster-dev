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

    return AsterNavigationScope(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: context.appColors.transparentSurface,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: context.colorScheme.surface,
          body: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: heroMinimumHeight),
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.passthrough,
                      children: [
                        const Positioned.fill(child: MeshGradientBackground()),
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
    );
  }
}
