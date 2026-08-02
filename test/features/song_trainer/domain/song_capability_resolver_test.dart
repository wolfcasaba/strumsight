import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/domain/public.dart';

void main() {
  const resolver = SongCapabilityResolver();

  group('SongCapabilityResolver — §6 acceptance matrix', () {
    test(
      'valid chord + monophonic note ⇒ full capability on every profile',
      () {
        final report = SongValidationReport.empty;
        for (final profile in SongCapabilityProfile.values) {
          final capability = resolver.resolve(report: report, profile: profile);
          expect(
            capability.canPersist,
            isTrue,
            reason: 'profile ${profile.code} should be persistable',
          );
          expect(capability.canImportPreview, isTrue);
          expect(capability.canTrain, isTrue);
          expect(capability.canExport, isTrue);
          expect(capability.chord.display, isTrue);
          expect(capability.chord.scoring, isTrue);
          expect(capability.chord.hasUnsupportedChord, isFalse);
          expect(capability.pitch.display, isTrue);
          expect(capability.pitch.scoring, isTrue);
          expect(capability.pitch.isMonophonic, isTrue);
        }
      },
    );

    test('unknown chord ⇒ persistable + preview + warning; chord-scoring '
        'downgraded, pitch axis untouched', () {
      final report = const SongValidationReport(
        issues: <SongValidationIssue>[
          SongValidationIssue(
            severity: SongValidationSeverity.warning,
            code: SongValidationCode.chordUnsupported,
            message: 'unsupported chord "Cmaj7"',
          ),
        ],
        warnings: <ImportWarning>[
          ImportWarning(
            code: 'songValidation.chord.unsupported',
            message: 'unsupported chord "Cmaj7"',
          ),
        ],
      );
      final capability = resolver.resolve(
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
      expect(capability.pitch.display, isTrue);
      expect(capability.pitch.scoring, isTrue);
      expect(capability.pitch.isMonophonic, isTrue);
    });

    test('polyphonic note ⇒ persistable, pitch scoring downgraded, '
        'chord axis untouched', () {
      final report = const SongValidationReport(
        issues: <SongValidationIssue>[
          SongValidationIssue(
            severity: SongValidationSeverity.warning,
            code: SongValidationCode.notePolyphonic,
            message: 'polyphonic',
          ),
        ],
        warnings: <ImportWarning>[
          ImportWarning(
            code: 'songValidation.note.polyphonic',
            message: 'polyphonic',
          ),
        ],
      );
      final capability = resolver.resolve(
        report: report,
        profile: SongCapabilityProfile.persist,
      );
      expect(capability.canPersist, isTrue);
      expect(capability.canImportPreview, isTrue);
      expect(capability.canTrain, isTrue);
      expect(capability.canExport, isTrue);
      expect(capability.chord.display, isTrue);
      expect(capability.chord.scoring, isTrue);
      expect(capability.chord.hasUnsupportedChord, isFalse);
      expect(capability.pitch.display, isTrue);
      expect(capability.pitch.scoring, isFalse);
      expect(capability.pitch.isMonophonic, isFalse);
    });

    test('fatal range/map ⇒ persistability false, every capability false', () {
      final report = const SongValidationReport(
        issues: <SongValidationIssue>[
          SongValidationIssue(
            severity: SongValidationSeverity.fatal,
            code: SongValidationCode.sectionRangeExceedsMeasures,
            message: 'bad',
          ),
        ],
        warnings: <ImportWarning>[],
      );
      final capability = resolver.resolve(
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
  });

  group('SongCapabilityResolver — per-profile independence', () {
    test('every profile agrees on canPersist for the same report', () {
      final report = const SongValidationReport(
        issues: <SongValidationIssue>[
          SongValidationIssue(
            severity: SongValidationSeverity.fatal,
            code: SongValidationCode.strumTargetChordMissing,
            message: 'missing',
          ),
        ],
        warnings: <ImportWarning>[],
      );
      final seen = <bool>{};
      for (final profile in SongCapabilityProfile.values) {
        final capability = resolver.resolve(report: report, profile: profile);
        seen.add(capability.canPersist);
      }
      expect(seen, equals(<bool>{false}));
    });

    test('warning-level issues never flip canPersist across any profile', () {
      final report = const SongValidationReport(
        issues: <SongValidationIssue>[
          SongValidationIssue(
            severity: SongValidationSeverity.warning,
            code: SongValidationCode.strumDirectionUnknown,
            message: 'unknown direction',
          ),
        ],
        warnings: <ImportWarning>[
          ImportWarning(
            code: 'songValidation.strum.directionUnknown',
            message: 'unknown direction',
          ),
        ],
      );
      for (final profile in SongCapabilityProfile.values) {
        final capability = resolver.resolve(report: report, profile: profile);
        expect(
          capability.canPersist,
          isTrue,
          reason: 'profile ${profile.code} should remain persistable',
        );
      }
    });
  });

  group('SongCapabilityResolver — determinism', () {
    test('two resolves with the same inputs return equal reports', () {
      final report = const SongValidationReport(
        issues: <SongValidationIssue>[
          SongValidationIssue(
            severity: SongValidationSeverity.warning,
            code: SongValidationCode.chordUnsupported,
            message: 'unsupported',
          ),
          SongValidationIssue(
            severity: SongValidationSeverity.warning,
            code: SongValidationCode.notePolyphonic,
            message: 'polyphonic',
          ),
        ],
        warnings: <ImportWarning>[
          ImportWarning(
            code: 'songValidation.chord.unsupported',
            message: 'unsupported',
          ),
          ImportWarning(
            code: 'songValidation.note.polyphonic',
            message: 'polyphonic',
          ),
        ],
      );
      final a = resolver.resolve(
        report: report,
        profile: SongCapabilityProfile.trainer,
      );
      final b = resolver.resolve(
        report: report,
        profile: SongCapabilityProfile.trainer,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('SongCapabilityProfile — code round-trip', () {
    test('every enum value round-trips through its code', () {
      for (final profile in SongCapabilityProfile.values) {
        final decoded = songCapabilityProfileFromCode(profile.code);
        expect(decoded, equals(profile));
      }
    });

    test('unknown profile code returns null (fail closed)', () {
      expect(songCapabilityProfileFromCode('wat'), isNull);
    });
  });
}
