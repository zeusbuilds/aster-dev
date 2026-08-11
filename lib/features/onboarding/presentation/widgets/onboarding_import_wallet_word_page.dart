import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ming_cute_icons/ming_cute_icons.dart';

import '../../../../shared/shared.dart';
import '../../domain/models/models.dart';
import '../models/models.dart';

/// Four editable recovery-word fields in one carousel page.
class OnboardingImportWalletWordPage extends StatelessWidget {
  const OnboardingImportWalletWordPage({
    super.key,
    required this.controllers,
    required this.focusNodes,
    required this.statuses,
    required this.startIndex,
    required this.fieldHeight,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
  }) : assert(controllers.length == ImportWalletState.wordsPerPage),
       assert(focusNodes.length == ImportWalletState.wordsPerPage),
       assert(statuses.length == ImportWalletState.wordsPerPage),
       assert(fieldHeight > 0);

  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final List<MnemonicWordStatus> statuses;
  final int startIndex;
  final double fieldHeight;
  final bool enabled;
  final void Function(int index, String value) onChanged;
  final ValueChanged<int> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(ImportWalletState.wordsPerPage, (offset) {
          final index = startIndex + offset;
          return Padding(
            padding: EdgeInsets.only(
              bottom: offset < ImportWalletState.wordsPerPage - 1
                  ? spacing.md
                  : 0,
            ),
            child: _RecoveryWordField(
              controller: controllers[offset],
              focusNode: focusNodes[offset],
              index: index,
              status: statuses[offset],
              height: fieldHeight,
              enabled: enabled,
              onChanged: (value) => onChanged(index, value),
              onSubmitted: () => onSubmitted(index),
            ),
          );
        }),
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
    required this.height,
    required this.enabled,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int index;
  final MnemonicWordStatus status;
  final double height;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final effects = context.effects;
    final radii = context.radii;
    final strokes = context.strokes;
    final statusDescription = switch (status) {
      MnemonicWordStatus.empty => 'empty',
      MnemonicWordStatus.valid => 'valid word',
      MnemonicWordStatus.invalid => 'word not found',
    };
    final border = ShapedInputBorder(
      borderSide: BorderSide(
        color: context.colorScheme.surface.withValues(
          alpha: effects.brandGlassBorderOpacity,
        ),
        width: strokes.hairline,
      ),
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(radii.input),
      ),
    );
    final focusedBorder = ShapedInputBorder(
      borderSide: BorderSide(
        color: colors.onBrandArt,
        width: strokes.focusBorder,
      ),
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(radii.input),
      ),
    );

    return Semantics(
      label: 'Recovery word ${index + 1}',
      value: statusDescription,
      textField: true,
      child: SizedBox(
        height: height,
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
          textInputAction: index == ImportWalletState.wordCount - 1
              ? TextInputAction.done
              : TextInputAction.next,
          keyboardType: TextInputType.text,
          inputFormatters: const [_RecoveryPhraseInputFormatter()],
          style: context.type.assetValue.copyWith(color: colors.onBrandArt),
          cursorColor: colors.onBrandArt,
          decoration: InputDecoration(
            constraints: BoxConstraints(minHeight: height),
            filled: true,
            fillColor: context.colorScheme.surface.withValues(
              alpha: effects.brandGlassSurfaceOpacity,
            ),
            prefixIcon: Center(
              widthFactor: 1,
              child: Text(
                '${index + 1}.',
                style: context.type.assetMeta
                    .copyWith(
                      color: colors.onBrandArt.withValues(
                        alpha: effects.brandContentMutedOpacity,
                      ),
                    )
                    .toNumeric(context),
              ),
            ),
            suffixIcon: switch (status) {
              MnemonicWordStatus.empty => null,
              MnemonicWordStatus.valid => Icon(
                MingCuteIcons.mgc_check_fill,
                semanticLabel: 'Valid word',
                size: context.icons.sm,
                color: colors.success,
              ),
              MnemonicWordStatus.invalid => Icon(
                MingCuteIcons.mgc_close_fill,
                semanticLabel: 'Word not found',
                size: context.icons.sm,
                color: colors.danger,
              ),
            },
            border: border,
            enabledBorder: border,
            disabledBorder: border,
            focusedBorder: focusedBorder,
          ),
          onChanged: onChanged,
          onSubmitted: (_) => onSubmitted(),
        ),
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
