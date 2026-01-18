import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'route_config.dart';
import 'route_guards.dart';
import 'route_paths.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Error')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Route Error',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
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
