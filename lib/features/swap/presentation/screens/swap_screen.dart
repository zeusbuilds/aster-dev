import 'package:flutter/material.dart';

import 'package:custom_numeric_pad/custom_numpad_package.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import 'package:aster/shared/shared.dart';
import '../widgets/widgets.dart';

/// Screen for swapping between different assets
///
/// Displays swap card, conversion rate, and transaction details with animations
class SwapScreen extends StatefulWidget {
  const SwapScreen({super.key});

  @override
  State<SwapScreen> createState() => _SwapScreenState();
}

class _SwapScreenState extends State<SwapScreen> with TickerProviderStateMixin {
  late AnimationController _detailsAnimationController;
  late AnimationController _detailsFadeOutController;
  late AnimationController _swapTextAnimationController;
  late List<Animation<double>> _detailAnimations;
  late Animation<double> _detailsFadeOutAnimation;
  late Animation<double> _swapTextFadeAnimation;
  bool _showDetails = false;
  bool _showKeyboard = true;

  final List<Map<String, String>> _detailRows = [
    {'title': 'SideSwap service fee', 'value': '\$0.0001'},
    {'title': 'SideSwap network fee', 'value': '\$0.0001'},
    {'title': 'Current Bitcoin rate', 'value': '7 sats/vbtye'},
    {'title': 'Liquid Network fee', 'value': '0.00000000002 BTC'},
    {'title': 'Current Liquid rate', 'value': '7 sats/vbtye'},
  ];

  @override
  void initState() {
    super.initState();

    // Details sequential animation
    _detailsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    // Details fade-out animation (for cancel - all at once)
    _detailsFadeOutController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Swap text fade-in animation (starts at 300ms, duration 400ms)
    _swapTextAnimationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Details fade-out animation
    _detailsFadeOutAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _detailsFadeOutController, curve: Curves.easeIn),
    );

    // Swap text fade animation
    _swapTextFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _swapTextAnimationController,
        curve: Curves.easeIn,
      ),
    );

    // Create staggered animations for each detail row
    _detailAnimations = List.generate(_detailRows.length, (index) {
      final delay = index * 0.15; // 150ms delay between each
      final start = delay.clamp(0.0, 1.0);
      final end = (delay + 0.85).clamp(0.0, 1.0);
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _detailsAnimationController,
          curve: Interval(start, end, curve: Curves.easeOutCubic),
        ),
      );
    });
  }

  @override
  void dispose() {
    _detailsAnimationController.dispose();
    _detailsFadeOutController.dispose();
    _swapTextAnimationController.dispose();
    super.dispose();
  }

  /// Handles continue button tap
  ///
  /// Hides keyboard, shows swap details with staggered animation, and displays cancel option
  void _onContinueTap() {
    // Dismiss keyboard with fade
    FocusScope.of(context).unfocus();

    // Phase 1: Remove keyboard from widget tree (AnimatedSwitcher will fade it out)
    // Duration: 0-300ms
    setState(() {
      _showKeyboard = false;
    });

    // Phase 2: Swap text becomes visible (takes space, but opacity 0)
    // This triggers AnimatedSize to grow the Column, smoothly moving button up
    // Duration: 300ms-700ms (400ms for AnimatedSize)
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        // Text is already in tree, AnimatedSize will grow Column
        // Then fade in the text
        _swapTextAnimationController.forward();
      }
    });

    // Phase 3: Show details with animation after keyboard fade completes
    // Duration: 300ms-1500ms
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        // Reset animations to start fresh
        _detailsAnimationController.reset();
        _detailsFadeOutController.reset();
        setState(() {
          _showDetails = true;
        });
        _detailsAnimationController.forward();
      }
    });
  }

  /// Handles cancel button tap
  ///
  /// Fades out details, hides cancel text, and shows keyboard again
  void _onCancelTap() {
    // Phase 1: Fade out all detail rows at once
    _detailsFadeOutController.forward().then((_) {
      if (mounted) {
        setState(() {
          _showDetails = false;
        });
        // Reset both animation controllers for next time
        _detailsAnimationController.reset();
        _detailsFadeOutController.reset();
      }
    });

    // Phase 2: Fade out cancel text (start slightly after details start fading)
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _swapTextAnimationController.reverse().then((_) {
          if (mounted) {
            // Phase 3: Show keyboard again
            setState(() {
              _showKeyboard = true;
            });
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colors = context.colors;
    final textTheme = context.textTheme;

    return Scaffold(
      backgroundColor: colors.fill1,
      appBar: CustomAppBar(
        title: 'Swap',
        leadingIcon: true,
        centerTitle: false,
      ),
      body: SafeArea(
        bottom: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: spacing.spacing20,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwapCard(),
                          SizedBox(height: spacing.spacing28),
                          Column(
                            children: [
                              DetailRow(
                                suffixIcon: MingCuteIcons.mgc_information_line,
                                title: 'Conversion rate',
                                value: '99.90%',
                              ),
                              if (_showDetails) ...[
                                SizedBox(height: spacing.spacing12),
                                ...List.generate(
                                  _detailRows.length,
                                  (index) => AnimatedBuilder(
                                    animation: Listenable.merge([
                                      _detailAnimations[index],
                                      _detailsFadeOutAnimation,
                                    ]),
                                    builder: (context, child) {
                                      // Combine both animations: staggered show and simultaneous fade-out
                                      final showOpacity =
                                          _detailAnimations[index].value;
                                      final fadeOutOpacity =
                                          _detailsFadeOutAnimation.value;
                                      final combinedOpacity =
                                          showOpacity * fadeOutOpacity;

                                      return Transform.translate(
                                        offset: Offset(
                                          (1 - _detailAnimations[index].value) *
                                              50,
                                          0,
                                        ),
                                        child: Opacity(
                                          opacity: combinedOpacity,
                                          child: child,
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        top: index > 0 ? spacing.spacing12 : 0,
                                      ),
                                      child: DetailRow(
                                        title: _detailRows[index]['title']!,
                                        value: _detailRows[index]['value']!,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          SizedBox(height: spacing.spacing18),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: spacing.spacing20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder:
                            (Widget child, Animation<double> animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: child,
                              );
                            },
                        child: _showKeyboard
                            ? CustomNumPad(
                                key: const ValueKey('keyboard'),
                                buttonWidth:
                                    (MediaQuery.of(context).size.width -
                                        spacing.spacing20 * 2 -
                                        80) /
                                    3,
                                buttonHeight: 60,
                                rowSpacing: spacing.spacing8,
                                columnSpacing: spacing.spacing8,
                                buttonColor: colors.fill2,
                                buttonTextStyle: textTheme.headlineSmall!
                                    .copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: colors.text1,
                                    )
                                    .toNumeric(context),
                              )
                            : const SizedBox.shrink(key: ValueKey('empty')),
                      ),
                      SizedBox(height: spacing.spacing18),
                      CustomButton(text: 'Continue', onTap: _onContinueTap),
                      // Animated height for text space (text height ~20 + padding 12 = ~32)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        height: !_showKeyboard ? 32 : 0,
                        child: !_showKeyboard
                            ? AnimatedBuilder(
                                animation: _swapTextFadeAnimation,
                                builder: (context, child) {
                                  return Opacity(
                                    opacity: _swapTextFadeAnimation.value,
                                    child: child,
                                  );
                                },
                                child: GestureDetector(
                                  onTap: _onCancelTap,
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      top: spacing.spacing12,
                                    ),
                                    child: Center(
                                      child: Text(
                                        'cancel',
                                        style: textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w500,
                                          color: colors.text1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
