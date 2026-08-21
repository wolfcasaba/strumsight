import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

void main() {
  test('spacing tokens contain the required 4dp grid threshold cells', () {
    expect(SsSpacing.values, containsAll(<double>[4, 8, 12, 16]));
    expect(SsSpacing.values, isNot(contains(2)));
    expect(
      SsSpacing.values.every((value) => value % SsSpacing.space1 == 0),
      isTrue,
    );
  });

  test('screen padding resolves to compact, medium, and expanded tokens', () {
    expect(SsSurface.screenPaddingForWidth(320), SsSpacing.space4);
    expect(SsSurface.screenPaddingForWidth(600), SsSpacing.space6);
    expect(SsSurface.screenPaddingForWidth(840), SsSpacing.space8);
  });

  test('surface primitives contain no raw spacing or radius literals', () {
    const sources = <String>[
      'lib/core/design_system/components/surfaces/ss_surface.dart',
      'lib/core/design_system/components/surfaces/ss_card.dart',
      'lib/core/design_system/components/surfaces/ss_hero_card.dart',
      'lib/core/design_system/components/surfaces/ss_section.dart',
    ];
    final rawInsets = RegExp(
      r'EdgeInsets\.(?:all|symmetric|only|fromLTRB)\s*\(\s*(?:\d|\.)',
    );
    final rawRadius = RegExp(r'BorderRadius\.circular\s*\(\s*(?:\d|\.)');

    for (final sourcePath in sources) {
      final source = File(sourcePath).readAsStringSync();
      expect(rawInsets.hasMatch(source), isFalse, reason: sourcePath);
      expect(rawRadius.hasMatch(source), isFalse, reason: sourcePath);
    }
  });
}
