import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/vision/domain/integration/vision_context_snapshot.dart';

void main() {
  final snapshot = VisionContextSnapshot(
    sessionId: 'vision-session-1',
    sessionTimestamp: SessionTimestamp(1_250_000),
    insightCode: InsightCode.pickingStable,
    confidence: 0.8,
    observationState: ObservationState.observed,
  );

  test('serializes exactly the pinned minimal evidence keys', () {
    expect(snapshot.toJson().keys, <String>[
      'sessionId',
      'sessionTimestampUs',
      'insightCode',
      'confidence',
      'observationState',
    ]);
  });

  test(
    'never serializes raw frame, landmark, face-point, or image URI data',
    () {
      const forbiddenKeys = <String>[
        'frame',
        'landmarks',
        'facePoints',
        'imageUri',
      ];

      for (final key in forbiddenKeys) {
        expect(snapshot.toJson(), isNot(contains(key)), reason: '$key is raw');
      }
    },
  );

  test('rejects an invalid confidence', () {
    expect(
      () => VisionContextSnapshot(
        sessionId: 'vision-session-1',
        sessionTimestamp: const SessionTimestamp(1),
        insightCode: InsightCode.pickingStable,
        confidence: 1.1,
        observationState: ObservationState.observed,
      ),
      throwsArgumentError,
    );
  });
}
