import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../routing/navigation_command_scope.dart';
import '../routing/route_paths.dart';
import '../theme/theme.dart';
import 'aster_icon_button.dart';

/// App bar with token-authored typography and safe root-deep-link navigation.
class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CustomAppBar({
    super.key,
    required this.title,
    this.leadingIcon = false,
    this.leadingEnabled = true,
    this.centerTitle = false,
    this.leadingIconData,
    this.action,
    this.onBack,
    this.automaticallyImplyLeading = true,
    this.fallbackLocation = RoutePaths.home,
  });

  final String title;
  final bool leadingIcon;

  /// Whether the rendered leading action may change routes.
  ///
  /// Mutation screens disable this while an uncancellable operation owns the
  /// current route, in addition to guarding system Back with [PopScope].
  final bool leadingEnabled;

  final bool centerTitle;
  final IconData? leadingIconData;
  final Widget? action;
  final VoidCallback? onBack;
  final bool automaticallyImplyLeading;

  /// Replacement destination used only when a root deep link has no page to
  /// pop. Flow screens should point this at their logical preceding step.
  final String fallbackLocation;

  @override
  Size get preferredSize =>
      Size.fromHeight(const AsterComponentMetrics().appBarHeight);

  @override
  Widget build(BuildContext context) {
    final icons = context.icons;
    final metrics = context.metrics;
    final hasScreenOwner = AsterNavigationScope.maybeOf(context) != null;

    Widget buildLeading(BuildContext context) {
      final navigation = AsterNavigationScope.of(context);

      void goBack() {
        unawaited(
          navigation.run(
            command: () {
              if (onBack case final handler?) {
                handler();
              } else if (context.canPop()) {
                context.pop();
              } else {
                context.go(fallbackLocation);
              }
            },
            failureTitle: 'Previous page could not open',
          ),
        );
      }

      return AsterIconButton(
        icon: leadingIconData ?? RemixIcons.arrow_left_s_line,
        tooltip: 'Back',
        onPressed: leadingEnabled && !navigation.inFlight ? goBack : null,
        hapticIntent: null,
        iconSize: icons.sm,
        alignment: Alignment.centerRight,
      );
    }

    return AppBar(
      automaticallyImplyLeading: automaticallyImplyLeading,
      toolbarHeight: metrics.appBarHeight,
      backgroundColor: context.colorScheme.surface,
      elevation: 0,
      centerTitle: centerTitle,
      title: Text(title, style: context.type.appBarTitle),
      leading: leadingIcon
          ? hasScreenOwner
                ? Builder(builder: buildLeading)
                : AsterNavigationScope(child: Builder(builder: buildLeading))
          : null,
      leadingWidth: metrics.appBarLeadingWidth,
      titleSpacing: leadingIcon
          ? context.spacing.xs
          : context.spacing.screenPadding,
      actions: action != null ? [action!] : null,
    );
  }
}
