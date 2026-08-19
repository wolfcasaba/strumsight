import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/practice_generator/application/service/shadow_plan_generator.dart';

import '../fixtures/practice_planner/golden_profiles.dart';

int _seed() {
  final raw = Platform.environment['PROPERTY_SEED'];
  return raw == null ? 42 : int.parse(raw);
}

void main() {
  test('E07-R30 A2/A3/A4: seeded shadow generation is byte-identical and '
      'performs no persistent activation', () async {
    final rng = math.Random(_seed());
    final profiles = goldenProfiles();
    final generator = ShadowPlanGenerator();

    for (var trial = 0; trial < 80; trial++) {
      final profile = profiles[rng.nextInt(profiles.length)];
      final first = await generator.generate(profile.input);
      final second = await generator.generate(profile.input);

      expect(first.result, isA<Success>());
      expect(second.result, isA<Success>());
      expect(first.activationCalls, greaterThan(0));
      expect(second.activationCalls, greaterThan(0));
      expect(first.persistentWrites, isZero);
      expect(second.persistentWrites, isZero);
      expect(first.hardViolationCount, isZero);
      expect(second.hardViolationCount, isZero);
      expect(
        jsonEncode(first.result.valueOrNull!.toJson()),
        jsonEncode(second.result.valueOrNull!.toJson()),
        reason: 'trial $trial must preserve the exact serialized plan',
      );
    }
  });
}
