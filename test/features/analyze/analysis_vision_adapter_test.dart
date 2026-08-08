import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/analyze/model/analyze_result.dart';
import 'package:strumsight/features/analyze/model/analysis_vision_reference.dart';
import 'package:strumsight/features/analyze/providers/analysis_vision_adapter.dart';
import 'package:strumsight/features/vision/domain/evidence/vision_evidence.dart';
import 'package:strumsight/features/vision/domain/sync/vision_clock.dart';

void main() {
  const adapter = AnalysisVisionAdapter();
  const clipStart = SessionTimestamp(1_000_000);

  test(
    'round-trips clip-relative time through the shared session timeline',
    () {
      final timestamp = adapter.toSessionTimestamp(
        clipStart: clipStart,
        clipRelativeSeconds: 2.5,
      );

      expect(timestamp, const SessionTimestamp(3_500_000));
      expect(
        adapter.toClipRelativeSeconds(
          clipStart: clipStart,
          sessionTimestamp: timestamp,
        ),
        2.5,
      );
    },
  );

  test('creates inferred provenance for linked audio and vision evidence', () {
    final reference = adapter.adapt(
      analysisEvidenceId: 'audio-chord-1',
      visionEvidenceId: 'vision-evidence-1',
      clipStart: clipStart,
      clipRelativeSeconds: 2.5,
    );

    expect(reference, isA<AnalysisVisionReference>());
    expect(reference.observationState, ObservationState.inferred);
    expect(reference.analysisEvidenceId, 'audio-chord-1');
    expect(reference.visionEvidenceId, 'vision-evidence-1');
    expect(reference.sessionTimestamp, const SessionTimestamp(3_500_000));
  });

  test('projects chord and strum timeline points onto session time', () {
    final chordReference = adapter.forChord(
      analysisEvidenceId: 'audio-chord-1',
      visionEvidenceId: 'vision-evidence-1',
      clipStart: clipStart,
      chord: const TimelineChord(label: 'Am', startSec: 2, endSec: 4),
    );
    final strumReference = adapter.forStrum(
      analysisEvidenceId: 'audio-strum-1',
      visionEvidenceId: 'vision-evidence-1',
      clipStart: clipStart,
      strum: const TimelineStrum(
        direction: StrumDirection.down,
        timeSec: 3,
        confidence: 0.9,
      ),
    );

    expect(chordReference.sessionTimestamp, const SessionTimestamp(3_000_000));
    expect(strumReference.sessionTimestamp, const SessionTimestamp(4_000_000));
  });

  test('adapter use creates no network client or request', () {
    final networkSpy = _NetworkSpyOverrides();

    HttpOverrides.runZoned(
      () => adapter.adapt(
        analysisEvidenceId: 'audio-chord-1',
        visionEvidenceId: 'vision-evidence-1',
        clipStart: clipStart,
        clipRelativeSeconds: 2.5,
      ),
      createHttpClient: networkSpy.createHttpClient,
    );

    expect(networkSpy.clientCreations, 0);
  });

  test(
    'adapter source contains neither network transport nor wall-clock time',
    () {
      final adapterSource = File(
        'lib/features/analyze/providers/analysis_vision_adapter.dart',
      ).readAsStringSync();
      final referenceSource = File(
        'lib/features/analyze/model/analysis_vision_reference.dart',
      ).readAsStringSync();

      expect(adapterSource, isNot(contains('dio')));
      expect(adapterSource, isNot(contains('http')));
      expect('$adapterSource$referenceSource', isNot(contains('DateTime')));
    },
  );
}

final class _NetworkSpyOverrides {
  int clientCreations = 0;

  HttpClient createHttpClient(SecurityContext? context) {
    clientCreations++;
    throw StateError('The pure adapter must not create a network client.');
  }
}
