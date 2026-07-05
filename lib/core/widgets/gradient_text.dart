import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Renders text filled with the brand gradient (#ED068A→#FE734C) — the web's
/// single most distinctive signature (`bg-clip-text text-transparent` on
/// virtually every heading + key number). Use for hero numbers and titles.
class GradientText extends StatelessWidget {
  const GradientText(
    this.text, {
    super.key,
    required this.style,
    this.gradient = AppColors.brandGradient,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle style;
  final Gradient gradient;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) => gradient.createShader(rect),
      blendMode: BlendMode.srcIn,
      child: Text(
        text,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        // White base so srcIn shows the gradient at full opacity.
        style: style.copyWith(color: Colors.white),
      ),
    );
  }
}
