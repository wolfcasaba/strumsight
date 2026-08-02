import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/song_trainer/domain/public.dart';

void main() {
  group('SongValidator — empty / well-formed documents', () {
    test('an empty, well-formed document produces an empty report', () {
      final validator = const SongValidator();
      final report = validator.validate(_sample());
      expect(report.issues, isEmpty);
      expect(report.warnings, isEmpty);
      expect(report.hasFatalIssue, isFalse);
      expect(report.isPersistable, isTrue);
    });

    test('a document with valid chord + monophonic note track is persistable '
        'with no warnings', () {
      final validator = const SongValidator();
      final document = _sample(
        tracks: <SongTrack>[
          ChordTrack(
            id: SongTrackId('c-1'),
            name: 'Chords',
            instrument: SongInstrument(name: 'Guitar'),
            events: <SongChordEvent>[
              SongChordEvent(
                id: SongEventId('e-1'),
                start: Duration.zero,
                duration: const Duration(seconds: 4),
                symbol: const Chord('C'),
              ),
              SongChordEvent(
                id: SongEventId('e-2'),
                start: const Duration(seconds: 4),
                duration: const Duration(seconds: 4),
                symbol: const Chord('Am'),
              ),
            ],
          ),
          NoteTrack(
            id: SongTrackId('n-1'),
            name: 'Lead',
            instrument: SongInstrument(name: 'Guitar'),
            events: <SongNoteEvent>[
              SongNoteEvent(
                id: SongEventId('ne-1'),
                start: Duration.zero,
                duration: const Duration(milliseconds: 500),
                midiPitch: 60,
              ),
              SongNoteEvent(
                id: SongEventId('ne-2'),
                start: const Duration(milliseconds: 500),
                duration: const Duration(milliseconds: 500),
                midiPitch: 64,
              ),
            ],
          ),
        ],
      );
      final report = validator.validate(document);
      expect(report.issues, isEmpty);
      expect(report.warnings, isEmpty);
      expect(report.isPersistable, isTrue);
    });
  });

  group('SongValidator — §6 required matrix (profile × severity)', () {
    test(
      'unknown chord → warning, document still persistable, scoring downgraded',
      () {
        final validator = const SongValidator();
        final document = _sample(
          tracks: <SongTrack>[
            ChordTrack(
              id: SongTrackId('c-1'),
              name: 'Chords',
              instrument: SongInstrument(name: 'Guitar'),
              events: <SongChordEvent>[
                SongChordEvent(
                  id: SongEventId('e-1'),
                  start: Duration.zero,
                  duration: const Duration(seconds: 4),
                  symbol: const Chord('Cmaj7'),
                ),
              ],
            ),
          ],
        );
        final report = validator.validate(document);
        expect(report.issues, hasLength(1));
        expect(report.issues.single.severity, SongValidationSeverity.warning);
        expect(report.issues.single.code, SongValidationCode.chordUnsupported);
        expect(report.warnings, hasLength(1));
        expect(report.warnings.single.code, 'songValidation.chord.unsupported');
        expect(report.isPersistable, isTrue);
        expect(report.hasFatalIssue, isFalse);

        final capability = const SongCapabilityResolver().resolve(
          report: report,
          profile: SongCapabilityProfile.persist,
        );
        expect(capability.canPersist, isTrue);
        expect(capability.canImportPreview, isTrue);
        expect(capability.canTrain, isTrue);
        expect(capability.canExport, isTrue);
        expect(capability.chord.display, isTrue);
        expect(capability.chord.scoring, isFalse);
        expect(capability.chord.hasUnsupportedChord, isTrue);
        expect(capability.pitch.isMonophonic, isTrue);
      },
    );

    test(
      'polyphonic note track → warning, persistable, pitch scoring downgraded',
      () {
        final validator = const SongValidator();
        final document = _sample(
          tracks: <SongTrack>[
            NoteTrack(
              id: SongTrackId('n-1'),
              name: 'Lead',
              instrument: SongInstrument(name: 'Guitar'),
              events: <SongNoteEvent>[
                SongNoteEvent(
                  id: SongEventId('a'),
                  start: Duration.zero,
                  duration: const Duration(milliseconds: 1000),
                  midiPitch: 60,
                ),
                SongNoteEvent(
                  id: SongEventId('b'),
                  start: const Duration(milliseconds: 500),
                  duration: const Duration(milliseconds: 1000),
                  midiPitch: 64,
                ),
              ],
            ),
          ],
        );
        final report = validator.validate(document);
        expect(report.issues, hasLength(1));
        expect(report.issues.single.severity, SongValidationSeverity.warning);
        expect(report.issues.single.code, SongValidationCode.notePolyphonic);
        expect(report.isPersistable, isTrue);

        final capability = const SongCapabilityResolver().resolve(
          report: report,
          profile: SongCapabilityProfile.persist,
        );
        expect(capability.canPersist, isTrue);
        expect(capability.chord.display, isTrue);
        expect(capability.chord.scoring, isTrue);
        expect(capability.pitch.display, isTrue);
        expect(capability.pitch.scoring, isFalse);
        expect(capability.pitch.isMonophonic, isFalse);
      },
    );

    test('fatal: section endMeasureExclusive exceeds document measures ⇒ '
        'persistability false, every capability false', () {
      final validator = const SongValidator();
      final document = _sample(
        sections: <SongSection>[
          SongSection(
            id: SongSectionId('bad'),
            name: 'Bad',
            startMeasure: 0,
            endMeasureExclusive: 5, // > measures.length (=2)
          ),
        ],
        measures: <SongMeasure>[
          SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
          SongMeasure(index: 1, durationBeats: BeatPosition.fromBeats(4)),
        ],
      );
      final report = validator.validate(document);
      expect(report.hasFatalIssue, isTrue);
      expect(report.isPersistable, isFalse);
      expect(
        report.issues.any(
          (issue) =>
              issue.severity == SongValidationSeverity.fatal &&
              issue.code == SongValidationCode.sectionRangeExceedsMeasures,
        ),
        isTrue,
      );

      final capability = const SongCapabilityResolver().resolve(
        report: report,
        profile: SongCapabilityProfile.persist,
      );
      expect(capability.canPersist, isFalse);
      expect(capability.canImportPreview, isFalse);
      expect(capability.canTrain, isFalse);
      expect(capability.canExport, isFalse);
      expect(capability.chord.display, isFalse);
      expect(capability.chord.scoring, isFalse);
      expect(capability.pitch.display, isFalse);
      expect(capability.pitch.scoring, isFalse);
    });

    test('fatal: overlapping sections ⇒ isPersistable false', () {
      final validator = const SongValidator();
      final document = _sample(
        sections: <SongSection>[
          SongSection(
            id: SongSectionId('a'),
            name: 'A',
            startMeasure: 0,
            endMeasureExclusive: 3,
          ),
          SongSection(
            id: SongSectionId('b'),
            name: 'B',
            startMeasure: 2, // overlaps a (ends at 3)
            endMeasureExclusive: 4,
          ),
        ],
        measures: <SongMeasure>[
          SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
          SongMeasure(index: 1, durationBeats: BeatPosition.fromBeats(4)),
          SongMeasure(index: 2, durationBeats: BeatPosition.fromBeats(4)),
          SongMeasure(index: 3, durationBeats: BeatPosition.fromBeats(4)),
        ],
      );
      final report = validator.validate(document);
      expect(report.hasFatalIssue, isTrue);
      expect(
        report.issues.any(
          (issue) =>
              issue.severity == SongValidationSeverity.fatal &&
              issue.code == SongValidationCode.sectionRangeOverlap,
        ),
        isTrue,
      );
    });

    test('fatal: strum.targetChordId missing ⇒ isPersistable false', () {
      final validator = const SongValidator();
      final document = _sample(
        tracks: <SongTrack>[
          StrumTrack(
            id: SongTrackId('s-1'),
            name: 'Strum',
            instrument: SongInstrument(name: 'Guitar'),
            events: <SongStrumEvent>[
              SongStrumEvent(
                id: SongEventId('s-evt-1'),
                at: Duration.zero,
                direction: StrumDirection.down,
                targetChordId: SongEventId('does-not-exist'),
              ),
            ],
          ),
        ],
      );
      final report = validator.validate(document);
      expect(report.hasFatalIssue, isTrue);
      expect(
        report.issues.any(
          (issue) =>
              issue.severity == SongValidationSeverity.fatal &&
              issue.code == SongValidationCode.strumTargetChordMissing,
        ),
        isTrue,
      );
    });

    test('warning: unknown technique on a note ⇒ survives persist', () {
      final validator = const SongValidator();
      final document = _sample(
        tracks: <SongTrack>[
          NoteTrack(
            id: SongTrackId('n-1'),
            name: 'Lead',
            instrument: SongInstrument(name: 'Guitar'),
            events: <SongNoteEvent>[
              SongNoteEvent(
                id: SongEventId('a'),
                start: Duration.zero,
                duration: const Duration(milliseconds: 500),
                midiPitch: 60,
                techniques: <SongNoteTechnique>{
                  SongNoteTechnique.unknown(
                    rawCode: 'fingerstyle.tap',
                    displayText: 'tap',
                  ),
                },
              ),
            ],
          ),
        ],
      );
      final report = validator.validate(document);
      expect(report.issues, hasLength(1));
      expect(report.issues.single.severity, SongValidationSeverity.warning);
      expect(report.issues.single.code, SongValidationCode.techniqueUnknown);
      expect(report.isPersistable, isTrue);
    });

    test('warning: strum direction unknown ⇒ survives persist', () {
      final validator = const SongValidator();
      final document = _sample(
        tracks: <SongTrack>[
          StrumTrack(
            id: SongTrackId('s-1'),
            name: 'Strum',
            instrument: SongInstrument(name: 'Guitar'),
            events: <SongStrumEvent>[
              SongStrumEvent(
                id: SongEventId('e-1'),
                at: Duration.zero,
                direction: null, // unknown direction
              ),
            ],
          ),
        ],
      );
      final report = validator.validate(document);
      expect(report.issues, hasLength(1));
      expect(report.issues.single.severity, SongValidationSeverity.warning);
      expect(
        report.issues.single.code,
        SongValidationCode.strumDirectionUnknown,
      );
      expect(report.isPersistable, isTrue);
    });
  });

  group('SongValidator — determinism', () {
    test('two validations of the same document produce an equal report', () {
      final validator = const SongValidator();
      final document = _sample(
        tracks: <SongTrack>[
          ChordTrack(
            id: SongTrackId('c-1'),
            name: 'Chords',
            instrument: SongInstrument(name: 'Guitar'),
            events: <SongChordEvent>[
              SongChordEvent(
                id: SongEventId('e-1'),
                start: Duration.zero,
                duration: const Duration(seconds: 4),
                symbol: const Chord('Cmaj7'),
              ),
              SongChordEvent(
                id: SongEventId('e-2'),
                start: const Duration(seconds: 4),
                duration: const Duration(seconds: 4),
                symbol: const Chord('G'),
              ),
            ],
          ),
        ],
      );
      final first = validator.validate(document);
      final second = validator.validate(document);
      expect(first, equals(second));
      expect(first.hashCode, second.hashCode);
    });

    test('issues are sorted: fatal before warning, then code ascending', () {
      final validator = const SongValidator();
      final document = _sample(
        sections: <SongSection>[
          SongSection(
            id: SongSectionId('bad'),
            name: 'Bad',
            startMeasure: 0,
            endMeasureExclusive: 99, // fatal
          ),
        ],
        measures: <SongMeasure>[
          SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
        ],
        tracks: <SongTrack>[
          ChordTrack(
            id: SongTrackId('c-1'),
            name: 'Chords',
            instrument: SongInstrument(name: 'Guitar'),
            events: <SongChordEvent>[
              SongChordEvent(
                id: SongEventId('e-1'),
                start: Duration.zero,
                duration: const Duration(seconds: 4),
                symbol: const Chord('Cmaj7'), // warning
              ),
            ],
          ),
        ],
      );
      final report = validator.validate(document);
      // Fatal must come before warning.
      expect(report.issues.first.severity, SongValidationSeverity.fatal);
      expect(report.issues.last.severity, SongValidationSeverity.warning);
      // Within the same severity, codes are sorted ascending.
      final fatalCodes = report.issues
          .where((issue) => issue.severity == SongValidationSeverity.fatal)
          .map((issue) => issue.code)
          .toList();
      final warningCodes = report.issues
          .where((issue) => issue.severity == SongValidationSeverity.warning)
          .map((issue) => issue.code)
          .toList();
      expect(fatalCodes, equals(List<String>.of(fatalCodes)..sort()));
      expect(warningCodes, equals(List<String>.of(warningCodes)..sort()));
    });
  });

  group('songTrainerChordRootIsSupported — canonical grammar', () {
    test('accepts sharp-spelled major roots', () {
      for (final root in const ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G']) {
        expect(
          songTrainerChordRootIsSupported(root),
          isTrue,
          reason: 'root "$root" should be supported',
        );
      }
    });

    test('accepts flat-spelled roots via the canonical grammar', () {
      for (final root in const ['Db', 'Eb', 'Gb', 'Ab', 'Bb', 'Cb', 'Fb']) {
        expect(
          songTrainerChordRootIsSupported(root),
          isTrue,
          reason: 'root "$root" should be supported',
        );
      }
    });

    test('accepts slash chords via the parent root', () {
      expect(songTrainerChordRootIsSupported('G/B'), isTrue);
      expect(songTrainerChordRootIsSupported('C/E'), isTrue);
    });

    test('rejects unsupported / unknown chords', () {
      expect(songTrainerChordRootIsSupported('Cmaj7'), isFalse);
      expect(songTrainerChordRootIsSupported('G7'), isFalse);
      expect(songTrainerChordRootIsSupported('H'), isFalse);
      expect(songTrainerChordRootIsSupported(''), isFalse);
      expect(songTrainerChordRootIsSupported('X'), isFalse);
      expect(songTrainerChordRootIsSupported('foo'), isFalse);
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

SongDocument _sample({
  List<SongTrack>? tracks,
  List<SongSection>? sections,
  List<SongMeasure>? measures,
}) {
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('song-001'),
    revision: 1,
    metadata: SongMetadata(title: 'Test'),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: 'song.strum',
      sha256: 'a' * 64,
      importedAt: DateTime.utc(2026, 1, 1, 12),
      importerVersion: '1.0.0',
    ),
    tracks: tracks,
    sections: sections,
    measures: measures,
    createdAt: DateTime.utc(2026, 1, 1, 12),
    updatedAt: DateTime.utc(2026, 1, 2, 12),
  );
}
