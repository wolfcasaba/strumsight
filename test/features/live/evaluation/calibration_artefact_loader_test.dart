// E14-R21/R32 (ADR 0536 D6): loading the calibration artefact.
//
// What these cells prove:
//   * absence is a first-class, named state — and it is today's state;
//   * a malformed / mis-bound artefact NEVER degrades to "no calibration"
//     silently: the typed error travels out in the result, so the caller can
//     surface it;
//   * either way the resolver serves nothing, so `calibratedConfidence`
//     stays null.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/live/data/evaluation/calibration_artefact_loader.dart';
import 'package:strumsight/features/live/domain/evaluation/confidence_calibration_profile.dart';

void main() {
  final model = CalibrationModelIdentity(
    modelId: 'strum_crnn_live_3c',
    modelSha256: 'a' * 64,
  );

  test('the canonical asset path is derived from the model id', () {
    expect(
      calibrationAssetPathFor('strum_crnn_live_3c'),
      'assets/ml/strum_crnn_live_3c.calibration.json',
    );
  });

  test('no artefact: absent, with the path named, and the resolver serves '
      'nothing (the SHIPPED state)', () async {
    const loader = CalibrationArtefactLoader(_noArtefact);

    final result = await loader.load(
      model: model,
      expectedBand: CalibrationBand.strum,
    );

    expect(result.status, CalibrationLoadStatus.absent);
    expect(result.profile, isNull);
    expect(result.error, isNull);
    expect(result.assetPath, 'assets/ml/strum_crnn_live_3c.calibration.json');
    expect(result.describe(), contains('no calibration artefact'));

    final resolver = CalibrationArtefactLoader.resolverFrom(
      CalibrationBand.strum,
      result,
    );
    final outcome = resolver.calibrate(rawConfidence: 0.9, loadedModel: model);
    expect(outcome.calibratedConfidence, isNull);
    expect(outcome.unavailableReason, CalibrationUnavailableReason.noArtefact);
  });

  test('malformed JSON is INVALID with a typed error attached — never a '
      'silent fall-back to absent', () async {
    const loader = CalibrationArtefactLoader(_brokenArtefact);

    final result = await loader.load(
      model: model,
      expectedBand: CalibrationBand.strum,
    );

    expect(result.status, CalibrationLoadStatus.invalid);
    expect(result.error, isA<CalibrationConfigException>());
    expect(result.describe(), contains('invalid calibration artefact'));
    // Still nothing served: the failure is visible, not fatal.
    final resolver = CalibrationArtefactLoader.resolverFrom(
      CalibrationBand.strum,
      result,
    );
    expect(
      resolver.calibrate(rawConfidence: 0.9, loadedModel: model).isAvailable,
      isFalse,
    );
  });

  test('an artefact bound to different weights is INVALID, not absent — a '
      'mis-packaged artefact must be seen', () async {
    final loader = CalibrationArtefactLoader(
      (path) async => jsonEncode(_artefactFor(modelSha256: 'b' * 64)),
    );

    final result = await loader.load(
      model: model,
      expectedBand: CalibrationBand.strum,
    );

    expect(result.status, CalibrationLoadStatus.invalid);
    expect(result.error!.path, 'calibration.model');
  });

  test('a chord artefact asked for by the strum band is INVALID', () async {
    final loader = CalibrationArtefactLoader(
      (path) async => jsonEncode(_artefactFor(band: 'chord')),
    );

    final result = await loader.load(
      model: model,
      expectedBand: CalibrationBand.strum,
    );

    expect(result.status, CalibrationLoadStatus.invalid);
    expect(result.error!.path, 'calibration.band');
  });

  test('a well-formed, correctly bound artefact loads and serves', () async {
    final loader = CalibrationArtefactLoader(
      (path) async => jsonEncode(_artefactFor()),
    );

    final result = await loader.load(
      model: model,
      expectedBand: CalibrationBand.strum,
    );

    expect(result.status, CalibrationLoadStatus.loaded);
    expect(result.profile!.artefactVersion, 'strum-live3c-heldout-v1');
    expect(result.describe(), contains('heldOut'));

    final resolver = CalibrationArtefactLoader.resolverFrom(
      CalibrationBand.strum,
      result,
    );
    final outcome = resolver.calibrate(rawConfidence: 0.4, loadedModel: model);
    // knots (0.0 -> 0.5) and (1.0 -> 0.9): 0.5 + 0.4 * 0.4 = 0.66.
    expect(outcome.calibratedConfidence, closeTo(0.66, 1e-12));
  });
}

Future<String?> _noArtefact(String path) async => null;

Future<String?> _brokenArtefact(String path) async => '{ not json';

Map<String, Object?> _artefactFor({
  String band = 'strum',
  String? modelSha256,
}) => <String, Object?>{
  'schemaVersion': '1',
  'artefactVersion': 'strum-live3c-heldout-v1',
  'band': band,
  'model': <String, Object?>{
    'modelId': 'strum_crnn_live_3c',
    'modelSha256': modelSha256 ?? 'a' * 64,
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
  'mapping': <String, Object?>{
    'kind': 'piecewiseLinear',
    'knots': <Object?>[
      <String, Object?>{'raw': 0.0, 'calibrated': 0.5},
      <String, Object?>{'raw': 1.0, 'calibrated': 0.9},
    ],
  },
};
