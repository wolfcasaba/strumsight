import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/data/legacy_analyze_adapter.dart';
import 'package:strumsight/features/audio_analysis/data/legacy_view_adapter.dart';
import 'package:strumsight/features/audio_analysis/public.dart';
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
      expect(document.warnings, contains(predicate<AnalysisWarning>(
        (warning) => warning.kind == AnalysisWarningKind.migration,
      )));
      expect(document.timeline.chordSegments, hasLength(session.result.chords.length));
      expect(document.timeline.events.whereType<StrumEvent>(), hasLength(session.result.strums.length));
      expect(document.timeline.tempoPoints.single.bpm, session.result.bpm);
      expect(document.capabilities, hasLength(AnalysisCapability.values.length));

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
          expect(capability.reason, CapabilityUnavailableReason.modelUnavailable);
        }
      }

      final legacy = viewAdapter.toAnalyzeResult(document);
      expect(legacy.durationSec, closeTo(session.result.durationSec, .000001));
      expect(legacy.bpm, session.result.bpm);
      expect(legacy.beatsPerBar, session.result.beatsPerBar);
      expect(legacy.chords.map((chord) => chord.label), session.result.chords.map((chord) => chord.label));
      expect(legacy.strums.map((strum) => strum.direction.name), session.result.strums.map((strum) => strum.direction.name));

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
}

AnalyzedSession _fixture(String name) {
  final source = File('test/fixtures/analysis/$name').readAsStringSync();
  return AnalyzedSession.fromJson(jsonDecode(source) as Map<String, dynamic>);
}
