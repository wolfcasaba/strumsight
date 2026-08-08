import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/domain/evidence/confidence_model.dart';
import 'package:strumsight/features/vision/domain/sync/sync_quality.dart';

void main() {
  group('ConfidenceModel', () {
    const model = ConfidenceModel();

    test('uses the weakest component instead of averaging it away', () {
      expect(
        model.combine(
          ConfidenceComponents(model: 1, quality: 1, geometry: 1, sync: 0.25),
        ),
        0.25,
      );
    });

    test('rejects non-finite confidence components with an argument error', () {
      expect(
        () => ConfidenceComponents(
          model: double.nan,
          quality: 1,
          geometry: 1,
          sync: 1,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('propagates good, boundary and poor values for every component', () {
      final good = ConfidenceComponents(
        model: 1,
        quality: 1,
        geometry: 1,
        sync: 1,
      );
      final cases = <String, List<double>>{
        'model': <double>[0.9, 0.5, 0.1],
        'quality': <double>[0.9, 0.5, 0.1],
        'geometry': <double>[0.9, 0.5, 0.1],
        'sync': <double>[0.9, 0.5, 0.1],
      };

      for (final entry in cases.entries) {
        for (final value in entry.value) {
          final components = switch (entry.key) {
            'model' => good.copyWith(model: value),
            'quality' => good.copyWith(quality: value),
            'geometry' => good.copyWith(geometry: value),
            'sync' => good.copyWith(sync: value),
            _ => throw StateError('Unexpected matrix component.'),
          };
          expect(
            model.combine(components),
            lessThanOrEqualTo(value),
            reason: '${entry.key}=$value must not be averaged away.',
          );
        }
      }
    });

    test('maps sync quality monotonically', () {
      expect(
        model.syncContribution(SyncQuality.excellent),
        greaterThan(model.syncContribution(SyncQuality.good)),
      );
      expect(
        model.syncContribution(SyncQuality.good),
        greaterThan(model.syncContribution(SyncQuality.acceptable)),
      );
      expect(
        model.syncContribution(SyncQuality.acceptable),
        greaterThan(model.syncContribution(SyncQuality.poor)),
      );
    });
  });
}
