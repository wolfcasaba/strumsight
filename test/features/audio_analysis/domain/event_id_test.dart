import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/events/event_id.dart';

void main() {
  group('EventId', () {
    test('builds a stable onset identifier from run and sample index', () {
      expect(
        EventId.onset(runId: 'run-42', sampleIndex: 123),
        'run-42:onset:123',
      );
    });

    test('uses a distinct fixed type literal for strums', () {
      expect(
        EventId.strum(runId: 'run-42', sampleIndex: 123),
        'run-42:strum:123',
      );
    });

    test('rejects blank run IDs and negative sample indexes', () {
      expect(
        () => EventId.onset(runId: ' ', sampleIndex: 0),
        throwsArgumentError,
      );
      expect(
        () => EventId.strum(runId: 'run-42', sampleIndex: -1),
        throwsArgumentError,
      );
    });
  });
}
