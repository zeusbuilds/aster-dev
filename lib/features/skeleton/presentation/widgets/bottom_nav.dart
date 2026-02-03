import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../shared/shared.dart';
import '../providers/providers.dart';

/// Bottom navigation bar with animated selection indicator
///
/// Displays four navigation items with a smooth animated circle background
class BottomNav extends ConsumerStatefulWidget {
  const BottomNav({super.key});

  @override
  ConsumerState<BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends ConsumerState<BottomNav> {
  final List<GlobalKey> _itemKeys = [
    GlobalKey(),
    GlobalKey(),
    GlobalKey(),
    GlobalKey(),
  ];

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(skeletonIndexProvider);
    final spacing = context.spacing;
    final radius = context.radius;

    return Positioned(
      left: 0,
      right: 0,
      bottom: spacing.spacing24,
      child: Center(
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: spacing.spacing24),
          height: 56,
          padding: EdgeInsets.symmetric(horizontal: spacing.spacing12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius.radius30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                spreadRadius: 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRect(
            clipBehavior: Clip.none,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Circle behind the icons
                    _AnimatedCircle(
                      selectedIndex: index,
                      itemKeys: _itemKeys,
                      containerWidth: constraints.maxWidth,
                      containerHeight: 56,
                    ),
                    // Icons in front
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _NavItem(
                          key: _itemKeys[0],
                          icon: index == 0
                              ? MingCuteIcons.mgc_home_4_fill
                              : MingCuteIcons.mgc_home_4_line,
                          isSelected: index == 0,
                          onTap: () {
                            ref
                                .read(skeletonIndexProvider.notifier)
                                .setIndex(0);
                          },
                        ),
                        SizedBox(width: spacing.spacing20),
                        _NavItem(
                          key: _itemKeys[1],
                          icon: index == 1
                              ? MingCuteIcons.mgc_bank_card_fill
                              : MingCuteIcons.mgc_bank_card_line,
                          isSelected: index == 1,
                          onTap: () {
                            ref
                                .read(skeletonIndexProvider.notifier)
                                .setIndex(1);
                          },
                        ),
                        SizedBox(width: spacing.spacing20),
                        _NavItem(
                          key: _itemKeys[2],
                          icon: index == 2
                              ? MingCuteIcons.mgc_copper_coin_fill
                              : MingCuteIcons.mgc_copper_coin_line,
                          isSelected: index == 2,
                          onTap: () {
                            ref
                                .read(skeletonIndexProvider.notifier)
                                .setIndex(2);
                          },
                        ),
                        SizedBox(width: spacing.spacing20),
                        _NavItem(
                          key: _itemKeys[3],
                          icon: index == 3
                              ? MingCuteIcons.mgc_settings_5_fill
                              : MingCuteIcons.mgc_settings_5_line,
                          isSelected: index == 3,
                          onTap: () {
                            ref
                                .read(skeletonIndexProvider.notifier)
                                .setIndex(3);
                          },
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Individual navigation item in the bottom nav bar
class _NavItem extends StatelessWidget {
  /// Icon to display
  final IconData icon;

  /// Whether this item is currently selected
  final bool isSelected;

  /// Callback when item is tapped
  final VoidCallback onTap;

  const _NavItem({
    super.key,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return GestureDetector(
      onTapDown: (_) async {
        final canVibrate = await Haptics.canVibrate();
        if (canVibrate) {
          await Haptics.vibrate(HapticsType.selection);
        }
      },
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.spacing12,
          vertical: spacing.spacing12,
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.black, size: spacing.spacing24),
      ),
    );
  }
}

/// Animated circle background that moves behind the selected navigation item
///
/// Provides smooth animation when switching between navigation items
class _AnimatedCircle extends StatefulWidget {
  /// Currently selected navigation index
  final int selectedIndex;

  /// Global keys for each navigation item to calculate positions
  final List<GlobalKey> itemKeys;

  /// Width of the navigation container
  final double containerWidth;

  /// Height of the navigation container
  final double containerHeight;

  const _AnimatedCircle({
    required this.selectedIndex,
    required this.itemKeys,
    required this.containerWidth,
    required this.containerHeight,
  });

  @override
  State<_AnimatedCircle> createState() => _AnimatedCircleState();
}

class _AnimatedCircleState extends State<_AnimatedCircle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _currentPositionX = 0.0;
  double _targetPositionX = 0.0;
  double _currentPositionY = 0.0;
  double _targetPositionY = 0.0;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.fastOutSlowIn,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updatePosition(isInitial: true);
    });
  }

  @override
  void didUpdateWidget(_AnimatedCircle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex ||
        oldWidget.containerWidth != widget.containerWidth ||
        oldWidget.containerHeight != widget.containerHeight) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updatePosition();
      });
    }
  }

  /// Updates the position of the animated circle based on selected item
  ///
  /// Calculates the center position of the selected navigation item
  ///
  /// [isInitial] - Whether this is the initial position setup
  void _updatePosition({bool isInitial = false}) {
    final BuildContext? itemContext =
        widget.itemKeys[widget.selectedIndex].currentContext;
    if (itemContext == null) return;

    final RenderBox? itemBox = itemContext.findRenderObject() as RenderBox?;
    if (itemBox == null || !itemBox.hasSize) return;

    // Get the Stack's RenderBox by finding the parent of _AnimatedCircle
    final RenderBox? animatedCircleBox =
        context.findRenderObject() as RenderBox?;
    if (animatedCircleBox == null || !animatedCircleBox.hasSize) return;

    // Get the Stack (parent of animatedCircleBox)
    final RenderBox? stackBox = animatedCircleBox.parent as RenderBox?;
    if (stackBox == null || !stackBox.hasSize) return;

    // Get the item's center position in global coordinates
    final itemCenterGlobal = itemBox.localToGlobal(
      Offset(itemBox.size.width / 2, itemBox.size.height / 2),
    );

    // Convert to Stack's local coordinate system
    final itemCenterLocal = stackBox.globalToLocal(itemCenterGlobal);

    // Use both X and Y coordinates for proper centering
    final centerX = itemCenterLocal.dx;
    final centerY = itemCenterLocal.dy;

    setState(() {
      if (isInitial || !_isInitialized) {
        _currentPositionX = centerX;
        _targetPositionX = centerX;
        _currentPositionY = centerY;
        _targetPositionY = centerY;
        _isInitialized = true;
      } else {
        _currentPositionX = _targetPositionX;
        _targetPositionX = centerX;
        _currentPositionY = _targetPositionY;
        _targetPositionY = centerY;
        _controller.forward(from: 0.0);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const SizedBox.shrink();
    }

    final radius = context.radius;
    const double pillWidth = 56;
    const double pillHeight = 40;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final positionX =
            _currentPositionX +
            (_targetPositionX - _currentPositionX) * _animation.value;
        final positionY =
            _currentPositionY +
            (_targetPositionY - _currentPositionY) * _animation.value;
        return Positioned(
          left: positionX - pillWidth / 2,
          top: positionY - pillHeight / 2,
          child: Container(
            width: pillWidth,
            height: pillHeight,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(radius.radius50),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
