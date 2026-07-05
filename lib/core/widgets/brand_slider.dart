import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// A [SliderTrackShape] that paints the active segment with the Music Theory
/// brand gradient (pink → orange) instead of a flat color.
///
/// The gradient is mapped across the ACTIVE portion (track start → thumb), so
/// every slider always shows the full pink→orange brand transition regardless
/// of its value — the brand spectrum is always visible, never "just pink".
class _GradientSliderTrackShape extends RoundedRectSliderTrackShape {
  const _GradientSliderTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (trackRect.isEmpty) return;

    final Radius radius = Radius.circular(trackRect.height / 2);

    // Inactive (right of thumb) — flat track color.
    final Paint inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? const Color(0xFFEFEFF4);
    final Rect inactiveRect = Rect.fromLTRB(
      thumbCenter.dx,
      trackRect.top,
      trackRect.right,
      trackRect.bottom,
    );
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(inactiveRect, radius),
      inactivePaint,
    );

    // Active (left of thumb) — brand gradient mapped across the active span so
    // the full pink→orange transition is always visible end-to-end.
    final Rect activeRect = Rect.fromLTRB(
      trackRect.left,
      trackRect.top,
      thumbCenter.dx,
      trackRect.bottom,
    );
    if (activeRect.width > 0) {
      final Paint activePaint = Paint()
        ..shader = AppColors.brandGradient.createShader(activeRect);
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(activeRect, radius),
        activePaint,
      );
    }
  }
}

/// Music Theory-branded slider: gradient active track + clean white thumb.
///
/// Drop-in replacement for [Slider] anywhere a value needs the brand spectrum.
/// Pass [activeLabel] color overrides only if you must; defaults match brand.
class BrandSlider extends StatelessWidget {
  const BrandSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.trackHeight = 6,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final int? divisions;
  final double trackHeight;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: trackHeight,
        trackShape: const _GradientSliderTrackShape(),
        inactiveTrackColor: p.track,
        // Thumb: clean white disc with a brand-tinted halo on press.
        thumbColor: Colors.white,
        thumbShape: const _BrandThumbShape(),
        overlayColor: AppColors.primary.withValues(alpha: 0.14),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
        // Discrete tick marks (when divisions set) in the brand color.
        activeTickMarkColor: Colors.white.withValues(alpha: 0.7),
        inactiveTickMarkColor: AppColors.primary.withValues(alpha: 0.25),
      ),
      child: Slider(
        value: value,
        onChanged: onChanged,
        min: min,
        max: max,
        divisions: divisions,
      ),
    );
  }
}

/// White thumb with a hairline brand ring + soft shadow — premium feel,
/// readable on top of the gradient track.
class _BrandThumbShape extends SliderComponentShape {
  const _BrandThumbShape();
  static const double radius = 11;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    // Soft drop shadow.
    canvas.drawCircle(
      center.translate(0, 1.5),
      radius,
      Paint()
        ..color = AppColors.primary.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // White disc.
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);
    // Brand ring.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..shader = AppColors.brandGradient.createShader(
          Rect.fromCircle(center: center, radius: radius),
        ),
    );
  }
}
