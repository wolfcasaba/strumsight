import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_event.dart';

void main() {
  test(
    'onset and strum retain optional evidence without changing base fields',
    () {
      final onset = OnsetEvent(
        id: 'onset',
        time: const Duration(milliseconds: 10),
        confidence: .8,
        sampleIndex: 480,
        attackStrength: .7,
        localRms: .4,
        confidenceSource: EventConfidenceSources.crnn,
        fallbackReason: 'model-fallback',
      );
      final strum = StrumEvent(
        id: 'strum',
        time: const Duration(milliseconds: 10),
        confidence: .8,
        sampleIndex: 480,
        direction: StrumDirection.down,
        directionConfidence: .75,
        onsetEventId: onset.id,
        attackStrength: .7,
        localRms: .4,
        confidenceSource: EventConfidenceSources.crnn,
        fallbackReason: 'model-fallback',
      );

      expect(onset.attackStrength, .7);
      expect(onset.localRms, .4);
      expect(onset.confidenceSource, EventConfidenceSources.crnn);
      expect(strum.directionConfidence, .75);
      expect(strum.onsetEventId, onset.id);
      expect(strum.fallbackReason, 'model-fallback');
    },
  );

  test(
    'new evidence fields preserve compatible defaults and reject invalid values',
    () {
      final onset = OnsetEvent(
        id: 'onset',
        time: Duration.zero,
        confidence: .5,
      );
      final strum = StrumEvent(
        id: 'strum',
        time: Duration.zero,
        confidence: .5,
        direction: StrumDirection.up,
      );

      expect(onset.confidenceSource, EventConfidenceSources.heuristic);
      expect(onset.attackStrength, isNull);
      expect(strum.directionConfidence, isNull);
      expect(strum.onsetEventId, isNull);
      expect(
        () => OnsetEvent(
          id: 'bad',
          time: Duration.zero,
          confidence: .5,
          localRms: -1,
        ),
        throwsArgumentError,
      );
      expect(
        () => StrumEvent(
          id: 'bad',
          time: Duration.zero,
          confidence: .5,
          direction: StrumDirection.up,
          directionConfidence: 1.1,
        ),
        throwsArgumentError,
      );
    },
  );
}
