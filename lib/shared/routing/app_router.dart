import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../theme/theme.dart';
import '../widgets/custom_button.dart';
import 'route_config.dart';
import 'route_paths.dart';

part 'app_router.g.dart';

/// App router provider
@riverpod
GoRouter appRouter(Ref ref) {
  final router = GoRouter(
    initialLocation: RoutePaths.skeleton,
    routes: RouteConfig.getRoutes(),
    redirect: (context, state) {
      // Auth and onboarding guards will be implemented when auth feature is added
      return null;
    },
    errorBuilder: (context, state) => const ErrorScreen(),
    debugLogDiagnostics: false,
  );
  ref.onDispose(router.dispose);
  return router;
}

/// Error screen for route errors
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
            Text('Route Error', style: context.textTheme.headlineSmall),
            SizedBox(height: spacing.sm),
            Text(
              'This page is unavailable.',
              style: context.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: spacing.xxl),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.screenPadding),
              child: CustomButton(
                text: 'Go to Home',
                onTap: () => context.go(RoutePaths.skeleton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
