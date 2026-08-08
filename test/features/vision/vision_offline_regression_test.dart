import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/audio/pitch/pitch_observation.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/ai_tutor/application/context/adapters/tutor_vision_context_adapter.dart';
import 'package:strumsight/features/ai_tutor/application/context/context_purpose.dart';
import 'package:strumsight/features/ai_tutor/application/context/redaction_report.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_snapshot.dart';
import 'package:strumsight/features/analyze/model/analyze_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_attempt_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_metrics.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_result.dart';
import 'package:strumsight/features/practice/domain/model/practice_verdict.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_clock.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_command.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_transport_state.dart';
import 'package:strumsight/features/song_trainer/data/playback/fake_backing_audio_player.dart';
import 'package:strumsight/features/song_trainer/domain/models/note_scoring_models.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_asset_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/services/monophonic_note_scorer.dart';
import 'package:strumsight/features/vision/domain/integration/public.dart';

void main() {
  test('all eleven Vision flags are false in every shipped environment', () {
    for (final environment in AppEnvironment.values) {
      final flags = FeatureFlags.forEnvironment(
        environment,
        accountEnabled: false,
      );

      expect(
        _visionFlags(flags),
        everyElement(isFalse),
        reason: environment.name,
      );
    }
  });

  test(
    'Vision-off fixture preserves audio scores, timing, analysis and Tutor output byte-for-byte',
    () async {
      final flags = FeatureFlags.forEnvironment(
        AppEnvironment.production,
        accountEnabled: false,
      );
      expect(_visionFlags(flags), everyElement(isFalse));

      expect(_practiceAudioProjection(), _preVisionPracticeAudioProjection);
      expect(await _songTimingProjection(), _preVisionSongTimingProjection);
      expect(_analysisProjection(), _preVisionAnalysisProjection);
      expect(_tutorProjection(), _preVisionTutorProjection);
    },
  );
}

List<bool> _visionFlags(FeatureFlags flags) => <bool>[
  flags.visionEnabled,
  flags.visionSetupEnabled,
  flags.visionHandTrackingEnabled,
  flags.visionPoseTrackingEnabled,
  flags.visionGuitarGeometryEnabled,
  flags.visionPracticeIntegrationEnabled,
  flags.visionSongIntegrationEnabled,
  flags.visionTutorIntegrationEnabled,
  flags.visionAnalysisIntegrationEnabled,
  flags.visionExperimentalFineFretEnabled,
  flags.visionLabCaptureEnabled,
];

String _practiceAudioProjection() {
  const result = PracticeSessionResult(
    id: 'audio-only-practice',
    activeDuration: Duration(seconds: 30),
    pausedDuration: Duration(seconds: 2),
    attempts: <PracticeAttemptResult>[
      PracticeAttemptResult(
        index: 0,
        tempo: Tempo(96),
        metrics: PracticeMetrics(
          completion: MetricAvailable(1),
          rhythm: MetricAvailable(0.9),
          direction: MetricAvailable(0.8),
          chord: MetricNotApplicable(),
          overall: MetricAvailable(0.9),
          totalTargets: 8,
          resolvedTargets: 7,
          maxCombo: 5,
          scorePoints: 900,
          meanAbsoluteOffset: Duration(milliseconds: 12),
          timingBias: Duration(milliseconds: -2),
        ),
        verdicts: <PracticeVerdict>[],
        outcome: PracticeAttemptOutcome.passed,
      ),
    ],
    finishReason: PracticeFinishReason.completedAllTargets,
    highestStableTempo: Tempo(96),
    coachingSummary: <String>[],
  );
  return jsonEncode(<String, Object?>{
    'id': result.id,
    'durationUs': result.activeDuration.inMicroseconds,
    'scorePoints': result.finalAttempt!.metrics.scorePoints,
    'overall': (result.finalAttempt!.metrics.overall as MetricAvailable).value,
    'vision': result.vision,
  });
}

Future<String> _songTimingProjection() async {
  final player = FakeBackingAudioPlayer();
  final clock = FakeSongTransportClock();
  final transport = SongTransport(player: player, clock: clock);
  try {
    await transport.dispatch(PrepareSongTransport(asset: _songAsset));
    await transport.dispatch(const StartSongTransport());
    clock.advance(const Duration(seconds: 1));
    final scorer = MonophonicNoteScorer(
      startedAt: DateTime.utc(2026, 8, 8),
      targets: const <NoteScoringTarget>[
        NoteScoringTarget(
          id: 'audio-note',
          midiPitch: 45,
          start: Duration(seconds: 1),
          duration: Duration(milliseconds: 500),
        ),
      ],
    );
    scorer.observe(
      PitchObservation(
        observedAt: DateTime.utc(2026, 8, 8, 0, 0, 1, 80),
        frequencyHz: 110,
        midiPitch: 45,
        centsFromNearest: 12,
        clarity: 0.85,
        rms: 0.014,
        stable: true,
      ),
    );
    scorer.advance(const Duration(seconds: 2));
    final result = scorer.finalize();
    return jsonEncode(<String, Object?>{
      'phase': transport.state.phase.name,
      'backing': transport.state.backingStatus.name,
      'positionUs': transport.state.activePosition.inMicroseconds,
      'pitch': result.notes.single.pitchGrade.name,
      'onset': result.notes.single.onsetGrade.name,
      'coverage': result.notes.single.coverage,
      'extraNotes': result.extraNoteCount,
    });
  } finally {
    await transport.dispose();
  }
}

String _analysisProjection() => jsonEncode(
  const AnalyzeResult(
    durationSec: 8,
    bpm: 96,
    chords: <TimelineChord>[TimelineChord(label: 'Am', startSec: 0, endSec: 4)],
    strums: <TimelineStrum>[
      TimelineStrum(
        direction: StrumDirection.down,
        timeSec: 1,
        confidence: 0.9,
      ),
    ],
  ).toJson(),
);

String _tutorProjection() {
  final vision = VisionContextSnapshot(
    sessionId: VisionSessionId('vision-session'),
    sessionTimestamp: const SessionTimestamp(1),
    insightCode: InsightCode.pickingStable,
    confidence: 0.9,
    observationState: ObservationState.observed,
  );
  final snapshot = TutorContextSnapshot(
    requestId: 'audio-only-tutor',
    createdAt: DateTime.utc(2026, 8, 8),
    purpose: ContextPurpose.sessionDebrief,
    fields: <TutorContextField>[
      TutorContextField.available(
        key: TutorContextFieldKey.analyze,
        values: const <String, Object?>{'summary': 'Am'},
        provenance: ContextProvenance(
          sourceFeature: ContextSourceFeature.analyze,
          schemaVersion: 'analyze.v1',
        ),
      ),
    ],
    redactionReport: RedactionReport.empty(),
  );

  expect(const TutorVisionContextAdapter().adapt(vision), isNull);
  return snapshot.canonicalJson;
}

final _songAsset = SongAssetReference(
  id: SongAssetId('audio-only-backing'),
  sha256: 'a' * 64,
  extension: 'mp3',
  byteLength: 1024,
  mimeType: 'audio/mpeg',
  durationMs: 10000,
);

const _preVisionPracticeAudioProjection =
    '{"id":"audio-only-practice","durationUs":30000000,"scorePoints":900,"overall":0.9,"vision":null}';
const _preVisionSongTimingProjection =
    '{"phase":"playing","backing":"playing","positionUs":1000000,"pitch":"exact","onset":"onTime","coverage":0.12,"extraNotes":0}';
const _preVisionAnalysisProjection =
    '{"duration":8.0,"bpm":96.0,"chords":[{"label":"Am","start":0.0,"end":4.0}],"strums":[{"dir":"down","time":1.0,"conf":0.9}],"bpb":4}';
const _preVisionTutorProjection =
    '{"createdAt":"2026-08-08T00:00:00.000Z","fields":[{"availability":"available","key":"analyze","provenance":{"schemaVersion":"analyze.v1","sourceFeature":"analyze"},"values":{"summary":"Am"}}],"purpose":"sessionDebrief","redactionReport":{"entries":[]},"requestId":"audio-only-tutor","truncatedFields":[]}';
