// E14-R21/R32 (ADR 0536/0540): the calibration artefact contract.
//
// What these cells prove, in one line each:
//   * a calibrated confidence exists ONLY when a held-out, model-bound
//     artefact exists — the shipped state is `null` with a stated reason;
//   * the mapping is monotone and total on 0..1 by construction;
//   * a wrong model / wrong band / in-sample artefact fails CLOSED, with a
//     typed reason, never a silent identity fallback.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/domain/evaluation/confidence_calibration_profile.dart';

void main() {
  final strumModel = CalibrationModelIdentity(
    modelId: 'strum_crnn_live_3c',
    modelSha256: 'a' * 64,
  );

  group('shipped default: no artefact', () {
    test('an absent resolver returns no value and names the reason', () {
      const resolver = ConfidenceCalibrationResolver.absent(
        CalibrationBand.strum,
      );

      final outcome = resolver.calibrate(
        rawConfidence: 0.97,
        loadedModel: strumModel,
      );

      expect(outcome.calibratedConfidence, isNull);
      expect(outcome.isAvailable, isFalse);
      expect(
        outcome.unavailableReason,
        CalibrationUnavailableReason.noArtefact,
      );
    });
  });

  group('mapping', () {
    test('identity is total on 0..1 and clamps outside it', () {
      const mapping = CalibrationMapping.identity();

      expect(mapping.apply(0), 0);
      expect(mapping.apply(0.42), 0.42);
      expect(mapping.apply(1), 1);
      expect(mapping.apply(-3), 0);
      expect(mapping.apply(7), 1);
    });

    test('piecewise-linear interpolates between knots and clamps at the '
        'ends — it never extrapolates a number no fold measured', () {
      final mapping = CalibrationMapping.piecewiseLinear(const [
        CalibrationKnot(raw: 0.5, calibrated: 0.6),
        CalibrationKnot(raw: 0.9, calibrated: 0.8),
      ]);

      expect(mapping.apply(0.5), closeTo(0.6, 1e-12));
      expect(mapping.apply(0.7), closeTo(0.7, 1e-12));
      expect(mapping.apply(0.9), closeTo(0.8, 1e-12));
      // Below the first / above the last knot: clamped, not extrapolated.
      expect(mapping.apply(0.1), closeTo(0.6, 1e-12));
      expect(mapping.apply(1), closeTo(0.8, 1e-12));
    });

    test('a decreasing calibrated series is rejected: monotonicity is a '
        'construction-time invariant, not a hope', () {
      expect(
        () => CalibrationMapping.piecewiseLinear(const [
          CalibrationKnot(raw: 0.5, calibrated: 0.8),
          CalibrationKnot(raw: 0.9, calibrated: 0.6),
        ]),
        throwsA(
          isA<CalibrationConfigException>().having(
            (e) => e.kind,
            'kind',
            CalibrationConfigErrorKind.nonMonotonic,
          ),
        ),
      );
    });

    test('a repeated raw value is rejected (ambiguous map)', () {
      expect(
        () => CalibrationMapping.piecewiseLinear(const [
          CalibrationKnot(raw: 0.5, calibrated: 0.6),
          CalibrationKnot(raw: 0.5, calibrated: 0.7),
        ]),
        throwsA(
          isA<CalibrationConfigException>().having(
            (e) => e.kind,
            'kind',
            CalibrationConfigErrorKind.nonMonotonic,
          ),
        ),
      );
    });

    test('a single knot is rejected', () {
      expect(
        () => CalibrationMapping.piecewiseLinear(const [
          CalibrationKnot(raw: 0.5, calibrated: 0.6),
        ]),
        throwsA(
          isA<CalibrationConfigException>().having(
            (e) => e.kind,
            'kind',
            CalibrationConfigErrorKind.tooFewKnots,
          ),
        ),
      );
    });

    test('a knot outside 0..1 is rejected', () {
      expect(
        () => CalibrationMapping.piecewiseLinear(const [
          CalibrationKnot(raw: 0.5, calibrated: 0.6),
          CalibrationKnot(raw: 1.5, calibrated: 0.7),
        ]),
        throwsA(
          isA<CalibrationConfigException>().having(
            (e) => e.kind,
            'kind',
            CalibrationConfigErrorKind.outOfRange,
          ),
        ),
      );
    });
  });

  group('artefact parsing', () {
    test('a complete held-out strum artefact parses and serves', () {
      final profile = ConfidenceCalibrationProfile.parseJsonString(
        jsonEncode(_strumArtefact()),
      );

      expect(profile.band, CalibrationBand.strum);
      expect(profile.artefactVersion, 'strum-live3c-heldout-v1');
      expect(profile.provenance.observationCount, 2018);
      expect(profile.isServable, isTrue);

      final resolver = ConfidenceCalibrationResolver(
        band: CalibrationBand.strum,
        profile: profile,
      );
      final outcome = resolver.calibrate(
        rawConfidence: 0.7,
        loadedModel: strumModel,
      );
      expect(outcome.calibratedConfidence, closeTo(0.7, 1e-12));
    });

    test('an unknown schemaVersion is typed, never a default mapping', () {
      final json = _strumArtefact()..['schemaVersion'] = '99';

      expect(
        () => ConfidenceCalibrationProfile.parse(json),
        throwsA(
          isA<CalibrationConfigException>().having(
            (e) => e.kind,
            'kind',
            CalibrationConfigErrorKind.unknownSchemaVersion,
          ),
        ),
      );
    });

    test('observationCount 0 is a parse error — an artefact fitted on '
        'nothing is not a measurement', () {
      final json = _strumArtefact();
      (json['provenance']! as Map<String, Object?>)['observationCount'] = 0;

      expect(
        () => ConfidenceCalibrationProfile.parse(json),
        throwsA(
          isA<CalibrationConfigException>().having(
            (e) => e.kind,
            'kind',
            CalibrationConfigErrorKind.outOfRange,
          ),
        ),
      );
    });

    test('a missing provenance field is a typed error, not a blank', () {
      final json = _strumArtefact();
      (json['provenance']! as Map<String, Object?>).remove('foldId');

      expect(
        () => ConfidenceCalibrationProfile.parse(json),
        throwsA(
          isA<CalibrationConfigException>()
              .having(
                (e) => e.kind,
                'kind',
                CalibrationConfigErrorKind.missingField,
              )
              .having((e) => e.path, 'path', 'calibration.provenance.foldId'),
        ),
      );
    });

    test('a strum artefact may not carry per-class mappings', () {
      final json = _strumArtefact()
        ..['perClassMappings'] = <String, Object?>{
          'A:min': <String, Object?>{'kind': 'identity'},
        };

      expect(
        () => ConfidenceCalibrationProfile.parse(json),
        throwsA(
          isA<CalibrationConfigException>().having(
            (e) => e.kind,
            'kind',
            CalibrationConfigErrorKind.unknownField,
          ),
        ),
      );
    });

    test('an identity mapping declaring knots is rejected', () {
      final json = _strumArtefact()
        ..['mapping'] = <String, Object?>{
          'kind': 'identity',
          'knots': <Object?>[],
        };

      expect(
        () => ConfidenceCalibrationProfile.parse(json),
        throwsA(isA<CalibrationConfigException>()),
      );
    });
  });

  group('fail-closed binding', () {
    test('a different model sha256 withholds the value and says why', () {
      final profile = ConfidenceCalibrationProfile.parse(_strumArtefact());
      final resolver = ConfidenceCalibrationResolver(
        band: CalibrationBand.strum,
        profile: profile,
      );

      final outcome = resolver.calibrate(
        rawConfidence: 0.95,
        loadedModel: CalibrationModelIdentity(
          modelId: 'strum_crnn_live_3c',
          modelSha256: 'b' * 64,
        ),
      );

      expect(outcome.calibratedConfidence, isNull);
      expect(
        outcome.unavailableReason,
        CalibrationUnavailableReason.modelMismatch,
      );
    });

    test('an IN-SAMPLE artefact is representable but never served — this is '
        'why the live_crnn_classifier knots are not promoted', () {
      final json = _strumArtefact();
      (json['provenance']! as Map<String, Object?>)['sampling'] = 'inSample';
      final profile = ConfidenceCalibrationProfile.parse(json);

      expect(profile.isServable, isFalse);

      final outcome = ConfidenceCalibrationResolver(
        band: CalibrationBand.strum,
        profile: profile,
      ).calibrate(rawConfidence: 0.95, loadedModel: strumModel);

      expect(outcome.calibratedConfidence, isNull);
      expect(
        outcome.unavailableReason,
        CalibrationUnavailableReason.inSampleArtefact,
      );
    });

    test('a chord artefact served to the strum band is a band mismatch', () {
      final profile = ConfidenceCalibrationProfile.parse(_chordArtefact());

      final outcome = ConfidenceCalibrationResolver(
        band: CalibrationBand.strum,
        profile: profile,
      ).calibrate(
        rawConfidence: 0.9,
        loadedModel: CalibrationModelIdentity(
          modelId: 'chord_crnn',
          modelSha256: 'c' * 64,
        ),
      );

      expect(
        outcome.unavailableReason,
        CalibrationUnavailableReason.bandMismatch,
      );
    });
  });

  group('chord artefact: root + quality aware', () {
    test('a per-class mapping wins over the default for that class only', () {
      final profile = ConfidenceCalibrationProfile.parse(_chordArtefact());
      final chordModel = CalibrationModelIdentity(
        modelId: 'chord_crnn',
        modelSha256: 'c' * 64,
      );
      final resolver = ConfidenceCalibrationResolver(
        band: CalibrationBand.chord,
        profile: profile,
      );

      final perClass = resolver.calibrate(
        rawConfidence: 0.5,
        loadedModel: chordModel,
        chordClass: const ChordClassKey(root: 'A', quality: 'min'),
      );
      final fallback = resolver.calibrate(
        rawConfidence: 0.5,
        loadedModel: chordModel,
        chordClass: const ChordClassKey(root: 'C', quality: 'maj'),
      );

      expect(perClass.calibratedConfidence, closeTo(0.3, 1e-12));
      expect(fallback.calibratedConfidence, closeTo(0.5, 1e-12));
    });

    test('label parsing splits root and quality, and refuses the reserved '
        'evaluation labels', () {
      expect(ChordClassKey.tryParseLabel('A#m')?.wireKey, 'A#:min');
      expect(ChordClassKey.tryParseLabel('C')?.wireKey, 'C:maj');
      expect(ChordClassKey.tryParseLabel('F#m')?.wireKey, 'F#:min');
      expect(ChordClassKey.tryParseLabel(recognitionNoChordLabel), isNull);
      expect(ChordClassKey.tryParseLabel(recognitionUnknownChordLabel), isNull);
      expect(ChordClassKey.tryParseLabel('H'), isNull);
    });

    test('the two reserved labels are different strings — N.C. and unknown '
        'never collapse into one state (ADR 0540 D1)', () {
      expect(recognitionNoChordLabel, isNot(recognitionUnknownChordLabel));
      expect(recognitionNoChordLabel, 'noChord');
      expect(recognitionUnknownChordLabel, 'unknown');
    });
  });
}

Map<String, Object?> _strumArtefact() => <String, Object?>{
  'schemaVersion': '1',
  'artefactVersion': 'strum-live3c-heldout-v1',
  'band': 'strum',
  'model': <String, Object?>{
    'modelId': 'strum_crnn_live_3c',
    'modelSha256': 'a' * 64,
  },
  'provenance': <String, Object?>{
    'corpusId': 'klangio-live70',
    'corpusSha256': 'deadbeef',
    'foldId': 'split3way-seed42-val',
    'sampling': 'heldOut',
    'observationCount': 2018,
    'fittedAtCommit': 'git:0000000000000000000000000000000000000000',
    'producedBy': 'ml-train.yml sections=calib',
  },
  'mapping': <String, Object?>{'kind': 'identity'},
};

Map<String, Object?> _chordArtefact() => <String, Object?>{
  'schemaVersion': '1',
  'artefactVersion': 'chord-crnn-heldout-v1',
  'band': 'chord',
  'model': <String, Object?>{'modelId': 'chord_crnn', 'modelSha256': 'c' * 64},
  'provenance': <String, Object?>{
    'corpusId': 'guitarset-majmin',
    'corpusSha256': 'cafebabe',
    'foldId': 'logo-fold-3',
    'sampling': 'heldOut',
    'observationCount': 4096,
    'fittedAtCommit': 'git:1111111111111111111111111111111111111111',
    'producedBy': 'chord-train.yml',
  },
  'mapping': <String, Object?>{'kind': 'identity'},
  'perClassMappings': <String, Object?>{
    'A:min': <String, Object?>{
      'kind': 'piecewiseLinear',
      'knots': <Object?>[
        <String, Object?>{'raw': 0.0, 'calibrated': 0.0},
        <String, Object?>{'raw': 1.0, 'calibrated': 0.6},
      ],
    },
  },
};
