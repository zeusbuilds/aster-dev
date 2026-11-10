import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../shared/shared.dart';
import '../providers/providers.dart';

const _destinations = <_NavDestination>[
  _NavDestination(
    label: 'Home',
    selectedIcon: MingCuteIcons.mgc_home_4_fill,
    icon: MingCuteIcons.mgc_home_4_line,
  ),
  _NavDestination(
    label: 'Scan',
    selectedIcon: MingCuteIcons.mgc_scan_fill,
    icon: MingCuteIcons.mgc_scan_line,
  ),
  _NavDestination(
    label: 'Market',
    selectedIcon: MingCuteIcons.mgc_copper_coin_fill,
    icon: MingCuteIcons.mgc_copper_coin_line,
  ),
  _NavDestination(
    label: 'Settings',
    selectedIcon: MingCuteIcons.mgc_settings_5_fill,
    icon: MingCuteIcons.mgc_settings_5_line,
  ),
];

/// Persistent four-destination navigation capsule.
class BottomNav extends ConsumerWidget {
  const BottomNav({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    assert(_destinations.length == appShellTabCount);
    final selectedIndex = ref.watch(appShellIndexProvider);
    final spacing = context.spacing;
    final metrics = context.metrics;
    final insets = context.windowInsets.systemPadding;
    final items = [
      for (var index = 0; index < _destinations.length; index += 1)
        Expanded(
          child: _NavItem(
            destination: _destinations[index],
            selected: selectedIndex == index,
            ordinal: index.toDouble(),
            onSelect: () =>
                ref.read(appShellIndexProvider.notifier).setIndex(index),
          ),
        ),
    ];
    if (CoverTabRail.boundsOf(context) case final bounds?) {
      return Positioned.fromRect(
        rect: bounds,
        child: _NavigationCapsule(
          axis: Axis.vertical,
          selectedIndex: selectedIndex,
          items: items,
        ),
      );
    }
    final availableWidth = math.max(
      0.0,
      MediaQuery.sizeOf(context).width - insets.horizontal - (spacing.xxl * 2),
    );
    final width = math.min(availableWidth, metrics.bottomNavMaxWidth);
    return Positioned(
      left: insets.left,
      right: insets.right,
      bottom: insets.bottom + spacing.sm,
      child: Center(
        child: SizedBox(
          width: width,
          height: metrics.bottomNavHeight,
          child: _NavigationCapsule(
            axis: Axis.horizontal,
            selectedIndex: selectedIndex,
            items: items,
          ),
        ),
      ),
    );
  }
}

class _NavigationCapsule extends StatelessWidget {
  const _NavigationCapsule({
    required this.axis,
    required this.selectedIndex,
    required this.items,
  });

  final Axis axis;
  final int selectedIndex;
  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    final metrics = context.metrics;
    const shape = StadiumBorder();
    final vertical = axis == Axis.vertical;
    final offset = _alignmentFor(selectedIndex, items.length);
    final fraction = 1 / items.length;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: context.appColors.surfaceRaised,
        shape: shape,
        shadows: context.shadows.raised,
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedAlign(
              alignment: vertical ? Alignment(0, offset) : Alignment(offset, 0),
              duration: context.motionPolicy.duration(
                context.motion.navIndicatorDuration,
              ),
              curve: context.motion.navIndicatorCurve,
              child: FractionallySizedBox(
                widthFactor: vertical ? null : fraction,
                heightFactor: vertical ? fraction : null,
                child: Center(
                  child: SizedBox(
                    key: const ValueKey('bottom-nav-indicator'),
                    width: vertical
                        ? metrics.bottomNavIndicatorHeight
                        : metrics.bottomNavIndicatorWidth,
                    height: metrics.bottomNavIndicatorHeight,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: context.appColors.surfaceRaised,
                        shape: shape,
                        shadows: context.shadows.raised,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Flex(direction: axis, children: items),
          ],
        ),
      ),
    );
  }
}

double _alignmentFor(int index, int count) {
  assert(count > 1);
  final boundedIndex = index.clamp(0, count - 1);
  return -1 + (2 * boundedIndex / (count - 1));
}

@immutable
final class _NavDestination {
  const _NavDestination({
    required this.label,
    required this.selectedIcon,
    required this.icon,
  });

  final String label;
  final IconData selectedIcon;
  final IconData icon;
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.ordinal,
    required this.onSelect,
  });

  final _NavDestination destination;
  final bool selected;
  final double ordinal;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    void select() {
      if (selected) return;
      unawaited(context.haptics.trigger(HapticIntent.selection));
      onSelect();
    }

    return Semantics(
      key: ValueKey('bottom-nav-${destination.label.toLowerCase()}'),
      button: true,
      selected: selected,
      enabled: true,
      label: destination.label,
      sortKey: OrdinalSortKey(ordinal),
      onTap: select,
      excludeSemantics: true,
      child: Material(
        color: context.appColors.transparentSurface,
        child: InkWell(
          onTap: select,
          child: Center(
            child: Icon(
              selected ? destination.selectedIcon : destination.icon,
              color: context.colorScheme.onSurface,
              size: context.icons.md,
            ),
          ),
        ),
      ),
    );
  }
}
