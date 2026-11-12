import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/send/presentation/models/models.dart';
import '../../features/send/presentation/view_model/view_models.dart';
import '../../features/shell/presentation/providers/app_shell_index_provider.dart';
import '../../features/wallet/domain/models/models.dart';
import '../../features/wallet/presentation/view_model/view_models.dart';
import '../feedback/toast_controller.dart';
import '../layout/layout.dart';
import '../theme/theme.dart';
import '../widgets/custom_button.dart';
import 'popup_feedback_observer.dart';
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
  final toasts = ref.read(toastControllerProvider.notifier);
  NavigatorObserver popupObserver() => PopupFeedbackObserver(
    discardMessages: toasts.discardMessagesForPopup,
    isActive: () => ref.mounted,
  );
  final router = GoRouter(
    initialLocation: RoutePaths.splash,
    routes: RouteConfig.getRoutes(popupObserverFactory: popupObserver),
    observers: [popupObserver()],
    refreshListenable: refresh,
    redirect: (context, state) =>
        RouteGuards.redirect(
          location: state.matchedLocation,
          walletState: ref.read(walletViewModelProvider),
        ) ??
        _paymentRedirect(ref, state),
    errorBuilder: (context, state) => const ErrorScreen(),
    debugLogDiagnostics: false,
  );
  void updateToastRouteScope() {
    final configuration = router.routerDelegate.currentConfiguration;
    // There is no screen owner until the first route is resolved. In
    // particular, a transient reported URL must not replace a pushed page's
    // authority when wallet state refreshes the router.
    if (configuration.isEmpty && !configuration.isError) return;
    final top = configuration.lastOrNull;
    toasts.updateRouteScope((
      top?.pageKey,
      top == null ? configuration.uri : router.state.uri,
      ref.read(appShellIndexProvider),
    ));
  }

  updateToastRouteScope();
  router.routerDelegate.addListener(updateToastRouteScope);
  ref.listen(appShellIndexProvider, (_, _) => updateToastRouteScope());
  ref.onDispose(
    () => router.routerDelegate.removeListener(updateToastRouteScope),
  );
  ref.onDispose(router.dispose);
  return router;
}

String? _paymentRedirect(Ref ref, GoRouterState state) {
  final fallback = switch (state.fullPath) {
    RoutePaths.sendAddress || RoutePaths.sendAmount => RoutePaths.send,
    RoutePaths.receiveRequest => RoutePaths.receive,
    _ => null,
  };
  if (fallback == null) return null;
  final target = WalletPaymentTarget.tryParse(
    state.pathParameters[RoutePaths.paymentTargetParameter],
  );
  if (target == null ||
      !ref
          .read(walletPaymentCapabilitiesProvider)
          .any((item) => item.target == target && item.isAvailable)) {
    return fallback;
  }
  // Only an available Send amount link may read the wallet flow.
  if (state.fullPath != RoutePaths.sendAmount) return null;
  final flow = ref.read(sendFlowViewModelProvider(target));
  final current = flow.value;
  if (flow.isLoading ||
      flow.hasError ||
      current?.hasValidatedDestination != true ||
      current?.balancePreparedForDestination != true ||
      current?.operation == SendFlowOperation.validatingDestination ||
      current?.operation == SendFlowOperation.preparingAmount ||
      current?.failureFor(SendFlowOperation.validatingDestination) != null ||
      current?.failureFor(SendFlowOperation.preparingAmount) != null) {
    return RoutePaths.sendAddressFor(target.slug);
  }
  return null;
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
    final bottomGap = context.isOpenDuoLandscape
        ? spacing.lg
        : spacing.screenPadding;
    final colors = context.appColors;
    final brightness = context.colorScheme.brightness;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: colors.transparentSurface,
        statusBarIconBrightness: brightness == Brightness.light
            ? Brightness.dark
            : Brightness.light,
        statusBarBrightness: brightness,
      ),
      child: Scaffold(
        body: AsterCenteredSafeArea(
          bottom: false,
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                spacing.screenPadding,
                spacing.screenPadding,
                spacing.screenPadding,
                bottomGap + context.windowInsets.bottomSafe,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: context.icons.xl,
                    color: colors.danger,
                  ),
                  SizedBox(height: spacing.lg),
                  Text(
                    'Page unavailable',
                    style: context.type.title,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: spacing.xxl),
                  CustomButton(
                    text: 'Go to Home',
                    onTap: () => context.go(RoutePaths.home),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
