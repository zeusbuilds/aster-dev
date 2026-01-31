import 'route_paths.dart';

/// Route guard utilities
class RouteGuards {
  RouteGuards._();

  /// Routes that require authentication
  static const _protectedRoutes = [
    RoutePaths.send,
    RoutePaths.receive,
    RoutePaths.settings,
  ];

  /// Routes that require onboarding completion
  static const _onboardingRequiredRoutes = [
    RoutePaths.send,
    RoutePaths.receive,
  ];

  /// Checks if route requires authentication
  static bool requiresAuth(String location) {
    return _protectedRoutes.contains(location);
  }

  /// Checks if route requires onboarding
  static bool requiresOnboarding(String location) {
    return _onboardingRequiredRoutes.contains(location);
  }
}
