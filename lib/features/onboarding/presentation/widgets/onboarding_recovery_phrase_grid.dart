import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../../shared/shared.dart';
import '../../domain/models/models.dart';
import '../models/models.dart';

/// Displays a generated 12-word phrase as columns 1-6 and 7-12.
class OnboardingRecoveryPhraseGrid extends StatelessWidget {
  const OnboardingRecoveryPhraseGrid({
    super.key,
    required this.words,
    this.obscured = false,
    this.onBrandArt = false,
  }) : assert(words.length == wordCount);

  static const wordCount = 12;
  static const wordsPerColumn = 6;

  final List<String> words;

  /// Prevents phrase words from being painted or exposed to accessibility.
  final bool obscured;

  /// Uses a translucent field treatment over the onboarding artwork.
  final bool onBrandArt;

  @override
  Widget build(BuildContext context) {
    return _RecoveryPhraseGrid(
      rowSpacing: context.spacing.sm,
      itemBuilder: (index) => _RecoveryWordTile(
        index: index,
        word: words[index],
        obscured: obscured,
        onBrandArt: onBrandArt,
      ),
    );
  }
}

/// Editable counterpart to [OnboardingRecoveryPhraseGrid].
///
/// The visual grid follows the same column ordering as the read-only phrase,
/// while focus advances in mnemonic order from word 1 through word 12.
class OnboardingEditableRecoveryPhraseGrid extends StatelessWidget {
  const OnboardingEditableRecoveryPhraseGrid({
    super.key,
    required this.controllers,
    required this.focusNodes,
    required this.statuses,
    required this.enabled,
    this.onBrandArt = false,
    required this.onChanged,
    required this.onSubmitted,
  }) : assert(controllers.length == ImportWalletState.wordCount),
       assert(focusNodes.length == ImportWalletState.wordCount),
       assert(statuses.length == ImportWalletState.wordCount);

  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final List<MnemonicWordStatus> statuses;
  final bool enabled;
  final bool onBrandArt;
  final void Function(int index, String value) onChanged;
  final ValueChanged<int> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final style = context.type.rowTitle;
    final visibleHeight =
        MediaQuery.textScalerOf(context).scale(style.fontSize!) *
            (style.height ?? 1) +
        context.spacing.sm * 2;
    final fieldHeight = math.max(context.metrics.minTouchTarget, visibleHeight);
    final rowSpacing = math.max(
      context.spacing.none,
      context.spacing.sm - (fieldHeight - visibleHeight),
    );
    return _RecoveryPhraseGrid(
      rowSpacing: rowSpacing,
      itemBuilder: (index) => _RecoveryWordField(
        controller: controllers[index],
        focusNode: focusNodes[index],
        index: index,
        status: statuses[index],
        enabled: enabled,
        onBrandArt: onBrandArt,
        fieldHeight: fieldHeight,
        onChanged: (value) => onChanged(index, value),
        onSubmitted: () => onSubmitted(index),
      ),
    );
  }
}

class _RecoveryPhraseGrid extends StatelessWidget {
  const _RecoveryPhraseGrid({
    required this.rowSpacing,
    required this.itemBuilder,
  });

  final double rowSpacing;
  final Widget Function(int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(OnboardingRecoveryPhraseGrid.wordsPerColumn, (
        row,
      ) {
        final left = row;
        final right = row + OnboardingRecoveryPhraseGrid.wordsPerColumn;
        return Padding(
          padding: EdgeInsets.only(
            bottom: row < OnboardingRecoveryPhraseGrid.wordsPerColumn - 1
                ? rowSpacing
                : 0,
          ),
          child: Row(
            children: [
              Expanded(child: itemBuilder(left)),
              SizedBox(width: context.spacing.sm),
              Expanded(child: itemBuilder(right)),
            ],
          ),
        );
      }),
    );
  }
}

class _RecoveryWordTile extends StatelessWidget {
  const _RecoveryWordTile({
    required this.index,
    required this.word,
    required this.obscured,
    required this.onBrandArt,
  });

  final int index;
  final String word;
  final bool obscured;
  final bool onBrandArt;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      sortKey: OrdinalSortKey(index.toDouble()),
      label: obscured
          ? 'Recovery word ${index + 1}, hidden'
          : '${index + 1}. $word',
      excludeSemantics: true,
      child: _RecoveryWordSurface(
        key: ValueKey('recovery-word-display-tile-${index + 1}'),
        onBrandArt: onBrandArt,
        child: Row(
          children: [
            _RecoveryWordNumber(index: index),
            SizedBox(width: context.spacing.sm),
            Expanded(
              child: Text(
                obscured ? '••••••' : word,
                style: context.type.rowTitle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecoveryWordField extends StatelessWidget {
  const _RecoveryWordField({
    required this.controller,
    required this.focusNode,
    required this.index,
    required this.status,
    required this.enabled,
    required this.onBrandArt,
    required this.fieldHeight,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int index;
  final MnemonicWordStatus status;
  final bool enabled;
  final bool onBrandArt;
  final double fieldHeight;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final statusDescription = switch (status) {
      MnemonicWordStatus.empty => 'empty',
      MnemonicWordStatus.valid => 'valid word',
      MnemonicWordStatus.invalid => 'word not found',
    };
    final trailingFieldInset = math.max(
      context.spacing.none,
      context.radii.recoveryWord - context.spacing.md,
    );
    return MergeSemantics(
      child: Semantics(
        container: true,
        sortKey: OrdinalSortKey(index.toDouble()),
        label: 'Recovery word ${index + 1}',
        hint: statusDescription,
        child: SizedBox(
          key: ValueKey('recovery-word-entry-target-${index + 1}'),
          height: fieldHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? focusNode.requestFocus : null,
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: double.infinity,
                child: _RecoveryWordSurface(
                  key: ValueKey('recovery-word-entry-tile-${index + 1}'),
                  onBrandArt: onBrandArt,
                  status: status,
                  child: Row(
                    children: [
                      _RecoveryWordNumber(index: index),
                      SizedBox(width: context.spacing.sm),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsetsDirectional.only(
                            end: trailingFieldInset,
                          ),
                          child: TextField(
                            key: ValueKey('recovery-word-${index + 1}'),
                            controller: controller,
                            focusNode: focusNode,
                            readOnly: !enabled,
                            autocorrect: false,
                            enableSuggestions: false,
                            enableIMEPersonalizedLearning: false,
                            smartDashesType: SmartDashesType.disabled,
                            smartQuotesType: SmartQuotesType.disabled,
                            textCapitalization: TextCapitalization.none,
                            textInputAction:
                                index == ImportWalletState.wordCount - 1
                                ? TextInputAction.done
                                : TextInputAction.next,
                            keyboardType: TextInputType.text,
                            inputFormatters: const [
                              _RecoveryPhraseInputFormatter(),
                            ],
                            style: context.type.rowTitle,
                            cursorColor: context.colorScheme.primary,
                            textAlignVertical: TextAlignVertical.center,
                            decoration: const InputDecoration(
                              hintText: '',
                              isCollapsed: true,
                              contentPadding: EdgeInsets.zero,
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                            ),
                            onChanged: onChanged,
                            onSubmitted: (_) => onSubmitted(),
                            onTapOutside: (_) => focusNode.unfocus(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecoveryWordSurface extends StatelessWidget {
  const _RecoveryWordSurface({
    super.key,
    required this.onBrandArt,
    required this.child,
    this.status,
  });

  final bool onBrandArt;
  final Widget child;
  final MnemonicWordStatus? status;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final surface = onBrandArt
        ? context.colorScheme.surface.withValues(
            alpha: context.stateLayers.translucentSurface,
          )
        : colors.surfaceSubtle;
    final border = onBrandArt
        ? colors.onBrandArt.withValues(
            alpha: context.effects.brandGlassBorderOpacity,
          )
        : colors.borderSubtle;
    final statusProgress = switch (status) {
      null || MnemonicWordStatus.empty => 0.0,
      MnemonicWordStatus.valid => 1.0,
      MnemonicWordStatus.invalid => -1.0,
    };

    Widget buildSurface(double progress, Widget child) {
      final statusColor = progress >= 0 ? colors.success : colors.danger;
      final statusContainer = progress >= 0
          ? colors.successContainer
          : colors.dangerContainer;
      final emphasis = progress.abs();
      return Squircle(
        padding: EdgeInsets.symmetric(
          horizontal: context.spacing.md,
          vertical: context.spacing.sm,
        ),
        borderRadius: context.radii.recoveryWord,
        color: Color.lerp(surface, statusContainer, emphasis),
        borderColor: Color.lerp(border, statusColor, emphasis),
        borderWidth: context.strokes.hairline,
        child: child,
      );
    }

    if (status == null) return buildSurface(statusProgress, child);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: statusProgress),
      duration: context.motionPolicy.duration(
        context.motion.selectionTransitionDuration,
      ),
      curve: context.motion.fastEase,
      builder: (context, progress, child) => buildSurface(progress, child!),
      child: child,
    );
  }
}

class _RecoveryWordNumber extends StatelessWidget {
  const _RecoveryWordNumber({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Text(
        '${index + 1}.',
        style: context.type.assetMeta.toNumeric(context),
      ),
    );
  }
}

final class _RecoveryPhraseInputFormatter extends TextInputFormatter {
  const _RecoveryPhraseInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final lowercase = newValue.text.toLowerCase();
    final pastedWords = lowercase
        .split(RegExp(r'\s+'))
        .map(_normalizeWord)
        .where((word) => word.isNotEmpty)
        .take(ImportWalletState.wordCount)
        .toList(growable: false);
    if (pastedWords.length > 1) {
      final phrase = pastedWords.join(' ');
      return TextEditingValue(
        text: phrase,
        selection: TextSelection.collapsed(offset: phrase.length),
      );
    }

    final normalized = _normalizeWord(lowercase);
    final rawOffset = newValue.selection.end < 0
        ? lowercase.length
        : newValue.selection.end.clamp(0, lowercase.length);
    final normalizedBeforeSelection = _normalizeWord(
      lowercase.substring(0, rawOffset),
    );
    final selectionOffset = normalizedBeforeSelection.length < normalized.length
        ? normalizedBeforeSelection.length
        : normalized.length;
    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: selectionOffset),
      composing: TextRange.empty,
    );
  }

  static String _normalizeWord(String input) {
    final letters = input.replaceAll(RegExp('[^a-z]'), '');
    if (letters.length <= ImportWalletState.maximumWordCharacters) {
      return letters;
    }
    return letters.substring(0, ImportWalletState.maximumWordCharacters);
  }
}
