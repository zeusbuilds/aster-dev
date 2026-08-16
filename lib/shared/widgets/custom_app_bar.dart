import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../routing/route_paths.dart';
import '../theme/theme.dart';
import 'aster_icon_button.dart';

/// App bar with token-authored typography and safe root-deep-link navigation.
class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  const CustomAppBar({
    super.key,
    required this.title,
    this.leadingIcon = false,
    this.centerTitle = true,
    this.leadingIconData,
    this.action,
    this.fallbackLocation = RoutePaths.home,
  });

  final String title;
  final bool leadingIcon;
  final bool centerTitle;
  final IconData? leadingIconData;
  final Widget? action;

  /// Replacement destination used only when a root deep link has no page to
  /// pop. Flow screens should point this at their logical preceding step.
  final String fallbackLocation;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final icons = context.icons;
    final metrics = context.metrics;

    void goBack() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(fallbackLocation);
      }
    }

    return AppBar(
      backgroundColor: context.colorScheme.surface,
      elevation: 0,
      centerTitle: centerTitle,
      title: Text(title, style: context.type.appBarTitle),
      leading: leadingIcon
          ? AsterIconButton(
              icon: leadingIconData ?? RemixIcons.arrow_left_s_line,
              tooltip: 'Back',
              onPressed: goBack,
              iconSize: icons.sm,
            )
          : null,
      leadingWidth: metrics.appBarLeadingWidth,
      actions: action != null ? [action!] : null,
    );
  }
}
