import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/application/vision_cadence_policy.dart';

void main() {
  const policy = VisionCadencePolicy();

  group('VisionCadencePolicy thermal matrix', () {
    for (final entry in <int, VisionCadence>{
      0: VisionCadence.full,
      39: VisionCadence.full,
      40: VisionCadence.reduced,
      79: VisionCadence.reduced,
      80: VisionCadence.audioOnly,
      100: VisionCadence.audioOnly,
    }.entries) {
      test('maps thermal load ${entry.key} to ${entry.value}', () {
        expect(
          policy
              .decide(
                thermalLoad: VisionThermalLoad(entry.key),
                supportsVision: true,
              )
              .cadence,
          entry.value,
        );
      });
    }

    test('low-tier vision disabled is not an error or a transport stop', () {
      final decision = policy.decide(
        thermalLoad: VisionThermalLoad.normal(),
        supportsVision: false,
      );

      expect(decision.cadence, VisionCadence.visionDisabled);
      expect(decision.isError, isFalse);
      expect(decision.requiresTransportStop, isFalse);
    });

    test('the same injected signal always produces the same decision', () {
      final load = VisionThermalLoad(40);

      expect(
        policy.decide(thermalLoad: load, supportsVision: true),
        policy.decide(thermalLoad: load, supportsVision: true),
      );
    });
  });

  test('thermal load rejects values outside its documented range', () {
    expect(() => VisionThermalLoad(-1), throwsArgumentError);
    expect(() => VisionThermalLoad(101), throwsArgumentError);
  });
}
