import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/wallet/presentation/view_model/wallet_view_model.dart';
import '../theme/theme.dart';
import '../widgets/custom_button.dart';
import 'route_config.dart';
import 'route_guards.dart';
import 'route_paths.dart';

part 'app_router.g.dart';

/// Owns one fail-closed router for the current provider container.
@riverpod
GoRouter appRouter(Ref ref) {
  final refresh = _RouterRefreshNotifier();
  ref.onDispose(refresh.dispose);
  ref.listen(walletViewModelProvider, (_, _) => refresh.notify());
  final router = GoRouter(
    initialLocation: RoutePaths.splash,
    routes: RouteConfig.getRoutes(),
    refreshListenable: refresh,
    redirect: (context, state) => RouteGuards.redirect(
      location: state.matchedLocation,
      walletState: ref.read(walletViewModelProvider),
    ),
    errorBuilder: (context, state) => const ErrorScreen(),
    debugLogDiagnostics: false,
  );
  ref.onDispose(router.dispose);
  return router;
}

final class _RouterRefreshNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Bounded recovery surface for malformed or unavailable locations.
class ErrorScreen extends StatelessWidget {
  const ErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Error')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: context.icons.xl,
              color: colors.danger,
            ),
            SizedBox(height: spacing.lg),
            Text('Route Error', style: context.type.title),
            SizedBox(height: spacing.sm),
            Text(
              'This page is unavailable.',
              style: context.type.statusMessage,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: spacing.xxl),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.screenPadding),
              child: CustomButton(
                text: 'Go to Home',
                onTap: () => context.go(RoutePaths.home),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
