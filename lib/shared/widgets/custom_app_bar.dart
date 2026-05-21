import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../theme/theme.dart';

/// Custom app bar widget with consistent styling
///
/// Provides a standardized app bar with title, optional leading icon for navigation,
/// and optional action widget. Supports custom title alignment and leading icon.
class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool leadingIcon;
  final bool centerTitle;
  final IconData? leadingIconData;
  final Widget? action;

  const CustomAppBar({
    super.key,
    required this.title,
    this.leadingIcon = false,
    this.centerTitle = true,
    this.leadingIconData,
    this.action,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final textTheme = context.textTheme;

    return AppBar(
      backgroundColor: context.colorScheme.surface,
      elevation: 0,
      centerTitle: centerTitle,
      title: Text(
        title,
        style: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: context.colorScheme.onSurface,
        ),
      ),
      leading: leadingIcon
          ? GestureDetector(
              onTap: () => context.pop(),
              child: Padding(
                padding: EdgeInsets.only(left: spacing.screenPadding),
                child: Icon(
                  leadingIconData ?? RemixIcons.arrow_left_s_line,
                  size: spacing.screenPadding,
                  color: context.colorScheme.onSurface,
                ),
              ),
            )
          : null,
      leadingWidth: spacing.iconXl,
      actions: action != null ? [action!] : null,
    );
  }
}
