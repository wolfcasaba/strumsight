import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart' as legacy_core;
import 'package:strumsight/features/audio_analysis/domain/analysis_capability.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_mode.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_warning.dart';
import 'package:strumsight/features/audio_analysis/domain/preprocessed_audio.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_provenance_builder.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_work_state.dart';
import 'package:strumsight/features/audio_analysis/engine/legacy/legacy_evidence.dart';

void main() {
  group('AnalysisWorkState', () {
    test('seed carries the boundary input and its own warnings', () {
      final input = _input(
        warnings: <AnalysisWarning>[
          AnalysisWarning(
            kind: AnalysisWarningKind.inputQuality,
            severity: AnalysisWarningSeverity.info,
            messageKey: 'quality.recording_short_clip',
          ),
        ],
      );

      final state = AnalysisWorkState.seed(input: input);

      expect(state.input, same(input));
      expect(state.warnings, input.warnings);
      expect(state.legacyEvidence, isNull);
      expect(state.preprocessedAudio, isNull);
      expect(state.signalQuality, isNull);
      expect(state.pitchFrames, isEmpty);
      expect(state.pitchSegments, isEmpty);
      expect(state.chordSegments, isEmpty);
      expect(state.beatGrid, isNull);
      expect(state.tempoCurve, isNull);
      expect(state.events, isEmpty);
      expect(state.suppressedEvents, isEmpty);
      expect(state.unavailableCapabilities, isEmpty);
    });

    test('copyWith returns a new instance and never mutates the original', () {
      final original = AnalysisWorkState.seed(input: _input());
      final audio = _audio();

      final withAudio = original.copyWith(preprocessedAudio: audio);

      expect(identical(withAudio, original), isFalse);
      expect(original.preprocessedAudio, isNull);
      expect(withAudio.preprocessedAudio, same(audio));
    });

    test('copyWith preserves fields that were not passed', () {
      final legacyEvidence = _legacyEvidence();
      final withEvidence = AnalysisWorkState.seed(
        input: _input(),
        legacyEvidence: legacyEvidence,
      );

      final withAudio = withEvidence.copyWith(preprocessedAudio: _audio());

      expect(withAudio.legacyEvidence, same(legacyEvidence));
      expect(withAudio.input, same(withEvidence.input));
    });

    test('copyWith replaces list/set fields wholesale, immutably', () {
      final state = AnalysisWorkState.seed(input: _input());
      final capabilities = <AnalysisCapability>{
        AnalysisCapability.monophonicPitch,
      };

      final degraded = state.copyWith(unavailableCapabilities: capabilities);

      expect(state.unavailableCapabilities, isEmpty);
      expect(degraded.unavailableCapabilities, capabilities);
      expect(
        () => degraded.unavailableCapabilities.add(
          AnalysisCapability.chordTimeline,
        ),
        throwsUnsupportedError,
      );
    });

    test('constructor lists and sets are unmodifiable', () {
      final state = AnalysisWorkState.seed(input: _input());

      expect(() => state.pitchFrames.clear(), throwsUnsupportedError);
      expect(() => state.chordSegments.clear(), throwsUnsupportedError);
      expect(() => state.warnings.clear(), throwsUnsupportedError);
    });
  });
}

ValidatedPcmAnalysisInput _input({
  List<AnalysisWarning> warnings = const <AnalysisWarning>[],
}) => ValidatedPcmAnalysisInput(
  input: PcmAnalysisInput(
    samples: const <double>[0.1, -0.1, 0.2, -0.2],
    sampleRate: 44100,
    channelCount: 1,
    source: AnalysisInputSource.microphone,
  ),
  warnings: warnings,
);

PreprocessedAudio _audio() => PreprocessedAudio(
  originalSamples: const <double>[0.1, -0.1],
  canonicalSamples: const <double>[0.1, -0.1],
  sampleRate: 44100,
  originalChannelCount: 1,
  normalizationGain: 1,
  preprocessingVersion: 'test',
);

LegacyEvidence _legacyEvidence() => LegacyEvidence(
  duration: const Duration(seconds: 1),
  bpm: 120,
  chords: const <LegacyChordEvidence>[],
  strums: const <LegacyStrumEvidence>[
    LegacyStrumEvidence(
      direction: legacy_core.StrumDirection.down,
      time: Duration.zero,
      confidence: .8,
    ),
  ],
  call: LegacyClipAnalyzerCall(
    sampleRate: 44100,
    sampleCount: 44100,
    labMode: false,
    hasCandidateStrumRefiner: false,
  ),
  provenance: AnalysisProvenanceBuilder().build(
    strumRefinerSource: StrumRefinerSource.none,
  ),
);
