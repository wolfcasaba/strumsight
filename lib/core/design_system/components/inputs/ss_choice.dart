import 'package:flutter/material.dart';

import '../../foundations/ss_semantics.dart';
import '../../foundations/ss_spacing.dart';

/// The three visual presentations [SsChoice] can render a single-select list
/// as (Ch13 §11.2): a segmented control for 2-3 short options, a [Wrap] of
/// chips for a longer or dynamically-sized list, and a radio list when each
/// option needs room for a longer label.
enum SsChoiceStyle { segmented, chip, radio }

/// One selectable value: a caller-supplied [label] paired with the
/// generic-typed [value] the caller matches on.
final class SsChoiceOption<T> {
  const SsChoiceOption({required this.value, required this.label});

  final T value;
  final String label;
}

/// A single-select choice control with three interchangeable presentations
/// (§3) driven by the same [SsChoiceOption] list — swapping [style] never
/// requires the caller to reshape its data.
final class SsChoice<T> extends StatelessWidget {
  const SsChoice({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.style = SsChoiceStyle.segmented,
  });

  final List<SsChoiceOption<T>> options;
  final T value;
  final ValueChanged<T>? onChanged;
  final SsChoiceStyle style;

  @override
  Widget build(BuildContext context) {
    return switch (style) {
      SsChoiceStyle.segmented => _buildSegmented(),
      SsChoiceStyle.chip => _buildChips(),
      SsChoiceStyle.radio => _buildRadios(context),
    };
  }

  Widget _buildSegmented() {
    return SegmentedButton<T>(
      segments: [
        for (final option in options)
          ButtonSegment<T>(value: option.value, label: Text(option.label)),
      ],
      selected: {value},
      onSelectionChanged: onChanged == null
          ? null
          : (selected) => onChanged!(selected.first),
    );
  }

  Widget _buildChips() {
    return Wrap(
      spacing: SsSpacing.space2,
      runSpacing: SsSpacing.space2,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(option.label),
            selected: option.value == value,
            onSelected: onChanged == null
                ? null
                : (_) => onChanged!(option.value),
          ),
      ],
    );
  }

  /// Each radio gets the same full-row touch target as [SsSwitchRow] (§5.4):
  /// the row's [InkWell] owns every tap, and the visible [Radio] never
  /// receives pointer events directly.
  Widget _buildRadios(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in options)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onChanged == null ? null : () => onChanged!(option.value),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: SsSemantics.minimumInteractiveDimension,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SsSpacing.space4,
                    vertical: SsSpacing.space2,
                  ),
                  child: MergeSemantics(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            option.label,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                        IgnorePointer(
                          ignoringSemantics: false,
                          child: Radio<T>(
                            value: option.value,
                            groupValue: value,
                            onChanged: onChanged == null ? null : (_) {},
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
