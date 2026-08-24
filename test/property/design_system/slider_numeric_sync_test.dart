import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

/// A3 (Ch13 §5.3): the slider and the exact numeric field of [SsValueSlider]
/// must ALWAYS agree, whichever side drove the change. Each trial fires the
/// widget's OWN bound callbacks (`Slider.onChanged`, `TextField.onSubmitted`)
/// — the actual controlling path, not a copy of the rounding rule under test
/// (D8/L446) — and every trial asserts on both callbacks (D8/L436: a branch
/// left unchecked is green only by luck of the seed). The invariant is exact
/// equality, not a tolerance or a percentage of trials (D8/L142).
void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;
  // ignore: avoid_print
  print('PROPERTY_SEED=$seed');

  testWidgets('the slider and the numeric field always report the same value, '
      'driven from either side, across randomized trials', (tester) async {
    final random = math.Random(seed);
    const min = 40.0;
    const max = 220.0;
    var current = 120.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SsValueSlider(
                label: 'Tempo',
                value: current,
                min: min,
                max: max,
                unitLabel: 'BPM',
                onChanged: (v) => setState(() => current = v),
              );
            },
          ),
        ),
      ),
    );

    for (var trial = 0; trial < 100; trial++) {
      // --- Drive through the SLIDER's own bound callback. ---
      final sliderTarget = min + random.nextDouble() * (max - min);
      final expectedFromSlider = sliderTarget.roundToDouble();

      tester.widget<Slider>(find.byType(Slider)).onChanged!(sliderTarget);
      await tester.pump();

      expect(
        tester.widget<Slider>(find.byType(Slider)).value,
        expectedFromSlider,
        reason:
            'seed=$seed trial=$trial sliderTarget=$sliderTarget '
            '(slider onChanged -> slider value)',
      );
      expect(
        double.parse(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
        ),
        expectedFromSlider,
        reason:
            'seed=$seed trial=$trial sliderTarget=$sliderTarget '
            '(slider onChanged -> numeric field)',
      );

      // --- Drive through the numeric FIELD's own bound callback. ---
      final textTarget = min.round() + random.nextInt((max - min).round() + 1);

      tester.widget<TextField>(find.byType(TextField)).onSubmitted!(
        '$textTarget',
      );
      await tester.pump();

      expect(
        tester.widget<Slider>(find.byType(Slider)).value,
        textTarget.toDouble(),
        reason:
            'seed=$seed trial=$trial textTarget=$textTarget '
            '(field onSubmitted -> slider value)',
      );
      expect(
        double.parse(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
        ),
        textTarget.toDouble(),
        reason:
            'seed=$seed trial=$trial textTarget=$textTarget '
            '(field onSubmitted -> numeric field)',
      );
    }
  });
}
