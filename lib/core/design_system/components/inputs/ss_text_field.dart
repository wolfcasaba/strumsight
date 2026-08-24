import 'package:flutter/material.dart';

/// A text field with a label that never disappears (§5.1).
///
/// [label] is rendered through [InputDecoration.labelText] with
/// [FloatingLabelBehavior.always] — floated above the input at all times,
/// even empty and unfocused — never through `hintText`, which vanishes as
/// soon as the user starts typing and leaves a screen-reader user with
/// nothing to associate the field with.
///
/// **NEM elfogadható gyengítés (§5.1):** only a `hintText`, "for a cleaner
/// look" — that makes the field unidentifiable once populated, both visually
/// and to a screen reader.
final class SsTextField extends StatelessWidget {
  const SsTextField({
    super.key,
    required this.label,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.obscureText = false,
    this.errorText,
    this.helperText,
    this.enabled = true,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final String? errorText;
  final String? helperText;
  final bool enabled;
  final int maxLines;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      obscureText: obscureText,
      enabled: enabled,
      maxLines: obscureText ? 1 : maxLines,
      textCapitalization: textCapitalization,
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        errorText: errorText,
        helperText: helperText,
        errorMaxLines: 3,
      ),
    );
  }
}
