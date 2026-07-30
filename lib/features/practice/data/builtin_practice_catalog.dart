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
import 'package:strumsight/features/practice/domain/repository/practice_catalog_repository.dart';

/// The shipped, offline built-in catalog of practice definitions.
///
/// Every entry is stable across builds and pinned to schema version 1.
/// Adding or removing an entry requires either a new ID version (for content
/// changes) or an ADR-justified catalog bump.
///
/// The catalog is returned in declaration order from every
/// [BuiltinPracticeCatalog] method; that order is part of the contract and
/// the tests pin the ID list by name.
///
/// Immutability guarantees:
///   * `_builtinPracticeDefinitions` is a top-level `final` list built when
///     the library is first loaded.
///   * Every `skillTags:` literal is a `const` list.
///   * The free-practice `events:` literal is `const []`.
///   * Every comprehension-driven `events:` list is wrapped with
///     `List.unmodifiable(...)` (helper-returned for the more complex
///     patterns, inline-wrapped for the others).
///   * `PracticeDefinition.events` and `skillTags` honor the
///     `practice_definition.dart` contract — callers cannot mutate them.
///   * `BuiltinPracticeCatalog.all()` returns a single cached
///     `List.unmodifiable` snapshot of this list.
final List<PracticeDefinition> _builtinPracticeDefinitions = [
  // 1. Quarter-note downstrokes across 4 bars.
  PracticeDefinition(
    id: 'builtin.quarterDownstrokes.v1',
    schemaVersion: 1,
    titleKey: 'practiceCatalogQuarterDownstrokesTitle',
    descriptionKey: 'practiceCatalogQuarterDownstrokesDescription',
    mode: PracticeMode.strumPattern,
    source: PracticeSource.builtin,
    meter: Meter(beatsPerBar: 4),
    defaultTempo: Tempo(70),
    totalBeats: BeatPosition.quarters(16),
    events: List<PracticeEvent>.unmodifiable([
      for (var index = 0; index < 16; index++)
        PracticeEvent(
          id: 'quarterDownstrokes.e$index',
          position: BeatPosition.quarters(index),
          direction: StrumDirection.down,
        ),
    ]),
    scoringProfile: ScoringProfile.legacyLearnParity,
    skillTags: const ['downstrokes', 'quarterNotes'],
  ),

  // 2. Alternating down/up eighths across 4 bars.
  PracticeDefinition(
    id: 'builtin.alternatingEighths.v1',
    schemaVersion: 1,
    titleKey: 'practiceCatalogAlternatingEighthsTitle',
    descriptionKey: 'practiceCatalogAlternatingEighthsDescription',
    mode: PracticeMode.strumPattern,
    source: PracticeSource.builtin,
    meter: Meter(beatsPerBar: 4),
    defaultTempo: Tempo(70),
    totalBeats: BeatPosition.quarters(16),
    events: List<PracticeEvent>.unmodifiable([
      for (var index = 0; index < 32; index++)
        PracticeEvent(
          id: 'alternatingEighths.e$index',
          position: BeatPosition.eighths(index),
          direction: index.isEven ? StrumDirection.down : StrumDirection.up,
        ),
    ]),
    scoringProfile: ScoringProfile.legacyLearnParity,
    skillTags: const ['eighthNotes', 'alternating', 'rhythm'],
  ),

  // 3. Folk syncopated pattern: "D - D U - U D U" on eighths, per bar.
  PracticeDefinition(
    id: 'builtin.folkPattern.v1',
    schemaVersion: 1,
    titleKey: 'practiceCatalogFolkPatternTitle',
    descriptionKey: 'practiceCatalogFolkPatternDescription',
    mode: PracticeMode.strumPattern,
    source: PracticeSource.builtin,
    meter: Meter(beatsPerBar: 4),
    defaultTempo: Tempo(80),
    totalBeats: BeatPosition.quarters(16),
    events: _folkPatternEvents(),
    scoringProfile: ScoringProfile.legacyLearnParity,
    skillTags: const ['folk', 'syncopation', 'eighthNotes'],
  ),

  // 4. G <-> D chord changes on quarter notes across 8 bars (one bar per chord).
  PracticeDefinition(
    id: 'builtin.gToDChanges.v1',
    schemaVersion: 1,
    titleKey: 'practiceCatalogGToDChangesTitle',
    descriptionKey: 'practiceCatalogGToDChangesDescription',
    mode: PracticeMode.chordChanges,
    source: PracticeSource.builtin,
    meter: Meter(beatsPerBar: 4),
    defaultTempo: Tempo(60),
    totalBeats: BeatPosition.quarters(32),
    events: _barGroupedChordEvents(
      slug: 'gToDChanges',
      firstChord: 'G',
      secondChord: 'D',
    ),
    scoringProfile: ScoringProfile.chordChangeDefault,
    skillTags: const ['chordChanges', 'openChords', 'gChord', 'dChord'],
  ),

  // 5. Em <-> C chord changes on quarter notes across 8 bars (one bar per chord).
  PracticeDefinition(
    id: 'builtin.emToCChanges.v1',
    schemaVersion: 1,
    titleKey: 'practiceCatalogEmToCChangesTitle',
    descriptionKey: 'practiceCatalogEmToCChangesDescription',
    mode: PracticeMode.chordChanges,
    source: PracticeSource.builtin,
    meter: Meter(beatsPerBar: 4),
    defaultTempo: Tempo(60),
    totalBeats: BeatPosition.quarters(32),
    events: _barGroupedChordEvents(
      slug: 'emToCChanges',
      firstChord: 'Em',
      secondChord: 'C',
    ),
    scoringProfile: ScoringProfile.chordChangeDefault,
    skillTags: const ['chordChanges', 'minorChords', 'emChord', 'cChord'],
  ),

  // 6. C / G / Am / F chord progression across 4 bars, quarter downstrokes.
  PracticeDefinition(
    id: 'builtin.cGAmFProgression.v1',
    schemaVersion: 1,
    titleKey: 'practiceCatalogCGAmFProgressionTitle',
    descriptionKey: 'practiceCatalogCGAmFProgressionDescription',
    mode: PracticeMode.chordProgression,
    source: PracticeSource.builtin,
    meter: Meter(beatsPerBar: 4),
    defaultTempo: Tempo(70),
    totalBeats: BeatPosition.quarters(16),
    events: List<PracticeEvent>.unmodifiable([
      for (var bar = 0; bar < 4; bar++)
        for (var beat = 0; beat < 4; beat++)
          PracticeEvent(
            id: 'cGAmFProgression.e${bar * 4 + beat}',
            position: BeatPosition.quarters(bar * 4 + beat),
            chord: const ['C', 'G', 'Am', 'F'][bar],
            direction: StrumDirection.down,
          ),
    ]),
    scoringProfile: ScoringProfile.chordProgressionDefault,
    difficulty: PracticeDifficulty.intermediate,
    skillTags: const ['chordProgression', 'pop', 'fourChords'],
  ),

  // 7. 3/4 waltz: D U U on the three quarter notes per bar, 4 bars.
  PracticeDefinition(
    id: 'builtin.firstWaltz.v1',
    schemaVersion: 1,
    titleKey: 'practiceCatalogFirstWaltzTitle',
    descriptionKey: 'practiceCatalogFirstWaltzDescription',
    mode: PracticeMode.strumPattern,
    source: PracticeSource.builtin,
    meter: Meter(beatsPerBar: 3),
    defaultTempo: Tempo(90),
    totalBeats: BeatPosition.quarters(12),
    events: List<PracticeEvent>.unmodifiable([
      for (var bar = 0; bar < 4; bar++)
        for (var beat = 0; beat < 3; beat++)
          PracticeEvent(
            id: 'firstWaltz.e${bar * 3 + beat}',
            position: BeatPosition.quarters(bar * 3 + beat),
            direction: beat == 0 ? StrumDirection.down : StrumDirection.up,
          ),
    ]),
    scoringProfile: ScoringProfile.legacyLearnParity,
    skillTags: const ['waltz', 'threeFour', 'upstrokes'],
  ),

  // 8. Syncopated upstrokes on the off-beats after 2, 3, and 4.
  PracticeDefinition(
    id: 'builtin.syncopatedUps.v1',
    schemaVersion: 1,
    titleKey: 'practiceCatalogSyncopatedUpsTitle',
    descriptionKey: 'practiceCatalogSyncopatedUpsDescription',
    mode: PracticeMode.strumPattern,
    source: PracticeSource.builtin,
    meter: Meter(beatsPerBar: 4),
    defaultTempo: Tempo(90),
    totalBeats: BeatPosition.quarters(16),
    events: List<PracticeEvent>.unmodifiable([
      for (var bar = 0; bar < 4; bar++)
        for (final entry in const [
          _SyncopatedSlot(0, StrumDirection.down),
          _SyncopatedSlot(3, StrumDirection.up),
          _SyncopatedSlot(5, StrumDirection.up),
          _SyncopatedSlot(7, StrumDirection.up),
        ])
          PracticeEvent(
            id: 'syncopatedUps.e${bar * 8 + entry.eighthIndex}',
            position: BeatPosition.eighths(bar * 8 + entry.eighthIndex),
            direction: entry.direction,
          ),
    ]),
    scoringProfile: ScoringProfile.legacyLearnParity,
    difficulty: PracticeDifficulty.intermediate,
    skillTags: const ['syncopation', 'offBeat', 'upstrokes'],
  ),

  // 9. Rhythm-only quarter downstrokes (no chord/direction scoring).
  PracticeDefinition(
    id: 'builtin.rhythmOnlyQuarters.v1',
    schemaVersion: 1,
    titleKey: 'practiceCatalogRhythmOnlyQuartersTitle',
    descriptionKey: 'practiceCatalogRhythmOnlyQuartersDescription',
    mode: PracticeMode.rhythmOnly,
    source: PracticeSource.builtin,
    meter: Meter(beatsPerBar: 4),
    defaultTempo: Tempo(70),
    totalBeats: BeatPosition.quarters(16),
    events: List<PracticeEvent>.unmodifiable([
      for (var index = 0; index < 16; index++)
        PracticeEvent(
          id: 'rhythmOnlyQuarters.e$index',
          position: BeatPosition.quarters(index),
          direction: StrumDirection.down,
        ),
    ]),
    scoringProfile: ScoringProfile.rhythmOnlyDefault,
    skillTags: const ['rhythmOnly', 'quarterNotes'],
  ),

  // 10. Free-practice template: no targets, no scoring.
  PracticeDefinition(
    id: 'builtin.freePracticeTemplate.v1',
    schemaVersion: 1,
    titleKey: 'practiceCatalogFreePracticeTemplateTitle',
    descriptionKey: 'practiceCatalogFreePracticeTemplateDescription',
    mode: PracticeMode.freePractice,
    source: PracticeSource.builtin,
    meter: Meter(beatsPerBar: 4),
    defaultTempo: Tempo(80),
    totalBeats: BeatPosition.quarters(16),
    events: const <PracticeEvent>[],
    scoringProfile: ScoringProfile.freePracticeOpen,
    skillTags: const ['freePlay', 'open'],
  ),
];

/// Folk-pattern events: 6 strums per bar of eighths, rests on the 2nd and
/// 5th eighth positions. Layout per bar at eighth indices 0..7:
///
///     0  1  2  3  4  5  6  7
///     D  .  D  U  .  U  D  U
///
/// Rests are simply absent from the event list; only the 6 strums are
/// emitted. Total = 4 bars × 6 = 24 events.
List<PracticeEvent> _folkPatternEvents() {
  const perBarDirections = <StrumDirection>[
    StrumDirection.down,
    StrumDirection.down,
    StrumDirection.up,
    StrumDirection.up,
    StrumDirection.down,
    StrumDirection.up,
  ];
  const perBarEighthIndices = <int>[0, 2, 3, 5, 6, 7];
  return List<PracticeEvent>.unmodifiable([
    for (var bar = 0; bar < 4; bar++)
      for (var index = 0; index < perBarDirections.length; index++)
        PracticeEvent(
          id: 'folkPattern.e${bar * 6 + index}',
          position: BeatPosition.eighths(bar * 8 + perBarEighthIndices[index]),
          direction: perBarDirections[index],
        ),
  ]);
}

/// G↔D or Em↔C chord-change events: a quarter-note downstroke per beat, with
/// the chord grouped per bar — four beats of the first chord, then four beats
/// of the second chord, alternating by bar. 8 bars × 4 beats = 32 events.
List<PracticeEvent> _barGroupedChordEvents({
  required String slug,
  required String firstChord,
  required String secondChord,
}) {
  return List<PracticeEvent>.unmodifiable([
    for (var index = 0; index < 32; index++)
      PracticeEvent(
        id: '$slug.e$index',
        position: BeatPosition.quarters(index),
        chord: (index ~/ 4).isEven ? firstChord : secondChord,
        direction: StrumDirection.down,
      ),
  ]);
}

/// One slot of the syncopated-upstrokes pattern, expressed as the eighth
/// index within a single bar (0..7) and the strum direction.
class _SyncopatedSlot {
  const _SyncopatedSlot(this.eighthIndex, this.direction);

  final int eighthIndex;
  final StrumDirection direction;
}

/// The shipped read-only [PracticeCatalogRepository] backed by the const
/// built-in definitions above.
final class BuiltinPracticeCatalog implements PracticeCatalogRepository {
  const BuiltinPracticeCatalog();

  /// One-shot unmodifiable snapshot of [_builtinPracticeDefinitions].
  /// Allocated lazily on first access and shared across every
  /// [BuiltinPracticeCatalog] instance.
  static final List<PracticeDefinition> _unmodifiableDefinitions =
      List<PracticeDefinition>.unmodifiable(_builtinPracticeDefinitions);

  @override
  List<PracticeDefinition> all() => _unmodifiableDefinitions;

  @override
  PracticeDefinition? byId(String id) {
    for (final definition in _unmodifiableDefinitions) {
      if (definition.id == id) return definition;
    }
    return null;
  }

  @override
  List<PracticeDefinition> byMode(PracticeMode mode) {
    final matches = <PracticeDefinition>[];
    for (final definition in _unmodifiableDefinitions) {
      if (definition.mode == mode) matches.add(definition);
    }
    return List<PracticeDefinition>.unmodifiable(matches);
  }

  @override
  List<PracticeDefinition> byDifficulty(PracticeDifficulty difficulty) {
    final matches = <PracticeDefinition>[];
    for (final definition in _unmodifiableDefinitions) {
      if (definition.difficulty == difficulty) matches.add(definition);
    }
    return List<PracticeDefinition>.unmodifiable(matches);
  }
}
