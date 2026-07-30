import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/data/adapters/daily_challenge_practice_adapter.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_difficulty.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/streak/public.dart';

PracticeDefinition _ok(AppResult<PracticeDefinition> r) =>
    (r as Success<PracticeDefinition>).value;

AppFailure _err(AppResult<PracticeDefinition> r) =>
    (r as Failure<PracticeDefinition>).error;

DailyChallenge _challenge(int day, List<StrumDirection> pattern) =>
    DailyChallenge(day: day, name: 'Day $day', pattern: pattern);

void main() {
  group('practiceDefinitionFromDailyChallenge — determinism', () {
    test('the same epoch day produces structurally equal definitions', () {
      final challenge = DailyChallenge.forDay(20000);
      final a = _ok(practiceDefinitionFromDailyChallenge(challenge));
      final b = _ok(practiceDefinitionFromDailyChallenge(challenge));
      expect(a, b);
      expect(a, equals(b));
    });

    test('consecutive epoch days produce different definitions', () {
      final a = _ok(
        practiceDefinitionFromDailyChallenge(DailyChallenge.forDay(20000)),
      );
      final b = _ok(
        practiceDefinitionFromDailyChallenge(DailyChallenge.forDay(20001)),
      );
      expect(a, isNot(b));
    });

    test('definition ID encodes the epoch day', () {
      final def = _ok(
        practiceDefinitionFromDailyChallenge(DailyChallenge.forDay(20000)),
      );
      expect(def.id, 'dailyChallenge.20000.v1');
      expect(def.sourceReference, 'dailyChallenge:20000');
    });
  });

  group('practiceDefinitionFromDailyChallenge — pattern handling', () {
    test('pattern longer than 8 slots is truncated to 8 events', () {
      final challenge = _challenge(1, const [
        StrumDirection.down,
        StrumDirection.up,
        StrumDirection.down,
        StrumDirection.up,
        StrumDirection.down,
        StrumDirection.up,
        StrumDirection.down,
        StrumDirection.up,
        StrumDirection.down, // 9th, dropped
        StrumDirection.up, // 10th, dropped
      ]);
      final def = _ok(practiceDefinitionFromDailyChallenge(challenge));
      expect(def.events, hasLength(8));
      for (var i = 0; i < 8; i++) {
        expect(def.events[i].direction, challenge.pattern[i]);
        expect(
          def.events[i].position.ticks,
          i * (BeatPosition.ticksPerBeat ~/ 2),
        );
      }
    });

    test('pattern shorter than 8 slots is preserved as-is', () {
      final challenge = _challenge(2, const [
        StrumDirection.down,
        StrumDirection.up,
        StrumDirection.down,
      ]);
      final def = _ok(practiceDefinitionFromDailyChallenge(challenge));
      expect(def.events, hasLength(3));
      expect(def.events[0].direction, StrumDirection.down);
      expect(def.events[1].direction, StrumDirection.up);
      expect(def.events[2].direction, StrumDirection.down);
    });

    test('every event has a null chord (strum-only)', () {
      final def = _ok(
        practiceDefinitionFromDailyChallenge(DailyChallenge.forDay(20000)),
      );
      for (final event in def.events) {
        expect(event.chord, isNull);
      }
    });

    test('event positions are eighth-note slots starting at zero', () {
      final def = _ok(
        practiceDefinitionFromDailyChallenge(DailyChallenge.forDay(20000)),
      );
      for (var i = 0; i < def.events.length; i++) {
        expect(
          def.events[i].position.ticks,
          i * (BeatPosition.ticksPerBeat ~/ 2),
        );
      }
    });
  });

  group('practiceDefinitionFromDailyChallenge — definition surface', () {
    test('source, mode, keys, difficulty, profile match ADR contract', () {
      final def = _ok(
        practiceDefinitionFromDailyChallenge(DailyChallenge.forDay(20000)),
      );
      expect(def.source, PracticeSource.dailyChallenge);
      expect(def.mode, PracticeMode.strumPattern);
      expect(def.titleKey, 'practiceSourceDailyChallengeTitle');
      expect(def.descriptionKey, 'practiceSourceDailyChallengeDescription');
      expect(def.difficulty, PracticeDifficulty.beginner);
      expect(def.skillTags, ['dailyChallenge']);
      expect(def.meter.beatsPerBar, 4);
      expect(def.totalBeats.toLegacyBeats(), 4.0);
      expect(def.defaultTempo.bpm, 80.0);
      expect(def.validate(), isEmpty);
    });

    test('custom bpm is honored when in range', () {
      final challenge = DailyChallenge.forDay(20000);
      final def = _ok(
        practiceDefinitionFromDailyChallenge(challenge, bpm: 120),
      );
      expect(def.defaultTempo.bpm, 120.0);
    });
  });

  group('practiceDefinitionFromDailyChallenge — controlled failure modes', () {
    test('empty pattern is rejected', () {
      final challenge = _challenge(3, const []);
      final r = practiceDefinitionFromDailyChallenge(challenge);
      expect(r.isFailure, isTrue);
      expect(_err(r).code, FailureCode.practiceContentUnsupported);
    });

    test('bpm out of range is rejected', () {
      final challenge = DailyChallenge.forDay(20000);
      final r = practiceDefinitionFromDailyChallenge(challenge, bpm: 10);
      expect(r.isFailure, isTrue);
      expect(_err(r).code, FailureCode.practiceContentUnsupported);

      final r2 = practiceDefinitionFromDailyChallenge(challenge, bpm: 400);
      expect(r2.isFailure, isTrue);
      expect(_err(r2).code, FailureCode.practiceContentUnsupported);
    });

    test('non-finite bpm is rejected', () {
      final challenge = DailyChallenge.forDay(20000);
      final r = practiceDefinitionFromDailyChallenge(
        challenge,
        bpm: double.nan,
      );
      expect(r.isFailure, isTrue);
      expect(_err(r).code, FailureCode.practiceContentUnsupported);
    });

    test('none of the failure paths throws', () {
      final challenge = _challenge(4, const []);
      expect(
        () => practiceDefinitionFromDailyChallenge(challenge),
        returnsNormally,
      );
      final realChallenge = DailyChallenge.forDay(20000);
      expect(
        () => practiceDefinitionFromDailyChallenge(realChallenge, bpm: 10),
        returnsNormally,
      );
      expect(
        () => practiceDefinitionFromDailyChallenge(
          realChallenge,
          bpm: double.nan,
        ),
        returnsNormally,
      );
    });
  });

  group('practiceDefinitionFromDailyChallenge — displayTitle', () {
    test('trims whitespace and falls back to null for empty names', () {
      final challenge = DailyChallenge(
        day: 5,
        name: '  Trim Me  ',
        pattern: const [StrumDirection.down],
      );
      final def = _ok(practiceDefinitionFromDailyChallenge(challenge));
      expect(def.displayTitle, 'Trim Me');

      final blank = DailyChallenge(
        day: 6,
        name: '',
        pattern: const [StrumDirection.down],
      );
      final blankDef = _ok(practiceDefinitionFromDailyChallenge(blank));
      expect(blankDef.displayTitle, isNull);
    });
  });
}
