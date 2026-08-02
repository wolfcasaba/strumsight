/// Stable, side-effect-free document validator (E03-R05, ADR 0114
/// §Döntés 2 + §Döntés 3, SDD §7 + §12).
///
/// The validator never throws. It scans a [SongDocument] for issues
/// the per-model constructors cannot see on their own
/// (cross-collection consistency) and for structural warnings the
/// capability resolver later translates into per-axis scoring
/// downgrades. The output is a [SongValidationReport] — an immutable
/// record with deterministic ordering, so two calls on equal
/// documents return equal reports (§6 acceptance: "Validator
/// ismeretlen/rossz inputnál reportot ad, nem nyers exceptiont").
///
/// The validator is **framework-independent**: no Flutter, Riverpod,
/// Dio, SharedPreferences, l10n or storage plugin import is allowed.
library;

import 'package:meta/meta.dart';

import '../models/import_warning.dart';
import '../models/song_document.dart';
import '../models/song_track.dart';
import '../models/song_validation_report.dart';
import 'note_track_analyzer.dart';

/// Recognised chord root spellings (ADR 0114 §Döntés 1 — domain-local
/// grammar, never the practice-feature dictionary).
///
/// The set covers every spelling the [Chord.transposeLabel] can
/// parse as a root, plus an explicit `H` rejection (the German
/// notation). The capability resolver layers quality-classification
/// (maj / min) on top of this set.
const Set<String> _recognizedChordRoots = <String>{
  'C',
  'C#',
  'Db',
  'D',
  'D#',
  'Eb',
  'E',
  'Fb',
  'F',
  'E#',
  'F#',
  'Gb',
  'G',
  'G#',
  'Ab',
  'A',
  'A#',
  'Bb',
  'B',
  'Cb',
  'B#',
};

/// True when [label] is one of the canonical sharp-spelled major /
/// minor chords the Song Trainer supports.
///
/// The grammar is `Root[sharp|flat](m?)` — root letter plus an
/// optional accidental, optionally followed by a single `m` for
/// minor. Extended chords (`maj7`, `7`, `sus4`, `add9`, …), suspended
/// chords (`sus`), slashed inversions (`G/B`) handled at the root,
/// diminished / augmented (`dim`, `aug`), and any non-canonical
/// quality suffix are classified as unsupported. ADR 0114 §Döntés 1
/// explicitly rejects the practice-feature dictionary as a source of
/// truth — this grammar is independent.
bool songTrainerChordRootIsSupported(String label) {
  if (label.isEmpty) return false;
  // Drop the slash-bass portion ("G/B" → "G") so a slash chord
  // collapses to its parent root for capability purposes. The bass
  // note is not scored independently; the parent chord is.
  final slash = label.indexOf('/');
  final head = slash >= 0 ? label.substring(0, slash) : label;
  final trimmed = head.trim();
  if (trimmed.isEmpty) return false;
  // Reject `H` outright — the German notation is not in the supported
  // root set (the importer would have already translated to a sharp
  // spelling if that translation existed).
  if (trimmed[0] == 'H') return false;
  // Root = first letter plus an optional accidental.
  var rootLen = 1;
  if (trimmed.length > 1 && (trimmed[1] == '#' || trimmed[1] == 'b')) {
    rootLen = 2;
  }
  final root = trimmed.substring(0, rootLen);
  if (!_recognizedChordRoots.contains(root)) return false;
  // Quality suffix: only the empty string (major) or a single `m`
  // (minor) is recognised.
  final suffix = trimmed.substring(rootLen);
  if (suffix.isEmpty) return true; // major
  if (suffix == 'm') return true; // minor
  return false;
}

/// Pure, deterministic [SongDocument] validator (E03-R05).
@immutable
final class SongValidator {
  /// Constructs a validator that reuses the given [analyzer] for
  /// note-track polyphony detection. The analyzer is a pure,
  /// side-effect-free collaborator (E03-R04).
  const SongValidator({this.analyzer = const NoteTrackAnalyzer()});

  /// The note-track analyzer the validator delegates to for
  /// polyphony detection. Pure and deterministic.
  final NoteTrackAnalyzer analyzer;

  /// Validates [document] and returns a stable [SongValidationReport].
  ///
  /// The validator never throws — every malformed state the
  /// per-model constructors accepted (because they did not see the
  /// cross-collection data) is surfaced here as a fatal issue. The
  /// returned issues list is sorted by `severity asc, code asc`; the
  /// projected warnings list is sorted by `code asc`. The output is
  /// deterministic: equal documents produce equal reports.
  SongValidationReport validate(SongDocument document) {
    final issues = <SongValidationIssue>[
      ..._validateSections(document),
      ..._validateTracks(document),
    ];

    // Deterministic ordering: fatal before warning, then code asc.
    issues.sort((a, b) {
      final severityCompare = a.severity.index.compareTo(b.severity.index);
      if (severityCompare != 0) return severityCompare;
      return a.code.compareTo(b.code);
    });

    final warnings =
        issues
            .where((issue) => issue.severity == SongValidationSeverity.warning)
            .map(_projectWarning)
            .toList()
          ..sort((a, b) => a.code.compareTo(b.code));

    return SongValidationReport(
      issues: List<SongValidationIssue>.unmodifiable(issues),
      warnings: List<ImportWarning>.unmodifiable(warnings),
    );
  }

  List<SongValidationIssue> _validateSections(SongDocument document) {
    final issues = <SongValidationIssue>[];
    final measureCount = document.measures.length;
    final sections = document.sections;
    for (final section in sections) {
      if (section.endMeasureExclusive > measureCount) {
        issues.add(
          SongValidationIssue(
            severity: SongValidationSeverity.fatal,
            code: SongValidationCode.sectionRangeExceedsMeasures,
            message:
                'Section "${section.id.value}" ends at measure '
                '${section.endMeasureExclusive} but the document only has '
                '$measureCount measure(s).',
          ),
        );
      }
    }
    // Detect overlapping section ranges (visible only at document
    // level — each constructor sees only its own state).
    final ordered = sections.toList()
      ..sort((a, b) => a.startMeasure.compareTo(b.startMeasure));
    for (var i = 1; i < ordered.length; i++) {
      final previous = ordered[i - 1];
      final current = ordered[i];
      if (current.startMeasure < previous.endMeasureExclusive) {
        issues.add(
          SongValidationIssue(
            severity: SongValidationSeverity.fatal,
            code: SongValidationCode.sectionRangeOverlap,
            message:
                'Section "${current.id.value}" starts at measure '
                '${current.startMeasure} but overlaps with section '
                '"${previous.id.value}" which ends at measure '
                '${previous.endMeasureExclusive}.',
          ),
        );
      }
    }
    return issues;
  }

  List<SongValidationIssue> _validateTracks(SongDocument document) {
    final issues = <SongValidationIssue>[];
    final chordEventIds = <String>{};
    for (final track in document.tracks) {
      if (track is ChordTrack) {
        for (final event in track.events) {
          chordEventIds.add(event.id.value);
          if (!songTrainerChordRootIsSupported(event.symbol.label)) {
            issues.add(
              SongValidationIssue(
                severity: SongValidationSeverity.warning,
                code: SongValidationCode.chordUnsupported,
                message:
                    'Chord event "${event.id.value}" uses an unsupported '
                    'chord symbol "${event.symbol.label}".',
              ),
            );
          }
        }
      } else if (track is NoteTrack) {
        final analysis = analyzer.analyze(track.events);
        if (!analysis.isMonophonic) {
          issues.add(
            SongValidationIssue(
              severity: SongValidationSeverity.warning,
              code: SongValidationCode.notePolyphonic,
              message:
                  'Note track "${track.id.value}" is polyphonic '
                  '(${analysis.overlapCount} overlapping pitch pair(s)); '
                  'pitch scoring is downgraded.',
            ),
          );
        }
        for (final note in track.events) {
          for (final technique in note.techniques) {
            if (!technique.isKnown) {
              issues.add(
                SongValidationIssue(
                  severity: SongValidationSeverity.warning,
                  code: SongValidationCode.techniqueUnknown,
                  message:
                      'Note event "${note.id.value}" uses unknown technique '
                      '"${technique.rawCode}"; the technique is preserved '
                      'on disk but the affected note is unscored.',
                ),
              );
            }
          }
        }
      } else if (track is StrumTrack) {
        for (final event in track.events) {
          final target = event.targetChordId;
          if (target != null && !chordEventIds.contains(target.value)) {
            issues.add(
              SongValidationIssue(
                severity: SongValidationSeverity.fatal,
                code: SongValidationCode.strumTargetChordMissing,
                message:
                    'Strum event "${event.id.value}" points to missing '
                    'chord event "${target.value}".',
              ),
            );
          }
          if (event.direction == null) {
            issues.add(
              SongValidationIssue(
                severity: SongValidationSeverity.warning,
                code: SongValidationCode.strumDirectionUnknown,
                message:
                    'Strum event "${event.id.value}" has no determinate '
                    'direction; rhythm scoring survives, direction '
                    'scoring is downgraded for this event.',
              ),
            );
          }
        }
      }
    }
    return issues;
  }

  /// Project a non-fatal [SongValidationIssue] into the typed
  /// [ImportWarning] shape consumed by the import preview UI. The
  /// projection is one-to-one on `code`; severities are dropped here
  /// because the warning surface is, by definition, non-fatal only.
  ImportWarning _projectWarning(SongValidationIssue issue) {
    return ImportWarning(code: issue.code, message: issue.message);
  }
}
