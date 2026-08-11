import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart' as legacy_core;
import 'package:strumsight/features/audio_analysis/public.dart';
import 'package:strumsight/features/analyze/public.dart' as legacy;
import 'package:strumsight/features/library/public.dart';

void main() {
  const adapter = LegacyAnalyzeAdapter();
  const viewAdapter = LegacyViewAdapter();

  for (final fixture in <String>[
    'legacy_session_v1.json',
    'legacy_session_pre_bpb.json',
    'legacy_session_lab_diag.json',
  ]) {
    test('migrates $fixture without inventing V2 measurements', () {
      final session = _fixture(fixture);
      final migrated = adapter.adapt(session);
      final document = migrated.document;

      expect(document.id, session.id);
      expect(document.createdAt, session.createdAt);
      expect(migrated.title, session.title);
      expect(migrated.customTitle, session.customTitle);
      expect(document.metrics, isEmpty);
      expect(document.signalQuality.measured, isFalse);
      expect(
        document.warnings,
        contains(
          predicate<AnalysisWarning>(
            (warning) => warning.kind == AnalysisWarningKind.migration,
          ),
        ),
      );
      expect(
        document.timeline.chordSegments,
        hasLength(session.result.chords.length),
      );
      expect(
        document.timeline.events.whereType<StrumEvent>(),
        hasLength(session.result.strums.length),
      );
      expect(document.timeline.tempoPoints.single.bpm, session.result.bpm);
      expect(
        document.capabilities,
        hasLength(AnalysisCapability.values.length),
      );

      for (final capability in document.capabilities) {
        final supplied = <AnalysisCapability>{
          AnalysisCapability.chordTimeline,
          AnalysisCapability.strumDirection,
          AnalysisCapability.onsetTimeline,
        };
        if (supplied.contains(capability.capability)) {
          expect(capability.status, CapabilityStatus.available);
        } else {
          expect(capability.status, CapabilityStatus.unavailable);
          expect(
            capability.reason,
            CapabilityUnavailableReason.modelUnavailable,
          );
          expect(capability.details, const <String, Object?>{
            'legacyMigration': 'true',
          });
        }
      }

      final legacy = viewAdapter.toAnalyzeResult(document);
      expect(legacy.durationSec, closeTo(session.result.durationSec, .000001));
      expect(legacy.bpm, session.result.bpm);
      expect(legacy.beatsPerBar, session.result.beatsPerBar);
      expect(
        legacy.chords.map((chord) => chord.label),
        session.result.chords.map((chord) => chord.label),
      );
      expect(
        legacy.chords.map((chord) => chord.startSec),
        orderedEquals(session.result.chords.map((chord) => chord.startSec)),
      );
      expect(
        legacy.chords.map((chord) => chord.endSec),
        orderedEquals(session.result.chords.map((chord) => chord.endSec)),
      );
      expect(
        legacy.strums.map((strum) => strum.direction.name),
        session.result.strums.map((strum) => strum.direction.name),
      );
      expect(
        legacy.strums.map((strum) => strum.timeSec),
        orderedEquals(session.result.strums.map((strum) => strum.timeSec)),
      );
      expect(
        legacy.strums.map((strum) => strum.confidence),
        orderedEquals(session.result.strums.map((strum) => strum.confidence)),
      );

      if (fixture == 'legacy_session_lab_diag.json') {
        expect(migrated.diagnostics, isNotNull);
        expect(document.metrics, isEmpty);
      }
    });
  }

  test('uses four beats per bar when the legacy record predates bpb', () {
    final migrated = adapter.adapt(_fixture('legacy_session_pre_bpb.json'));
    final warning = migrated.document.warnings.singleWhere(
      (value) => value.kind == AnalysisWarningKind.migration,
    );

    expect(warning.messageArgs['beatsPerBar'], '4');
    expect(viewAdapter.toAnalyzeResult(migrated.document).beatsPerBar, 4);
  });

  test('migrates a zero-BPM session without a synthetic tempo point', () {
    final session = AnalyzedSession(
      id: 'zero-bpm',
      createdAt: DateTime.utc(2026, 8, 11),
      title: 'One strum',
      result: const legacy.AnalyzeResult(
        durationSec: 1,
        bpm: 0,
        chords: <legacy.TimelineChord>[
          legacy.TimelineChord(label: 'C', startSec: 0, endSec: 1),
        ],
        strums: <legacy.TimelineStrum>[],
      ),
    );

    final migrated = adapter.adapt(session).document;

    expect(migrated.timeline.tempoPoints, isEmpty);
    expect(viewAdapter.toAnalyzeResult(migrated).bpm, 0);
  });

  test('drops invalid V1 chords and reports the migration correction', () {
    final session = AnalyzedSession(
      id: 'invalid-timeline',
      createdAt: DateTime.utc(2026, 8, 11),
      title: 'Corrupt timeline',
      result: const legacy.AnalyzeResult(
        durationSec: 1,
        bpm: 120,
        chords: <legacy.TimelineChord>[
          legacy.TimelineChord(label: 'C', startSec: 0, endSec: 1),
          legacy.TimelineChord(label: 'G', startSec: 1, endSec: 0),
        ],
        strums: <legacy.TimelineStrum>[
          legacy.TimelineStrum(
            direction: legacy_core.StrumDirection.down,
            timeSec: .5,
            confidence: 1.2,
          ),
        ],
      ),
    );

    final migrated = adapter.adapt(session).document;

    expect(migrated.timeline.chordSegments, hasLength(1));
    expect(migrated.timeline.events.whereType<StrumEvent>(), hasLength(1));
    expect(
      migrated.timeline.events.whereType<StrumEvent>().single.confidence,
      1,
    );
    final warning = migrated.warnings.singleWhere(
      (value) =>
          value.messageKey ==
          'analysis.migration.legacy_v1.dropped_timeline_entries',
    );
    expect(warning.messageArgs, <String, String>{
      'droppedChords': '1',
      'droppedStrums': '0',
    });
  });
}

AnalyzedSession _fixture(String name) {
  final source = File('test/fixtures/analysis/$name').readAsStringSync();
  return AnalyzedSession.fromJson(jsonDecode(source) as Map<String, dynamic>);
}
