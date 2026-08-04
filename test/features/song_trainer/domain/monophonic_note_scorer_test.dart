import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/pitch/pitch_observation.dart';
import 'package:strumsight/features/song_trainer/domain/models/note_scoring_models.dart';
import 'package:strumsight/features/song_trainer/domain/services/monophonic_note_scorer.dart';

void main() {
  test(
    'compensates observation latency before applying inclusive exact and onset boundaries',
    () {
      final startedAt = DateTime.utc(2026, 8, 4);
      final scorer = MonophonicNoteScorer(
        startedAt: startedAt,
        targets: <NoteScoringTarget>[
          const NoteScoringTarget(
            id: 'clean-a2',
            midiPitch: 45,
            start: Duration(seconds: 1),
            duration: Duration(milliseconds: 500),
          ),
        ],
        policy: const NoteScoringPolicy(),
      );

      final update = scorer.observe(
        PitchObservation(
          observedAt: startedAt.add(const Duration(milliseconds: 1080)),
          frequencyHz: 110,
          midiPitch: 45,
          centsFromNearest: 12,
          clarity: 0.85,
          rms: 0.014,
          stable: true,
        ),
      );

      expect(update.compensatedAt, const Duration(seconds: 1));
      expect(update.noteUpdates, hasLength(1));
      expect(update.noteUpdates.single.pitchGrade, NotePitchGrade.exact);
      expect(update.noteUpdates.single.onsetGrade, NoteOnsetGrade.onTime);
    },
  );

  test('finalizes an unobserved target as a missed no-stable-pitch note', () {
    final scorer = MonophonicNoteScorer(
      startedAt: DateTime.utc(2026, 8, 4),
      targets: <NoteScoringTarget>[
        const NoteScoringTarget(
          id: 'silence',
          midiPitch: 45,
          start: Duration.zero,
          duration: Duration(milliseconds: 100),
        ),
      ],
    );

    scorer.advance(const Duration(milliseconds: 181));
    final result = scorer.finalize();

    expect(result.notes, hasLength(1));
    expect(result.notes.single.pitchGrade, NotePitchGrade.noStablePitch);
    expect(result.notes.single.onsetGrade, NoteOnsetGrade.missed);
    expect(result.notes.single.coverage, 0);
  });

  test(
    'retains the best pitch, onset and coverage from deterministic replay',
    () {
      final startedAt = DateTime.utc(2026, 8, 4);
      final scorer = MonophonicNoteScorer(
        startedAt: startedAt,
        targets: <NoteScoringTarget>[
          const NoteScoringTarget(
            id: 'coverage-boundary',
            midiPitch: 45,
            start: Duration.zero,
            duration: Duration(milliseconds: 100),
          ),
        ],
      );

      scorer.observe(
        PitchObservation(
          observedAt: startedAt.add(const Duration(milliseconds: 80)),
          frequencyHz: 110,
          midiPitch: 45,
          centsFromNearest: 0,
          clarity: 0.85,
          rms: 0.014,
          stable: true,
        ),
      );
      scorer.advance(const Duration(milliseconds: 181));
      final result = scorer.finalize();

      expect(result.notes.single.pitchGrade, NotePitchGrade.exact);
      expect(result.notes.single.onsetGrade, NoteOnsetGrade.onTime);
      expect(result.notes.single.coverage, 0.6);
    },
  );

  test(
    'fixture manifest pins raw timestamps, compensation and pitch/onset grades',
    () {
      final manifest =
          jsonDecode(
                File(
                  'test/fixtures/audio/song_trainer/pitch_fixture_manifest.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final limits = manifest['thresholds'] as Map<String, Object?>;
      final startedAt = DateTime.utc(2026, 8, 4);

      for (final rawFixture in manifest['fixtures']! as List<Object?>) {
        final fixture = rawFixture as Map<String, Object?>;
        final latencyUs = fixture['latencyUs'] as int;
        final supportedLatency =
            latencyUs <=
            (limits['maximumObservationLatencyMicrosecondsInclusive'] as int);
        final stable = fixture['accepted'] != false && supportedLatency;
        final scorer = MonophonicNoteScorer(
          startedAt: startedAt,
          targets: <NoteScoringTarget>[
            NoteScoringTarget(
              id: fixture['id']! as String,
              midiPitch: fixture['targetMidi']! as int,
              start: Duration(microseconds: fixture['targetStartUs']! as int),
              duration: const Duration(milliseconds: 500),
            ),
          ],
          policy: NoteScoringPolicy(
            inputLatency: Duration(microseconds: latencyUs),
          ),
        );

        final update = scorer.observe(
          PitchObservation(
            observedAt: startedAt.add(
              Duration(microseconds: fixture['rawObservedAtUs']! as int),
            ),
            frequencyHz: 110,
            midiPitch: fixture['observedMidi']! as int,
            centsFromNearest: fixture['cents']! as double,
            clarity: 0.85,
            rms: 0.014,
            stable: stable,
          ),
        );

        expect(
          update.compensatedAt.inMicroseconds,
          fixture['expectedCompensatedAtUs'],
          reason: '${fixture['id']} compensation',
        );
        expect(
          update.noteUpdates,
          hasLength(1),
          reason: '${fixture['id']} target',
        );
        expect(
          update.noteUpdates.single.pitchGrade.name,
          fixture['expectedPitchGrade'],
          reason: '${fixture['id']} pitch grade',
        );
        expect(
          update.noteUpdates.single.onsetGrade.name,
          fixture['expectedOnsetGrade'],
          reason: '${fixture['id']} onset grade',
        );
      }
    },
  );

  test(
    'counts one extra onset for a continuous stable pitch outside every target',
    () {
      final startedAt = DateTime.utc(2026, 8, 4);
      final scorer = MonophonicNoteScorer(
        startedAt: startedAt,
        targets: const <NoteScoringTarget>[],
      );
      final observation = PitchObservation(
        observedAt: startedAt.add(const Duration(milliseconds: 80)),
        frequencyHz: 110,
        midiPitch: 45,
        centsFromNearest: 0,
        clarity: 0.85,
        rms: 0.014,
        stable: true,
      );

      expect(scorer.observe(observation).extraNoteDetected, isTrue);
      expect(scorer.observe(observation).extraNoteDetected, isFalse);
      expect(scorer.finalize().extraNoteCount, 1);
    },
  );

  test(
    'does not grade a stable-marked observation below the clarity or RMS gates',
    () {
      final startedAt = DateTime.utc(2026, 8, 4);
      final scorer = MonophonicNoteScorer(
        startedAt: startedAt,
        targets: <NoteScoringTarget>[
          const NoteScoringTarget(
            id: 'speech',
            midiPitch: 45,
            start: Duration.zero,
            duration: Duration(milliseconds: 100),
          ),
        ],
      );

      final update = scorer.observe(
        PitchObservation(
          observedAt: startedAt.add(const Duration(milliseconds: 80)),
          frequencyHz: 110,
          midiPitch: 45,
          centsFromNearest: 0,
          clarity: 0.8499,
          rms: 0.014,
          stable: true,
        ),
      );

      expect(
        update.noteUpdates.single.pitchGrade,
        NotePitchGrade.noStablePitch,
      );
      expect(update.noteUpdates.single.onsetGrade, NoteOnsetGrade.missed);
    },
  );

  test('replaying the same observation sequence yields an equal result', () {
    NoteScoringResult replay() {
      final startedAt = DateTime.utc(2026, 8, 4);
      final scorer = MonophonicNoteScorer(
        startedAt: startedAt,
        targets: <NoteScoringTarget>[
          const NoteScoringTarget(
            id: 'repeat',
            midiPitch: 45,
            start: Duration.zero,
            duration: Duration(milliseconds: 100),
          ),
        ],
      );
      scorer.observe(
        PitchObservation(
          observedAt: startedAt.add(const Duration(milliseconds: 80)),
          frequencyHz: 110,
          midiPitch: 45,
          centsFromNearest: 0,
          clarity: 0.85,
          rms: 0.014,
          stable: true,
        ),
      );
      scorer.advance(const Duration(milliseconds: 181));
      return scorer.finalize();
    }

    expect(replay(), replay());
  });
}
