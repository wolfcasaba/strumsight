import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/meter.dart';
import 'package:strumsight/features/practice/domain/model/practice_definition.dart';
import 'package:strumsight/features/practice/domain/model/practice_difficulty.dart';
import 'package:strumsight/features/practice/domain/model/practice_event.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/practice_source.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';
import 'package:strumsight/features/practice/domain/model/tempo.dart';

void main() {
  group('PracticeDefinition validation', () {
    test('accepts a complete valid definition', () {
      expect(_definition().validate(), isEmpty);
    });

    test('aggregates definition fields and nested Tempo failures', () {
      final invalid = _definition(
        id: '',
        schemaVersion: 0,
        titleKey: '',
        descriptionKey: '',
        defaultTempo: const Tempo(500),
      );
      final codes = invalid.validate().map((failure) => failure.code);

      expect(
        codes,
        containsAll({
          'definition.id.empty',
          'definition.schemaVersion.invalid',
          'definition.titleKey.empty',
          'definition.descriptionKey.empty',
          'tempo.bpm.outOfRange',
        }),
      );
      expect(codes.length, greaterThanOrEqualTo(3));
    });

    test('rejects a non-positive total duration', () {
      final codes = _definition(
        mode: PracticeMode.freePractice,
        totalBeats: const BeatPosition(0),
        events: const [],
        scoringProfile: _freeProfile,
      ).validate().map((failure) => failure.code);

      expect(codes, contains('definition.totalBeats.nonPositive'));
    });

    test('requires a non-empty target list only for scored modes', () {
      expect(
        _definition(events: const []).validate().map((failure) => failure.code),
        contains('events.empty'),
      );
      expect(
        _definition(
          mode: PracticeMode.freePractice,
          events: const [],
          scoringProfile: _freeProfile,
        ).validate(),
        isEmpty,
      );
    });

    test('reports decreasing positions as unsorted', () {
      final codes = _definition(
        events: const [
          PracticeEvent(
            id: 'later',
            position: BeatPosition(480),
            direction: StrumDirection.down,
          ),
          PracticeEvent(
            id: 'earlier',
            position: BeatPosition(0),
            direction: StrumDirection.up,
          ),
        ],
      ).validate().map((failure) => failure.code);

      expect(codes, contains('events.unsorted'));
    });

    test('reports duplicate event IDs independently of positions', () {
      final codes = _definition(
        events: const [
          PracticeEvent(
            id: 'same',
            position: BeatPosition(0),
            direction: StrumDirection.down,
          ),
          PracticeEvent(
            id: 'same',
            position: BeatPosition(480),
            direction: StrumDirection.up,
          ),
        ],
      ).validate().map((failure) => failure.code);

      expect(codes, contains('events.idDuplicate'));
    });

    test('reports duplicate positions without treating them as unsorted', () {
      final codes = _definition(
        events: const [
          PracticeEvent(
            id: 'first',
            position: BeatPosition(0),
            direction: StrumDirection.down,
          ),
          PracticeEvent(
            id: 'second',
            position: BeatPosition(0),
            direction: StrumDirection.up,
          ),
        ],
      ).validate().map((failure) => failure.code).toList();

      expect(codes, contains('events.positionDuplicate'));
      expect(codes, isNot(contains('events.unsorted')));
    });

    test('rejects positions at and beyond the exclusive totalBeats bound', () {
      for (final ticks in [960, 961]) {
        final codes = _definition(
          totalBeats: const BeatPosition(960),
          events: [
            PracticeEvent(
              id: 'outside',
              position: BeatPosition.fromTicks(ticks),
              direction: StrumDirection.down,
            ),
          ],
        ).validate().map((failure) => failure.code);

        expect(
          codes,
          contains('event.position.outOfRange'),
          reason: '$ticks ticks',
        );
      }
    });

    test('passes nested event failures through unchanged', () {
      final codes = _definition(
        events: const [
          PracticeEvent(id: 'invalid', position: BeatPosition(0), chord: 'Bb'),
        ],
      ).validate().map((failure) => failure.code);

      expect(codes, contains('event.chord.invalid'));
    });

    test('enforces exact mode-to-weight-key compatibility', () {
      expect(_definition().validate(), isEmpty);

      final freeWithWeights = _definition(
        mode: PracticeMode.freePractice,
        scoringProfile: ScoringProfile.legacyLearnParity,
      );
      final wrongStrumKeys = _definition(
        scoringProfile: const ScoringProfile(
          id: 'wrong',
          matchWindow: Duration(milliseconds: 280),
          perfectWindow: Duration(milliseconds: 50),
          goodWindow: Duration(milliseconds: 120),
          extraStrumPolicy: ExtraStrumPolicy.ignore,
          weights: {
            PracticeScoreDimension.rhythm: 60,
            PracticeScoreDimension.chord: 40,
          },
          completionThresholdPercent: 85,
          overallThresholdPercent: 70,
        ),
      );

      expect(
        freeWithWeights.validate().map((failure) => failure.code),
        contains('definition.scoringProfile.incompatibleWithMode'),
      );
      expect(
        wrongStrumKeys.validate().map((failure) => failure.code),
        contains('definition.scoringProfile.incompatibleWithMode'),
      );
    });

    test('displayTitle accepts null and non-blank text, rejects blank', () {
      expect(_definition().validate(), isEmpty);
      expect(
        _definition(displayTitle: 'User-Supplied Title').validate(),
        isEmpty,
      );
      for (final blank in ['', '   ', '\t\n']) {
        expect(
          _definition(
            displayTitle: blank,
          ).validate().map((failure) => failure.code),
          contains('definition.displayTitle.blank'),
          reason: 'blank=$blank must surface the displayTitle failure',
        );
      }
    });
  });

  group('PracticeDefinition value semantics', () {
    test('deeply compares lists and supports Set and Map keys', () {
      final definition = _definition(
        events: const [
          PracticeEvent(
            id: 'one',
            position: BeatPosition(0),
            direction: StrumDirection.down,
          ),
        ],
        skillTags: const ['rhythm', 'beginner'],
      );
      final sameValue = _definition(
        events: const [
          PracticeEvent(
            id: 'one',
            position: BeatPosition(0),
            direction: StrumDirection.down,
          ),
        ],
        skillTags: const ['rhythm', 'beginner'],
      );
      final different = _definition(
        events: const [
          PracticeEvent(
            id: 'one',
            position: BeatPosition(0),
            direction: StrumDirection.down,
          ),
        ],
        skillTags: const ['rhythm'],
      );

      expect(definition, sameValue);
      expect(definition.hashCode, sameValue.hashCode);
      expect(definition, isNot(different));
      expect({definition, sameValue}, hasLength(1));
      expect({definition: 'value'}[sameValue], 'value');
    });
  });
}

const _freeProfile = ScoringProfile(
  id: 'free',
  matchWindow: Duration(milliseconds: 280),
  perfectWindow: Duration(milliseconds: 50),
  goodWindow: Duration(milliseconds: 120),
  extraStrumPolicy: ExtraStrumPolicy.ignore,
  weights: {},
  completionThresholdPercent: 85,
  overallThresholdPercent: 70,
);

PracticeDefinition _definition({
  String id = 'definition',
  int schemaVersion = 1,
  String titleKey = 'practiceTitle',
  String descriptionKey = 'practiceDescription',
  PracticeMode mode = PracticeMode.strumPattern,
  PracticeSource source = PracticeSource.builtin,
  Meter meter = const Meter(beatsPerBar: 4),
  Tempo defaultTempo = const Tempo(120),
  BeatPosition totalBeats = const BeatPosition(960),
  List<PracticeEvent> events = const [
    PracticeEvent(
      id: 'event',
      position: BeatPosition(0),
      direction: StrumDirection.down,
    ),
  ],
  ScoringProfile scoringProfile = ScoringProfile.legacyLearnParity,
  List<String> skillTags = const ['rhythm'],
  String? sourceReference,
  PracticeDifficulty difficulty = PracticeDifficulty.beginner,
  String? displayTitle,
}) => PracticeDefinition(
  id: id,
  schemaVersion: schemaVersion,
  titleKey: titleKey,
  descriptionKey: descriptionKey,
  mode: mode,
  source: source,
  meter: meter,
  defaultTempo: defaultTempo,
  totalBeats: totalBeats,
  events: events,
  scoringProfile: scoringProfile,
  skillTags: skillTags,
  sourceReference: sourceReference,
  difficulty: difficulty,
  displayTitle: displayTitle,
);
