import 'package:meta/meta.dart';

import '../models/song_event.dart';
import '../models/song_track.dart';

/// Stable machine-readable codes attached to a [NoteTrackAnalysis.warning].
abstract final class NoteTrackAnalysisWarningCode {
  /// A `tieGroupId` spanned notes with mismatched MIDI pitches — a tie
  /// implies the same pitch; the importer fed us an inconsistent reading.
  static const String tieGroupPitchMismatch =
      'noteTrackAnalysis.tieGroup.pitchMismatch';
}

/// One human-readable warning produced by [NoteTrackAnalyzer].
@immutable
final class NoteTrackAnalysisWarning {
  const NoteTrackAnalysisWarning(this.code, this.message);

  /// Stable, machine-readable code (one of
  /// [NoteTrackAnalysisWarningCode]'s constants).
  final String code;

  /// Displayable, locale-independent English message — the UI maps it to
  /// a localised string at display time.
  final String message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NoteTrackAnalysisWarning &&
          other.code == code &&
          other.message == message;

  @override
  int get hashCode => Object.hash(code, message);
}

/// Result of [NoteTrackAnalyzer.analyze] (SDD §11.5).
///
/// The analyzer reports structural facts about a note track — overlap,
/// tie candidate count, pitch range — without taking a position on
/// scoring: the capability resolver (a future round) translates these
/// facts into "this track supports pitch scoring yes/no" statements.
@immutable
final class NoteTrackAnalysis {
  const NoteTrackAnalysis({
    required this.isMonophonic,
    required this.overlapCount,
    required this.tieCandidateCount,
    required this.lowestPitch,
    required this.highestPitch,
    required this.noteCount,
    required this.warnings,
  });

  /// `true` when no two notes overlap on the timeline with different
  /// pitches — the canonical definition of "this track can be scored as
  /// monophonic" (SDD §11.5).
  final bool isMonophonic;

  /// Number of overlapping same-timeline events whose pitches differ.
  /// Tie candidates (same-pitch overlap) are reported separately.
  final int overlapCount;

  /// Number of overlapping events whose pitches are identical — these
  /// are candidates the analyzer flags but NEVER merges (§5 kötött
  /// döntés 4).
  final int tieCandidateCount;

  /// Lowest MIDI pitch observed in the input. `null` for an empty track.
  final int? lowestPitch;

  /// Highest MIDI pitch observed in the input. `null` for an empty track.
  final int? highestPitch;

  /// Total number of notes fed to the analyzer.
  final int noteCount;

  /// Non-fatal warnings (e.g. inconsistent tie groups). The capability
  /// resolver surfaces these as soft UI hints.
  final List<NoteTrackAnalysisWarning> warnings;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NoteTrackAnalysis) return false;
    if (other.isMonophonic != isMonophonic ||
        other.overlapCount != overlapCount ||
        other.tieCandidateCount != tieCandidateCount ||
        other.lowestPitch != lowestPitch ||
        other.highestPitch != highestPitch ||
        other.noteCount != noteCount ||
        other.warnings.length != warnings.length) {
      return false;
    }
    for (var index = 0; index < warnings.length; index++) {
      if (other.warnings[index] != warnings[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    isMonophonic,
    overlapCount,
    tieCandidateCount,
    lowestPitch,
    highestPitch,
    noteCount,
    Object.hashAll(warnings),
  );
}

/// Pure, deterministic analyzer for a [NoteTrack] (SDD §11.5).
///
/// The analyzer is a value-in / value-out function. It never mutates the
/// events it is handed; the canonical event ordering required by §5
/// kötött döntés 1 — start asc, track id, event id — is computed on a
/// defensive copy so the caller's list is observable bit-for-bit after
/// the call returns.
final class NoteTrackAnalyzer {
  const NoteTrackAnalyzer();

  /// Analyze the [events] list and return a [NoteTrackAnalysis].
  ///
  /// The input is NOT mutated. The analyzer is deterministic — two calls
  /// with equal input lists return equal reports.
  NoteTrackAnalysis analyze(List<SongNoteEvent> events) {
    final noteCount = events.length;
    if (noteCount == 0) {
      return const NoteTrackAnalysis(
        isMonophonic: true,
        overlapCount: 0,
        tieCandidateCount: 0,
        lowestPitch: null,
        highestPitch: null,
        noteCount: 0,
        warnings: <NoteTrackAnalysisWarning>[],
      );
    }

    // Defensive canonical sort — start asc, then event id asc. The list
    // is a shallow copy; the SongNoteEvent instances are immutable.
    final ordered = List<SongNoteEvent>.of(events)
      ..sort((a, b) {
        final startCompare = a.start.compareTo(b.start);
        if (startCompare != 0) return startCompare;
        return a.id.value.compareTo(b.id.value);
      });

    var lowestPitch = ordered.first.midiPitch;
    var highestPitch = ordered.first.midiPitch;
    for (final note in ordered) {
      if (note.midiPitch < lowestPitch) lowestPitch = note.midiPitch;
      if (note.midiPitch > highestPitch) highestPitch = note.midiPitch;
    }

    var overlapCount = 0;
    var tieCandidateCount = 0;
    final activeNotes = <SongNoteEvent>[];
    for (final curr in ordered) {
      // End == start is a boundary, not an overlap, so remove all notes
      // ending at or before this onset before comparing active intervals.
      activeNotes.removeWhere(
        (note) => note.start + note.duration <= curr.start,
      );
      for (final active in activeNotes) {
        if (curr.midiPitch == active.midiPitch) {
          // Same-pitch overlap → merge candidate. §5 kötött döntés 4
          // forbids the analyzer from auto-merging.
          tieCandidateCount++;
        } else {
          overlapCount++;
        }
      }
      activeNotes.add(curr);
    }

    final warnings = _collectWarnings(ordered);

    return NoteTrackAnalysis(
      isMonophonic: overlapCount == 0,
      overlapCount: overlapCount,
      tieCandidateCount: tieCandidateCount,
      lowestPitch: lowestPitch,
      highestPitch: highestPitch,
      noteCount: noteCount,
      warnings: List<NoteTrackAnalysisWarning>.unmodifiable(warnings),
    );
  }

  /// Convenience wrapper: extracts [NoteTrack.events] and calls [analyze].
  /// The track is read-only; this does not modify its event list.
  NoteTrackAnalysis analyzeTrack(NoteTrack track) => analyze(track.events);

  /// Group notes by tieGroupId; emit a warning for any group that
  /// contains notes with differing MIDI pitches (SDD §11.4 tie consistency
  /// rule).
  List<NoteTrackAnalysisWarning> _collectWarnings(List<SongNoteEvent> ordered) {
    final Map<String, List<SongNoteEvent>> byGroup =
        <String, List<SongNoteEvent>>{};
    for (final note in ordered) {
      final group = note.tieGroupId;
      if (group == null) continue;
      byGroup.putIfAbsent(group, () => <SongNoteEvent>[]).add(note);
    }
    final result = <NoteTrackAnalysisWarning>[];
    for (final entry in byGroup.entries) {
      final pitches = entry.value.map((n) => n.midiPitch).toSet();
      if (pitches.length > 1) {
        result.add(
          NoteTrackAnalysisWarning(
            NoteTrackAnalysisWarningCode.tieGroupPitchMismatch,
            'Tie group "${entry.key}" spans notes with different MIDI pitches '
            '(${pitches.toList()..sort()}).',
          ),
        );
      }
    }
    return result;
  }
}
