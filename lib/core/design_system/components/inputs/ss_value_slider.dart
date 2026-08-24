import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../foundations/ss_spacing.dart';

/// Pairs a [Slider] with an exact numeric [TextField] for the SAME value
/// (§5.3) — tempo and duration need more precision than a thumb position can
/// reliably give (118 vs 120 BPM matters during practice).
///
/// Both inputs are fully controlled ([value] + [onChanged]) and funnel
/// through the SAME [_round] step before calling [onChanged] — that one
/// shared rounding, not two independently-tuned roundings, is what keeps
/// them in sync (§5.3). The randomized `slider_numeric_sync_test.dart`
/// drives both the [Slider]'s and the [TextField]'s own callback (D8/L446 —
/// through the actual widget API, not a copy of the rounding logic).
///
/// **NEM elfogadható gyengítés (§5.3):** a slider alone, "close enough" — or
/// the numeric field rounding differently than the slider, which the
/// property test is built to catch.
final class SsValueSlider extends StatefulWidget {
  const SsValueSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.fractionDigits = 0,
    this.unitLabel,
  }) : assert(min < max),
       assert(fractionDigits >= 0);

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  /// Decimal places both the slider and the numeric field round to — `0` for
  /// whole-number tempo, `1` for tenths-of-a-minute duration, and so on.
  final int fractionDigits;

  /// Also doubles as the numeric field's persistent label (§5.1) when set;
  /// falls back to [label] otherwise — the field is never left unlabelled.
  final String? unitLabel;

  @override
  State<SsValueSlider> createState() => _SsValueSliderState();
}

class _SsValueSliderState extends State<SsValueSlider> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant SsValueSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    final formatted = _format(widget.value);
    if (_controller.text != formatted && !_focusNode.hasFocus) {
      _controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  double _round(double raw) {
    final clamped = raw.clamp(widget.min, widget.max);
    final factor = math.pow(10, widget.fractionDigits);
    return (clamped * factor).round() / factor;
  }

  String _format(double value) =>
      _round(value).toStringAsFixed(widget.fractionDigits);

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) {
      _commitText(_controller.text);
    }
  }

  void _commitText(String text) {
    final parsed = double.tryParse(text);
    if (parsed == null) {
      _controller.text = _format(widget.value);
      return;
    }
    final rounded = _round(parsed);
    _controller.text = _format(rounded);
    widget.onChanged(rounded);
  }

  void _handleSliderChanged(double raw) {
    final rounded = _round(raw);
    _controller.text = _format(rounded);
    widget.onChanged(rounded);
  }

  @override
  Widget build(BuildContext context) {
    final displayValue = _round(widget.value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            const SizedBox(width: SsSpacing.space4),
            SizedBox(
              width: 96,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textAlign: TextAlign.end,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: widget.fractionDigits > 0,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: _commitText,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: widget.unitLabel ?? widget.label,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: displayValue,
          min: widget.min,
          max: widget.max,
          label: _format(displayValue),
          onChanged: _handleSliderChanged,
        ),
      ],
    );
  }
}
