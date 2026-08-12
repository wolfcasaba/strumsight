import 'expected_event.dart';

/// Origin of an immutable [AnalysisTarget] snapshot.
enum AnalysisTargetKind { practice, song, custom }

/// Timeline that owns the timestamps in an [AnalysisTarget].
enum AnalysisTargetTimebase { session, media }

/// A named interval in an [AnalysisTarget] timeline.
final class AnalysisTargetSection {
  AnalysisTargetSection({
    required this.id,
    required this.start,
    required this.end,
  }) {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
    if (start.isNegative || end < start) {
      throw ArgumentError('Target section must be a non-negative interval.');
    }
  }

  final String id;
  final Duration start;
  final Duration end;
}

/// Versioned, immutable analysis input detached from feature providers.
///
/// This contract deliberately stores only a snapshot of target facts. Practice
/// and Song adapters are future consumers; no provider, controller, or
/// repository reference belongs here (SDD Ch7 §9.4).
final class AnalysisTarget {
  AnalysisTarget({
    required this.id,
    this.targetVersion = 1,
    required this.kind,
    required this.timebase,
    List<ExpectedEvent> expectedEvents = const <ExpectedEvent>[],
    List<String> expectedChords = const <String>[],
    List<int> expectedNotes = const <int>[],
    List<AnalysisTargetSection> sections = const <AnalysisTargetSection>[],
  }) : expectedEvents = List<ExpectedEvent>.unmodifiable(expectedEvents),
       expectedChords = List<String>.unmodifiable(expectedChords),
       expectedNotes = List<int>.unmodifiable(expectedNotes),
       sections = List<AnalysisTargetSection>.unmodifiable(sections) {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
    if (targetVersion <= 0) {
      throw ArgumentError.value(targetVersion, 'targetVersion');
    }
    if (this.expectedChords.any((chord) => chord.trim().isEmpty)) {
      throw ArgumentError.value(expectedChords, 'expectedChords');
    }
    if (this.expectedNotes.any((note) => note < 0 || note > 127)) {
      throw ArgumentError.value(expectedNotes, 'expectedNotes');
    }
    _requireNondecreasing(
      this.expectedEvents.map((event) => event.time),
      'expectedEvents',
    );
    _requireNondecreasing(
      this.sections.map((section) => section.start),
      'sections',
    );
  }

  final String id;
  final int targetVersion;
  final AnalysisTargetKind kind;
  final AnalysisTargetTimebase timebase;
  final List<ExpectedEvent> expectedEvents;
  final List<String> expectedChords;
  final List<int> expectedNotes;
  final List<AnalysisTargetSection> sections;
}

void _requireNondecreasing(Iterable<Duration> values, String name) {
  Duration? previous;
  for (final value in values) {
    if (previous != null && value < previous) {
      throw ArgumentError.value(values, name, 'must be ordered by time');
    }
    previous = value;
  }
}
