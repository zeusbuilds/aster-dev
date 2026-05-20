import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'route_config.dart';
import 'route_paths.dart';
import '../theme/theme.dart';

part 'app_router.g.dart';

/// App router provider
@riverpod
GoRouter appRouter(AppRouterRef ref) {
  return GoRouter(
    initialLocation: RoutePaths.skeleton,
    routes: RouteConfig.getRoutes(),
    redirect: (context, state) {
      // Auth and onboarding guards will be implemented when auth feature is added
      return null;
    },
    errorBuilder: (context, state) => ErrorScreen(error: state.error),
    debugLogDiagnostics: true,
  );
}

/// Error screen for route errors
class ErrorScreen extends StatelessWidget {
  const ErrorScreen({super.key, this.error});

  final Exception? error;

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
              size: spacing.giant,
              color: colors.danger,
            ),
            SizedBox(height: spacing.lg),
            Text(
              'Route Error',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (error != null) ...[
              SizedBox(height: spacing.sm),
              Text(
                error.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
            SizedBox(height: spacing.xxl),
            ElevatedButton(
              onPressed: () => context.go(RoutePaths.splash),
              child: const Text('Go to Home'),
            ),
          ],
        ),
      ),
    );
  }
}
