import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import 'gradient_text.dart';

/// Brand heading — Montserrat (the web's heading font), gradient-clipped by
/// default (mirrors the web `StyledHeader` / `.text-gradient-primary`).
class BrandHeading extends StatelessWidget {
  const BrandHeading(
    this.text, {
    super.key,
    this.size = 26,
    this.gradient = true,
  });

  final String text;
  final double size;
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'Montserrat',
      fontSize: size,
      fontWeight: FontWeight.w800,
      height: 1.1,
      letterSpacing: -0.5,
      color: gradient ? null : context.palette.ink,
    );
    return gradient
        ? GradientText(text, style: style)
        : Text(text, style: style);
  }
}
