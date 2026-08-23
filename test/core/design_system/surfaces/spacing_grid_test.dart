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

  test('surface primitive public APIs expose only fixed token spacing', () {
    for (final sourcePath in _surfaceSources) {
      final source = File(sourcePath).readAsStringSync();
      expect(
        RegExp(r'final double (?:padding|spacing)').hasMatch(source),
        isFalse,
        reason: sourcePath,
      );
      expect(
        RegExp(r'this\.(?:padding|spacing)').hasMatch(source),
        isFalse,
        reason: sourcePath,
      );
    }

    expect(
      File(
        'lib/core/design_system/components/surfaces/ss_card.dart',
      ).readAsStringSync(),
      contains('EdgeInsets.all(SsSpacing.space4)'),
    );
    expect(
      File(
        'lib/core/design_system/components/surfaces/ss_hero_card.dart',
      ).readAsStringSync(),
      contains('EdgeInsets.all(SsSpacing.space6)'),
    );
    expect(
      File(
        'lib/core/design_system/components/surfaces/ss_section.dart',
      ).readAsStringSync(),
      contains('SizedBox(height: SsSpacing.space2)'),
    );
  });

  test('surface primitive source contains no raw geometry literals', () {
    const sources = <String>[
      'lib/core/design_system/components/surfaces/ss_surface.dart',
      'lib/core/design_system/components/surfaces/ss_card.dart',
      'lib/core/design_system/components/surfaces/ss_hero_card.dart',
      'lib/core/design_system/components/surfaces/ss_section.dart',
    ];

    for (final sourcePath in sources) {
      final source = File(sourcePath).readAsStringSync();
      expect(_rawInsets.hasMatch(source), isFalse, reason: sourcePath);
      expect(_rawRadius.hasMatch(source), isFalse, reason: sourcePath);
    }
  });

  test('raw geometry guardian catches every production constructor shape', () {
    expect(_rawInsets.hasMatch('EdgeInsets.all(13)'), isTrue);
    expect(_rawInsets.hasMatch('EdgeInsets.only(left: 4)'), isTrue);
    expect(
      _rawInsets.hasMatch('EdgeInsetsDirectional.symmetric(horizontal: 8)'),
      isTrue,
    );
    expect(_rawRadius.hasMatch('Radius.circular(9)'), isTrue);
    expect(_rawRadius.hasMatch('BorderRadius.circular(9)'), isTrue);
    expect(_rawRadius.hasMatch('BorderRadius.all(Radius.circular(9))'), isTrue);
    expect(
      _rawRadius.hasMatch('BorderRadius.only(topLeft: Radius.circular(9))'),
      isTrue,
    );
  });
}

const List<String> _surfaceSources = <String>[
  'lib/core/design_system/components/surfaces/ss_surface.dart',
  'lib/core/design_system/components/surfaces/ss_card.dart',
  'lib/core/design_system/components/surfaces/ss_hero_card.dart',
  'lib/core/design_system/components/surfaces/ss_section.dart',
];

final RegExp _rawInsets = RegExp(
  r'(?:EdgeInsets|EdgeInsetsDirectional)\.(?:all|symmetric|only|fromLTRB)\s*\([^)]*\b\d',
);
final RegExp _rawRadius = RegExp(
  r'(?:Radius\.circular|BorderRadius\.circular)\s*\(\s*[-+]?(?:\d|\.)',
);
