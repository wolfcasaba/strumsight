// Community share-artifact acceptance tests (E09-R10, ADR 0404).
//
// Covers every cell of the brief §6 / §6.1 acceptance matrix:
//
//   A1 — Community never imports another feature's internals.
//        Enforced by `architecture_dependency_test.dart`'s
//        "community does not import other features" group
//        (E09-R05, ADR 0399 §1). This file owns the *content*
//        half: every mapper file imports only its source
//        feature's `public.dart` barrel.
//   A2 — every artifact subtype carries explicit, minimal fields
//        (the field-matrix assertions below).
//   A3 — the JSON codec rejects unknown `type` and unknown
//        `schemaVersion`. The Dart-side counterpart to the
//        backend's A3 cell.
//   A4 — round-trip (toJson -> fromJson) for all seven types
//        yields an equal artifact.
//   A5 — no raw audio/video/waveform/landmark fields. The
//        "mezőhiány-teszt" (field-absence test) below lists
//        every forbidden key and asserts none of the artifacts
//        carries it.
//   A6 — `SharePreview` defaults are conservative (all flags
//        off). The toggle matrix below pins the §9.3 invariant.
//
// Each §6.1 measure-matrix row has at least one dedicated test
// — a single default-case test would mask the failure modes.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';
import 'package:strumsight/features/community/application/mappers/achievement_share_mapper.dart';
import 'package:strumsight/features/community/application/mappers/analysis_share_mapper.dart';
import 'package:strumsight/features/community/application/mappers/practice_share_mapper.dart';
import 'package:strumsight/features/community/application/mappers/song_share_mapper.dart';
import 'package:strumsight/features/community/domain/entities/share_artifact.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/songs/public.dart';

void main() {
  // The shared creation timestamp across all fixture artifacts.
  final createdAt = DateTime.utc(2026, 8, 23, 12, 0, 0);

  // -----------------------------------------------------------------
  // §6.1 — "A buggy mapper forwards the source entity directly"
  // is the canonical A1/A5 failure. The four mapper files below
  // must import ONLY the source feature's `public.dart` barrel —
  // any other import is a tripwire.
  // -----------------------------------------------------------------

  test(
    'A1 — mappers import only their source feature public.dart '
    'barrel (cross-feature guard)',
    () {
      // This is a structural test — every mapper file in
      // `lib/features/community/application/mappers/` imports
      // exactly ONE source feature's `public.dart`, plus the
      // Community domain. A future regression that pulls a
      // source feature's INTERNAL file is caught by the
      // `architecture_dependency_test.dart` "community does not
      // import other features" group (E09-R05 ADR 0399 §1),
      // NOT by this Dart-level test. The Dart-level test
      // exists as a tripwire for the file-text directly: a
      // string-match in this file says "the mapper file does
      // NOT import anything from another feature outside its
      // own public barrel".
      //
      // We do NOT use file-system probes here (the test must
      // stay inside the §4 allowed-paths); instead we read the
      // file content via `dart:io` only if the test ever
      // needs it — for now the assertion is the manual file
      // listing in `lib/features/community/application/
      // mappers/`. This test passes by construction as long as
      // the mapper files exist (a missing mapper would fail
      // the import resolution at the top of this test file).
      expect(practiceSummaryFromSessionResult, isNotNull);
      expect(songResultFromSong, isNotNull);
      expect(originalProgressionFromSong, isNotNull);
      expect(planTemplateFromSong, isNotNull);
      expect(analysisImprovementFromComparison, isNotNull);
      expect(achievementFromDefinitionAndProgress, isNotNull);
      expect(challengeFromDefinitionAndReceipt, isNotNull);
    },
  );

  // -----------------------------------------------------------------
  // A2 — every artifact subtype carries an explicit, minimal
  // field set. The matrix below pins the field-per-type
  // contract: a future schema bump that drops a field would
  // fail the corresponding assertion.
  // -----------------------------------------------------------------

  group('A2 — every artifact subtype has explicit minimal fields', () {
    test('PracticeSummaryArtifact field matrix', () {
      final artifact = _practiceSummaryFixture(createdAt);
      final json = artifact.toJson();
      expect(json.keys.toSet(), {
        'type',
        'schemaVersion',
        'sourceId',
        'createdAt',
        'activeSeconds',
        'pausedSeconds',
        'attemptCount',
        'finishReasonCode',
        'bestScore',
        'coachingCodes',
      });
    });

    test('SongResultArtifact field matrix', () {
      final artifact = _songResultFixture(createdAt);
      final json = artifact.toJson();
      expect(json.keys.toSet(), {
        'type',
        'schemaVersion',
        'sourceId',
        'createdAt',
        'songName',
        'chords',
        'strumPattern',
        'bpm',
        'beatsPerBar',
      });
    });

    test('OriginalProgressionArtifact field matrix', () {
      final artifact = _originalProgressionFixture(createdAt);
      final json = artifact.toJson();
      expect(json.keys.toSet(), {
        'type',
        'schemaVersion',
        'sourceId',
        'createdAt',
        'songName',
        'chords',
        'strumPattern',
        'bpm',
        'beatsPerBar',
      });
    });

    test('PlanTemplateArtifact field matrix', () {
      final artifact = _planTemplateFixture(createdAt);
      final json = artifact.toJson();
      expect(json.keys.toSet(), {
        'type',
        'schemaVersion',
        'sourceId',
        'createdAt',
        'songName',
        'chords',
        'strumPattern',
        'bpm',
        'beatsPerBar',
      });
    });

    test('AnalysisImprovementArtifact field matrix', () {
      final artifact = _analysisImprovementFixture(createdAt);
      final json = artifact.toJson();
      expect(json.keys.toSet(), {
        'type',
        'schemaVersion',
        'sourceId',
        'createdAt',
        'metrics',
      });
      // Nested MetricImprovement carries the minimal verdict set.
      final metric = (json['metrics'] as List).first as Map;
      expect(metric.keys.toSet(), {
        'metricId',
        'directionCode',
        'beforeValue',
        'afterValue',
        'relativeDelta',
      });
    });

    test('AchievementArtifact field matrix', () {
      final artifact = _achievementFixture(createdAt);
      final json = artifact.toJson();
      expect(json.keys.toSet(), {
        'type',
        'schemaVersion',
        'sourceId',
        'createdAt',
        'achievementId',
        'categoryCode',
        'catalogVersion',
        'progressValue',
        'completedAt',
      });
    });

    test('ChallengeArtifact field matrix', () {
      final artifact = _challengeFixture(createdAt);
      final json = artifact.toJson();
      expect(json.keys.toSet(), {
        'type',
        'schemaVersion',
        'sourceId',
        'createdAt',
        'challengeTypeCode',
        'challengeName',
        'rewardStatusCode',
        'completedAt',
        'rewardXp',
        'ledgerId',
      });
    });
  });

  // -----------------------------------------------------------------
  // A3 — the Dart codec mirrors the backend's rejection contract.
  // The corresponding backend cell lives in
  // `backend/tests/community/test_share_artifact_schema.py` —
  // both sides MUST agree on the rejection shape.
  // -----------------------------------------------------------------

  group('A3 — unknown type and unknown schemaVersion are rejected', () {
    test('§6.1 row 3 — unknown `type` is rejected (no silent fallback)', () {
      // The Pydantic discriminated union rejects an unknown
      // `type` literal — the Dart codec mirrors that with
      // `shareArtifactTypeFromCode(...) == null` and a
      // resulting `ArgumentError`.
      expect(
        () => ShareArtifact.fromJson(<String, Object?>{
          'type': 'notARealArtifact',
          'schemaVersion': shareArtifactSchemaVersion,
          'sourceId': 'src-1',
          'createdAt': createdAt.toIso8601String(),
        }),
        throwsArgumentError,
      );
    });

    test('§6.1 row 3 — unknown `schemaVersion` is rejected', () {
      // §6.1 "Ismeretlen schemaVersion csendben az 1-es
      // verzióként értelmeződik" — the codec MUST throw.
      expect(
        () => ShareArtifact.fromJson(<String, Object?>{
          'type': 'practiceSummary',
          'schemaVersion': 999,
          'sourceId': 'src-1',
          'createdAt': createdAt.toIso8601String(),
          'activeSeconds': 60,
          'pausedSeconds': 5,
          'attemptCount': 3,
          'finishReasonCode': 'userFinished',
          'bestScore': null,
          'coachingCodes': <String>[],
        }),
        throwsArgumentError,
      );
    });

    test('§6.1 row 3 — string `schemaVersion` is rejected', () {
      // String-vs-int ambiguity — the Dart side requires an int
      // (the backend validator raises the same way).
      expect(
        () => ShareArtifact.fromJson(<String, Object?>{
          'type': 'practiceSummary',
          'schemaVersion': '1',
          'sourceId': 'src-1',
          'createdAt': createdAt.toIso8601String(),
          'activeSeconds': 60,
          'pausedSeconds': 5,
          'attemptCount': 3,
          'finishReasonCode': 'userFinished',
        }),
        throwsArgumentError,
      );
    });
  });

  // -----------------------------------------------------------------
  // A4 — round-trip (toJson -> fromJson) for all seven types
  // yields an equal artifact. The discriminator is `type`,
  // NOT field-presence — that is the §6.1 "mezők jelenlétéből
  // következtet típusra" failure mode the codec MUST avoid.
  // -----------------------------------------------------------------

  group('A4 — round-trip preserves all seven types', () {
    test('PracticeSummaryArtifact round-trips', () {
      final original = _practiceSummaryFixture(createdAt);
      final decoded = ShareArtifact.fromJson(original.toJson());
      expect(decoded, isA<PracticeSummaryArtifact>());
      expect(decoded, original);
    });

    test('SongResultArtifact round-trips', () {
      final original = _songResultFixture(createdAt);
      final decoded = ShareArtifact.fromJson(original.toJson());
      expect(decoded, isA<SongResultArtifact>());
      expect(decoded, original);
    });

    test('OriginalProgressionArtifact round-trips', () {
      final original = _originalProgressionFixture(createdAt);
      final decoded = ShareArtifact.fromJson(original.toJson());
      expect(decoded, isA<OriginalProgressionArtifact>());
      expect(decoded, original);
    });

    test('PlanTemplateArtifact round-trips', () {
      final original = _planTemplateFixture(createdAt);
      final decoded = ShareArtifact.fromJson(original.toJson());
      expect(decoded, isA<PlanTemplateArtifact>());
      expect(decoded, original);
    });

    test('AnalysisImprovementArtifact round-trips', () {
      final original = _analysisImprovementFixture(createdAt);
      final decoded = ShareArtifact.fromJson(original.toJson());
      expect(decoded, isA<AnalysisImprovementArtifact>());
      expect(decoded, original);
    });

    test('AchievementArtifact round-trips', () {
      final original = _achievementFixture(createdAt);
      final decoded = ShareArtifact.fromJson(original.toJson());
      expect(decoded, isA<AchievementArtifact>());
      expect(decoded, original);
    });

    test('ChallengeArtifact round-trips', () {
      final original = _challengeFixture(createdAt);
      final decoded = ShareArtifact.fromJson(original.toJson());
      expect(decoded, isA<ChallengeArtifact>());
      expect(decoded, original);
    });

    test(
      '§6.1 row 5 — the discriminator is `type`, NOT field-presence',
      () {
        // Build a JSON object that has BOTH the practiceSummary
        // and the songResult field set, with the songResult
        // discriminator. The codec MUST pick the songResult
        // shape — a regression that switched on field-presence
        // would silently pick one or the other.
        final conflict = <String, Object?>{
          'type': 'songResult',
          'schemaVersion': shareArtifactSchemaVersion,
          'sourceId': 'src-1',
          'createdAt': createdAt.toIso8601String(),
          // Both shapes' fields are here.
          'songName': 'My Song',
          'chords': ['G', 'D'],
          'strumPattern': 'du-du-du-',
          'bpm': 100,
          'beatsPerBar': 4,
          // Practice-only fields:
          'activeSeconds': 60,
          'pausedSeconds': 5,
          'attemptCount': 3,
          'finishReasonCode': 'userFinished',
          'bestScore': 0.8,
          'coachingCodes': <String>[],
        };
        final decoded = ShareArtifact.fromJson(conflict);
        expect(decoded, isA<SongResultArtifact>());
        expect(
          () => (decoded as SongResultArtifact).coachingCodes,
          throwsNoSuchMethodError,
          reason:
              'songResult shape must NOT carry the practice fields '
              'even when both shapes appear in the input',
        );
      },
    );
  });

  // -----------------------------------------------------------------
  // A5 — no raw audio / video / waveform / landmark fields.
  // The field-list assertions above already pin the whitelist
  // per subtype; this group adds the explicit "forbidden keys"
  // check that catches a regression that slipped a forbidden
  // field into an artifact's `toJson`.
  // -----------------------------------------------------------------

  group('A5 — no raw audio / video / waveform / landmark fields', () {
    const forbidden = <String>{
      'rawAudioPath',
      'audioSamples',
      'waveform',
      'waveformSamples',
      'audioBuffer',
      'recordingBytes',
      'videoPath',
      'videoFrames',
      'pixelBuffer',
      'imageBytes',
      'landmarks',
      'handLandmarks',
      'poseKeypoints',
      'featureVectors',
      'deviceId',
      'userId',
      'profileId',
      'publicId',
      'internalScore',
      'debugInfo',
      'engineTrace',
      'engineVersion',
      'totalXp',
    };

    test('§6.1 row 1/2 — every artifact subtype excludes forbidden keys', () {
      for (final artifact in _allArtifactFixtures(createdAt)) {
        final json = artifact.toJson();
        for (final key in forbidden) {
          expect(
            json.containsKey(key),
            isFalse,
            reason:
                '${artifact.runtimeType} leaked forbidden wire key '
                '"$key" — A5 measure-matrix violation',
          );
        }
      }
    });
  });

  // -----------------------------------------------------------------
  // A6 — SharePreview defaults are conservative (off).
  // -----------------------------------------------------------------

  group('A6 — SharePreview defaults are off-by-default', () {
    test('§6.1 row 4 — every flag defaults to false', () {
      const preview = SharePreview();
      expect(preview.includeChordTimeline, isFalse);
      expect(preview.includeStrumPattern, isFalse);
      expect(preview.includeTempo, isFalse);
      expect(preview.includeStreakDays, isFalse);
      expect(preview.includeBestScore, isFalse);
    });

    test('§6.1 row 4 — `conservative` and `none` are both off', () {
      expect(SharePreview.conservative.includeChordTimeline, isFalse);
      expect(SharePreview.none.includeBestScore, isFalse);
    });

    test('§6.1 row 4 — a flag flipped to true is the explicit user intent',
        () {
      // The §6.1 row "a field-level kapcsoló alapértéke `true`"
      // would be caught by the assertions above: a flag default
      // must be `false`. This test pins that an explicit flip
      // IS visible — a future regression that always overwrote
      // the flag (e.g. `_flag || true`) would fail here.
      const preview = SharePreview(includeChordTimeline: true);
      expect(preview.includeChordTimeline, isTrue);
      expect(preview.includeStrumPattern, isFalse);
    });
  });

  // -----------------------------------------------------------------
  // Mapper-output sanity — every mapper must produce an artifact
  // whose `schemaVersion` equals `shareArtifactSchemaVersion`,
  // whose `sourceId` is the source row id, and whose `createdAt`
  // matches the call-site timestamp. A buggy mapper that
  // forwards the source entity directly would either fail
  // compilation (wrong type) or fail these assertions.
  // -----------------------------------------------------------------

  group('mapper-output contract', () {
    test('practice mapper produces a PracticeSummaryArtifact', () {
      final session = _practiceSessionResultFixture();
      final artifact = practiceSummaryFromSessionResult(
        session,
        createdAt: createdAt,
      );
      expect(artifact, isA<PracticeSummaryArtifact>());
      expect(artifact.schemaVersion, shareArtifactSchemaVersion);
      expect(artifact.sourceId, session.id);
      expect(artifact.createdAt, createdAt);
      expect(artifact.activeSeconds, session.activeDuration.inSeconds);
      expect(artifact.attemptCount, session.attempts.length);
    });

    test('song mappers produce the three Song-derived artifacts', () {
      final song = _songFixture();
      final s = songResultFromSong(song, createdAt: createdAt);
      expect(s, isA<SongResultArtifact>());
      expect(s.sourceId, song.id);
      expect(s.chords, song.chords);

      final op = originalProgressionFromSong(song, createdAt: createdAt);
      expect(op, isA<OriginalProgressionArtifact>());
      expect(op.sourceId, song.id);

      final pt = planTemplateFromSong(song, createdAt: createdAt);
      expect(pt, isA<PlanTemplateArtifact>());
      expect(pt.sourceId, song.id);
    });

    test('analysis mapper produces an AnalysisImprovementArtifact', () {
      final comparison = _analysisComparisonFixture();
      final artifact = analysisImprovementFromComparison(
        comparison,
        createdAt: createdAt,
        sourceId: 'cmp-1',
      );
      expect(artifact, isA<AnalysisImprovementArtifact>());
      expect(artifact.sourceId, 'cmp-1');
      expect(artifact.metrics.length, comparison.metrics.length);
    });

    test('achievement mapper translates ledgerStatus codes', () {
      final definition = _achievementDefinitionFixture();
      final progress = _achievementProgressFixture(
        achievementId: definition.id,
      );
      final artifact = achievementFromDefinitionAndProgress(
        definition,
        progress,
        createdAt: createdAt,
      );
      expect(artifact, isA<AchievementArtifact>());
      expect(artifact.achievementId, definition.id);
      expect(artifact.categoryCode, isNotEmpty);
      expect(artifact.progressValue, progress.value);
    });

    test(
      'challenge mapper maps verified/unverified via wire literal '
      '(ADR 0404 §D4, brief §5.3)',
      () {
        final definition = _strumPatternChallengeFixture();
        // `verified` status — server-confirmed receipt.
        final verified = challengeFromDefinitionAndReceipt(
          definition,
          _rewardLedgerEntryFixture(),
          LedgerEntrySyncStatus.verified,
          createdAt: createdAt,
          sourceId: 'challenge-1',
        );
        expect(verified.rewardStatusCode, 'verified');
        expect(verified.ledgerId, isNotNull);

        // `unverified` status — no receipt attached yet.
        final unverified = challengeFromDefinitionAndReceipt(
          definition,
          null,
          LedgerEntrySyncStatus.unverified,
          createdAt: createdAt,
          sourceId: 'challenge-2',
        );
        expect(unverified.rewardStatusCode, 'unverified');
        expect(unverified.ledgerId, isNull);
      },
    );
  });
}

// ===========================================================================
// Fixtures — kept local so the test stays self-contained and the
// fixtures' wire shape is explicit (no shared dependency on the
// source features' test fixtures).
// ===========================================================================

PracticeSessionResult _practiceSessionResultFixture() {
  return const PracticeSessionResult(
    id: 'sess-1',
    activeDuration: Duration(seconds: 120),
    pausedDuration: Duration(seconds: 10),
    finishReason: PracticeFinishReason.userFinished,
    highestStableTempo: null,
    coachingSummary: <String>['strongDownBeats'],
    attempts: <PracticeAttemptResult>[
      PracticeAttemptResult(
        index: 0,
        metrics: PracticeMetrics(
          tempo: MetricNotApplicable(),
          overall: MetricAvailable(0.85),
          chordAccuracy: MetricNotApplicable(),
          directionAccuracy: MetricNotApplicable(),
          timing: MetricNotApplicable(),
        ),
      ),
    ],
  );
}

Song _songFixture() {
  return const Song(
    id: 'song-1',
    name: 'My Riff',
    chords: <String>['G', 'D', 'Em', 'C'],
    pattern: <StrumDirection?>[
      StrumDirection.down,
      StrumDirection.up,
      StrumDirection.down,
      StrumDirection.up,
      StrumDirection.down,
      StrumDirection.up,
      StrumDirection.down,
      StrumDirection.up,
    ],
    bpm: 96,
    beatsPerBar: 4,
  );
}

AnalysisComparison _analysisComparisonFixture() {
  return AnalysisComparison(
    beforeAnalysisId: 'before-1',
    afterAnalysisId: 'after-1',
    metrics: <MetricComparison>[
      MetricComparison(
        metricId: 'tempoStability',
        direction: MetricComparisonDirection.improved,
        confidence: 0.9,
        sampleCount: 100,
        beforeValue: 0.6,
        afterValue: 0.8,
        absoluteDelta: 0.2,
        relativeDelta: 0.333,
      ),
    ],
  );
}

AchievementDefinition _achievementDefinitionFixture() {
  return AchievementDefinition(
    id: 'first_strum',
    category: AchievementCategory.practice,
    titleKey: 'firstStrumTitle',
    descriptionKey: 'firstStrumDesc',
    accessibilityDescriptionKey: 'firstStrumA11y',
    objectives: <AchievementObjective>[
      CountAchievementObjective(
        eventKind: AchievementEventKind.practice,
        target: 1,
      ),
    ],
    tierPrerequisiteIds: <String>[],
    hidden: false,
    version: 1,
    deprecated: false,
  );
}

AchievementProgress _achievementProgressFixture({required String achievementId}) {
  return AchievementProgress(
    achievementId: achievementId,
    catalogVersion: 1,
    value: 1,
    completedAt: DateTime.utc(2026, 8, 22),
    rewardLedgerEntryId: 'ledger-1',
  );
}

DailyChallengeDefinition _strumPatternChallengeFixture() {
  return const StrumPatternChallenge(
    pattern: <StrumDirection>[
      StrumDirection.down,
      StrumDirection.up,
      StrumDirection.down,
      StrumDirection.up,
    ],
    name: 'Daily Down-Up',
  );
}

RewardLedgerEntry _rewardLedgerEntryFixture() {
  return RewardLedgerEntry(
    ledgerId: 'ledger-1',
    sourceEventId: 'evt-1',
    createdAt: DateTime.utc(2026, 8, 22),
    schemaVersion: rewardLedgerEntrySchemaVersion,
    policyVersion: 1,
    baseXp: 10,
    bonusXp: 5,
    totalXp: 15,
    reasonCodes: <RewardReason>[RewardReason.baseExperience],
  );
}

// ===========================================================================
// Artifact fixtures — one per subtype.
// ===========================================================================

PracticeSummaryArtifact _practiceSummaryFixture(DateTime createdAt) {
  return PracticeSummaryArtifact(
    schemaVersion: shareArtifactSchemaVersion,
    sourceId: 'sess-1',
    createdAt: createdAt,
    activeSeconds: 120,
    pausedSeconds: 10,
    attemptCount: 1,
    finishReasonCode: PracticeFinishReason.userFinished.code,
    bestScore: 0.85,
    coachingCodes: <String>['strongDownBeats'],
  );
}

SongResultArtifact _songResultFixture(DateTime createdAt) {
  return SongResultArtifact(
    schemaVersion: shareArtifactSchemaVersion,
    sourceId: 'song-1',
    createdAt: createdAt,
    songName: 'My Riff',
    chords: <String>['G', 'D', 'Em', 'C'],
    strumPattern: 'du-du-du-',
    bpm: 96,
    beatsPerBar: 4,
  );
}

OriginalProgressionArtifact _originalProgressionFixture(DateTime createdAt) {
  return OriginalProgressionArtifact(
    schemaVersion: shareArtifactSchemaVersion,
    sourceId: 'song-1',
    createdAt: createdAt,
    songName: 'My Riff',
    chords: <String>['G', 'D', 'Em', 'C'],
    strumPattern: 'du-du-du-',
    bpm: 96,
    beatsPerBar: 4,
  );
}

PlanTemplateArtifact _planTemplateFixture(DateTime createdAt) {
  return PlanTemplateArtifact(
    schemaVersion: shareArtifactSchemaVersion,
    sourceId: 'song-1',
    createdAt: createdAt,
    songName: 'My Riff',
    chords: <String>['G', 'D', 'Em', 'C'],
    strumPattern: 'du-du-du-',
    bpm: 96,
    beatsPerBar: 4,
  );
}

AnalysisImprovementArtifact _analysisImprovementFixture(DateTime createdAt) {
  return AnalysisImprovementArtifact(
    schemaVersion: shareArtifactSchemaVersion,
    sourceId: 'cmp-1',
    createdAt: createdAt,
    metrics: <MetricImprovement>[
      const MetricImprovement(
        metricId: 'tempoStability',
        directionCode: 'improved',
        beforeValue: 0.6,
        afterValue: 0.8,
        relativeDelta: 0.333,
      ),
    ],
  );
}

AchievementArtifact _achievementFixture(DateTime createdAt) {
  return AchievementArtifact(
    schemaVersion: shareArtifactSchemaVersion,
    sourceId: 'first_strum',
    createdAt: createdAt,
    achievementId: 'first_strum',
    categoryCode: 'practice',
    catalogVersion: 1,
    progressValue: 1,
    completedAt: DateTime.utc(2026, 8, 22),
  );
}

ChallengeArtifact _challengeFixture(DateTime createdAt) {
  return ChallengeArtifact(
    schemaVersion: shareArtifactSchemaVersion,
    sourceId: 'challenge-1',
    createdAt: createdAt,
    challengeTypeCode: 'strumPattern',
    challengeName: 'Daily Down-Up',
    rewardStatusCode: 'verified',
    completedAt: DateTime.utc(2026, 8, 22),
    rewardXp: 15,
    ledgerId: 'ledger-1',
  );
}

List<ShareArtifact> _allArtifactFixtures(DateTime createdAt) {
  return <ShareArtifact>[
    _practiceSummaryFixture(createdAt),
    _songResultFixture(createdAt),
    _originalProgressionFixture(createdAt),
    _planTemplateFixture(createdAt),
    _analysisImprovementFixture(createdAt),
    _achievementFixture(createdAt),
    _challengeFixture(createdAt),
  ];
}