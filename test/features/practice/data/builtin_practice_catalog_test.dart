import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/data/builtin_practice_catalog.dart';
import 'package:strumsight/features/practice/domain/model/beat_position.dart';
import 'package:strumsight/features/practice/domain/model/practice_difficulty.dart';
import 'package:strumsight/features/practice/domain/model/practice_mode.dart';
import 'package:strumsight/features/practice/domain/model/scoring_profile.dart';

const _expectedIds = <String>[
  'builtin.quarterDownstrokes.v1',
  'builtin.alternatingEighths.v1',
  'builtin.folkPattern.v1',
  'builtin.gToDChanges.v1',
  'builtin.emToCChanges.v1',
  'builtin.cGAmFProgression.v1',
  'builtin.firstWaltz.v1',
  'builtin.syncopatedUps.v1',
  'builtin.rhythmOnlyQuarters.v1',
  'builtin.freePracticeTemplate.v1',
];

void main() {
  const catalog = BuiltinPracticeCatalog();

  group('BuiltinPracticeCatalog', () {
    test('contains exactly ten definitions in pinned ID order', () {
      final all = catalog.all();

      expect(all, hasLength(10));
      expect(all.map((d) => d.id).toList(), _expectedIds);
    });

    test('every definition validates with no failures', () {
      for (final definition in catalog.all()) {
        final failures = definition.validate();
        expect(
          failures.map((f) => '${definition.id}: ${f.code}').toList(),
          isEmpty,
          reason: 'Definition ${definition.id} must validate cleanly.',
        );
      }
    });

    test('definition IDs are globally unique', () {
      final ids = catalog.all().map((d) => d.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('all() returns the same order on repeated calls', () {
      final first = catalog.all().map((d) => d.id).toList();
      final second = catalog.all().map((d) => d.id).toList();
      final third = catalog.all().map((d) => d.id).toList();

      expect(second, first);
      expect(third, first);
    });

    test('byId returns the pinned definition and null for unknown IDs', () {
      expect(
        catalog.byId('builtin.alternatingEighths.v1')?.id,
        'builtin.alternatingEighths.v1',
      );
      expect(catalog.byId('does.not.exist'), isNull);
      expect(catalog.byId(''), isNull);
    });

    test('byMode returns only definitions of the requested mode', () {
      final strumPatternIds = catalog
          .byMode(PracticeMode.strumPattern)
          .map((d) => d.id)
          .toList();
      final chordChangesIds = catalog
          .byMode(PracticeMode.chordChanges)
          .map((d) => d.id)
          .toList();
      final chordProgressionIds = catalog
          .byMode(PracticeMode.chordProgression)
          .map((d) => d.id)
          .toList();
      final rhythmOnlyIds = catalog
          .byMode(PracticeMode.rhythmOnly)
          .map((d) => d.id)
          .toList();
      final freePracticeIds = catalog
          .byMode(PracticeMode.freePractice)
          .map((d) => d.id)
          .toList();

      expect(strumPatternIds, [
        'builtin.quarterDownstrokes.v1',
        'builtin.alternatingEighths.v1',
        'builtin.folkPattern.v1',
        'builtin.firstWaltz.v1',
        'builtin.syncopatedUps.v1',
      ]);
      expect(chordChangesIds, [
        'builtin.gToDChanges.v1',
        'builtin.emToCChanges.v1',
      ]);
      expect(chordProgressionIds, ['builtin.cGAmFProgression.v1']);
      expect(rhythmOnlyIds, ['builtin.rhythmOnlyQuarters.v1']);
      expect(freePracticeIds, ['builtin.freePracticeTemplate.v1']);

      for (final ids in [
        strumPatternIds,
        chordChangesIds,
        chordProgressionIds,
        rhythmOnlyIds,
        freePracticeIds,
      ]) {
        expect(ids.toSet(), hasLength(ids.length));
      }
    });

    test(
      'byDifficulty returns only definitions of the requested difficulty',
      () {
        final beginner = catalog
            .byDifficulty(PracticeDifficulty.beginner)
            .map((d) => d.id)
            .toList();
        final intermediate = catalog
            .byDifficulty(PracticeDifficulty.intermediate)
            .map((d) => d.id)
            .toList();

        expect(beginner, contains('builtin.quarterDownstrokes.v1'));
        expect(beginner, contains('builtin.firstWaltz.v1'));
        expect(beginner, isNot(contains('builtin.cGAmFProgression.v1')));
        expect(intermediate, [
          'builtin.cGAmFProgression.v1',
          'builtin.syncopatedUps.v1',
        ]);
        expect(catalog.byDifficulty(PracticeDifficulty.advanced), isEmpty);
      },
    );

    test('firstWaltz is 3/4 with twelve total beats on the quarter grid', () {
      final waltz = catalog.byId('builtin.firstWaltz.v1')!;

      expect(waltz.meter.beatsPerBar, 3);
      expect(waltz.totalBeats.ticks, 12 * BeatPosition.ticksPerBeat);
      for (final event in waltz.events) {
        expect(
          event.position.ticks % BeatPosition.ticksPerBeat,
          0,
          reason: 'Waltz event ${event.id} must sit on a quarter beat.',
        );
      }
      expect(waltz.events, hasLength(12));
      // Per bar: D on beat 1, U on beats 2 and 3.
      for (var bar = 0; bar < 4; bar++) {
        final base = bar * 3;
        expect(waltz.events[base].direction, StrumDirection.down);
        expect(waltz.events[base + 1].direction, StrumDirection.up);
        expect(waltz.events[base + 2].direction, StrumDirection.up);
      }
    });

    test('titleKey and descriptionKey follow the practiceCatalog regex', () {
      final pattern = RegExp(
        r'^practiceCatalog[A-Z][A-Za-z0-9]*(Title|Description)$',
      );
      for (final definition in catalog.all()) {
        expect(
          pattern.hasMatch(definition.titleKey),
          isTrue,
          reason: 'titleKey for ${definition.id} must match the catalog regex.',
        );
        expect(
          pattern.hasMatch(definition.descriptionKey),
          isTrue,
          reason:
              'descriptionKey for ${definition.id} must match the catalog regex.',
        );
      }
    });

    test(
      'free-practice template has no events and an open scoring profile',
      () {
        final free = catalog.byId('builtin.freePracticeTemplate.v1')!;

        expect(free.events, isEmpty);
        expect(free.scoringProfile.id, ScoringProfile.freePracticeOpen.id);
        expect(free.scoringProfile.weights, isEmpty);
      },
    );

    test('strumPattern events carry no chord and chordChanges events do', () {
      for (final definition in catalog.all()) {
        if (definition.mode == PracticeMode.strumPattern ||
            definition.mode == PracticeMode.rhythmOnly) {
          for (final event in definition.events) {
            expect(
              event.chord,
              isNull,
              reason:
                  '${definition.id}.${event.id} must not declare a chord in '
                  '${definition.mode.code} mode.',
            );
          }
        }
        if (definition.mode == PracticeMode.chordChanges ||
            definition.mode == PracticeMode.chordProgression) {
          for (final event in definition.events) {
            expect(
              event.chord,
              isNotNull,
              reason:
                  '${definition.id}.${event.id} must carry a chord in '
                  '${definition.mode.code} mode.',
            );
            expect(
              event.direction,
              isNotNull,
              reason:
                  '${definition.id}.${event.id} must carry a direction in '
                  '${definition.mode.code} mode.',
            );
          }
        }
      }
    });
  });

  group('BuiltinPracticeCatalog data layer purity', () {
    test(
      'source forbids ambient IO, randomness, framework, and l10n imports',
      () {
        final file = File(
          'lib/features/practice/data/builtin_practice_catalog.dart',
        );
        expect(file.existsSync(), isTrue);

        final forbidden = <String, RegExp>{
          'ambient wall clock': RegExp(r'\bDateTime\s*\.\s*now\s*\('),
          'ambient stopwatch': RegExp(r'\bStopwatch\s*\('),
          'ambient randomness': RegExp(r'\bRandom(?:\s*\.\s*secure)?\s*\('),
          'console output': RegExp(r'\bprint\s*\('),
          'framework or storage import': RegExp(
            r'''import\s+['"]package:(?:flutter(?:/|_)|[^/'"]*riverpod[^/'"]*/|dio/|shared_preferences/)''',
          ),
          'localization import': RegExp(
            r'''import\s+['"][^'"]*l10n(?:/|\.dart)''',
          ),
        };

        final source = file.readAsStringSync();
        final violations = <String>[];
        for (final entry in forbidden.entries) {
          if (entry.value.hasMatch(source)) {
            violations.add(entry.key);
          }
        }

        expect(
          violations,
          isEmpty,
          reason: 'Data-layer purity violations: ${violations.join(', ')}',
        );
      },
    );
  });

  group('BuiltinPracticeCatalog PracticeDefinition integrity', () {
    test('event IDs are unique within every definition', () {
      for (final definition in catalog.all()) {
        final ids = definition.events.map((e) => e.id).toList();
        expect(
          ids.toSet(),
          hasLength(ids.length),
          reason:
              'Duplicate event ids inside ${definition.id}: '
              '${definition.events.map((e) => e.id).toList()}',
        );
      }
    });
  });
}
