/// Lossless, deterministic adapter from a legacy [LegacySongRecord] to a
/// V2 [SongDocument] (E03-R06, ADR 0116, SDD Ch4 §3.2–3.4).
///
/// The adapter is the **single producer** of [SongSourceType.legacyLocal]
/// documents today (the value was reserved for it). It owns the four
/// architectural decisions locked by ADR 0116:
///
///   Döntés 1 — `LegacyMigrationReport` is a third, adapter-local report
///              type (defined in `legacy_migration_report.dart`), never a
///              `SongValidationReport` or `ImportWarning` extension.
///   Döntés 2 — `Meter(beatsPerBar, 4)` always (legacy has no denominator).
///   Döntés 3 — Event timing uses **direct multiplication** (`measure *
///              beatsPerBar * spb`) with a single microsecond rounding, not
///              cumulative accumulation — the same "one rounding point"
///              principle as ADR 0093 §1.1.
///   Döntés 4 — One `SongSection` covering the whole song, kind
///              [SongSectionKind.custom], name `Full Song` (no fake
///              tagolás for a tagolatlan legacy record).
///
/// The adapter is **side-effect-free**: it never imports a presentation
/// layer, never opens storage and never logs raw bytes. The caller passes
/// in a [LegacySongRecord] (typically produced by [LegacySongReader]) and
/// gets back a fully-constructed [SongDocument] + a [LegacyMigrationReport]
/// describing any repair / clamp the adapter had to apply.
library;

import 'package:meta/meta.dart';

import '../../../../core/music/chord.dart';
import '../../../../core/music/strum.dart';
import '../../../../core/music/tuning.dart';
import '../../domain/models/key_map.dart';
import '../../domain/models/meter_map.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_event.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/song_instrument.dart';
import '../../domain/models/song_measure.dart';
import '../../domain/models/song_metadata.dart';
import '../../domain/models/song_section.dart';
import '../../domain/models/song_source.dart';
import '../../domain/models/song_track.dart';
import '../../domain/models/tempo_map.dart';
import 'legacy_migration_report.dart';
import 'legacy_song_reader.dart';

/// Display name of the chord track an adapter-produced document carries.
/// Stable, so the codec round-trip and the parity test can both key off
/// it.
const String legacyAdapterChordTrackName = 'Chords';

/// Display name of the strum track an adapter-produced document carries.
const String legacyAdapterStrumTrackName = 'Strums';

/// Display name of the single section an adapter-produced document
/// carries (ADR 0116 §Döntés 4).
const String legacyAdapterSectionName = 'Full Song';

/// Stable, importer identifier persisted on the [SongSource.importerVersion]
/// field. Bumping the value signals a fidelity change that an
/// audit / re-import path can branch on.
const String legacyAdapterImporterVersion = 'legacySongAdapter@1';

/// The default instrument reference attached to the chord / strum tracks
/// of an adapter-produced document. Guitar / standard tuning — the
/// legacy record has no instrument field and 4/4 chord progression is
/// always guitar-shaped in the legacy model.
final SongInstrument _guitarInstrument = SongInstrument(
  name: 'Guitar',
  tuning: Tunings.standard,
);

/// Output of a single [LegacySongAdapter.adapt] call.
@immutable
final class LegacySongAdaptation {
  /// Stable constructor.
  const LegacySongAdaptation({required this.document, required this.report});

  /// The V2 document the adapter produced.
  final SongDocument document;

  /// Fidelity report describing any repair / clamp the adapter had to
  /// apply (empty when the input was clean).
  final LegacyMigrationReport report;
}

/// Lossless, deterministic Song → V2 SongDocument adapter
/// (E03-R06, ADR 0116).
///
/// Two [LegacySongAdapter] instances produce the same document for the
/// same input. Event identifiers are derived deterministically from the
/// `(measureIndex, slotIndex)` pair, the canonical SHA-256 is carried on
/// the input record (computed by the reader), and timing is computed via
/// direct multiplication with a single rounding step.
final class LegacySongAdapter {
  /// Stable constructor — the adapter carries no state.
  const LegacySongAdapter();

  /// Adapt one legacy Song record into a V2 [SongDocument].
  ///
  /// [importedAt] is supplied by the caller so the same record imported
  /// twice yields a [SongSource] whose codec round-trip is stable except
  /// for the supplied timestamp. The migration runner is expected to
  /// pass a deterministic timestamp when running parity tests.
  LegacySongAdaptation adapt(
    LegacySongRecord record, {
    required DateTime importedAt,
    int revision = 1,
  }) {
    final issues = <LegacyMigrationIssue>[];

    // --- Meter / BPM normalisation ------------------------------------
    final beatsPerBar = record.beatsPerBar;
    final rawBpm = record.bpm;
    final bpm = _clampBpm(rawBpm);
    if (bpm != rawBpm) {
      issues.add(
        const LegacyMigrationIssue(
          code: LegacyMigrationCode.bpmClamped,
          message:
              'Legacy bpm was outside the documented 1..400 range; '
              'clamped to the nearest valid value.',
        ),
      );
    }

    // --- Pattern fit ---------------------------------------------------
    // The legacy reader preserves the raw pattern; the adapter fits it to
    // beatsPerBar * 2 slots and surfaces a fidelity note when the fit
    // dropped or padded a slot (legacy Song.fromJson does the same fit).
    final fittedPattern = _fitToMeter(record.pattern, beatsPerBar);
    if (!_listEquals(fittedPattern, record.pattern)) {
      issues.add(
        const LegacyMigrationIssue(
          code: LegacyMigrationCode.patternLengthFitted,
          message:
              'Legacy pattern length did not match beatsPerBar*2; '
              'truncated or rest-padded to fit the meter.',
        ),
      );
    }

    // --- Direct timing with one rounding point per event ----------------
    // Match legacy `Song.toAnalyzeResult()`: multiply the whole beat
    // position by 60 / bpm, then round only when crossing into Duration.
    // Rounding a single beat first would accumulate a per-beat error.
    // --- Chord events: one per measure ---------------------------------
    final chordEvents = <SongChordEvent>[];
    for (
      var measureIndex = 0;
      measureIndex < record.chords.length;
      measureIndex++
    ) {
      final startMicros = _microsForHalfBeats(
        measureIndex * beatsPerBar * 2,
        bpm,
      );
      final endMicros = _microsForHalfBeats(
        (measureIndex + 1) * beatsPerBar * 2,
        bpm,
      );
      final start = Duration(microseconds: startMicros);
      final duration = Duration(microseconds: endMicros - startMicros);
      chordEvents.add(
        SongChordEvent(
          id: SongEventId('legacy_${record.id}_chord_m$measureIndex'),
          start: start,
          duration: duration,
          symbol: Chord(record.chords[measureIndex]),
        ),
      );
    }

    // --- Strum events: one per non-rest pattern slot, per measure ------
    final strumEvents = <SongStrumEvent>[];
    final slots = beatsPerBar * 2;
    for (
      var measureIndex = 0;
      measureIndex < record.chords.length;
      measureIndex++
    ) {
      for (var slotIndex = 0; slotIndex < slots; slotIndex++) {
        final direction = fittedPattern[slotIndex];
        if (direction == null) continue; // rest → no invented stroke
        final at = Duration(
          microseconds: _microsForHalfBeats(
            (measureIndex * beatsPerBar * 2) + slotIndex,
            bpm,
          ),
        );
        strumEvents.add(
          SongStrumEvent(
            id: SongEventId(
              'legacy_${record.id}_strum_m${measureIndex}s$slotIndex',
            ),
            at: at,
            direction: direction,
          ),
        );
      }
    }

    // --- Sections, measures, maps --------------------------------------
    final sections = <SongSection>[
      SongSection(
        id: SongSectionId('legacy_${record.id}_section_full'),
        name: legacyAdapterSectionName,
        startMeasure: 0,
        endMeasureExclusive: record.chords.length,
        kind: SongSectionKind.custom,
      ),
    ];

    final measures = <SongMeasure>[
      for (var index = 0; index < record.chords.length; index++)
        SongMeasure(
          index: index,
          durationBeats: BeatPosition.fromBeats(beatsPerBar),
        ),
    ];

    final tempoMap = TempoMap.constant(Tempo(bpm));
    final meterMap = MeterMap.constant(Meter(beatsPerBar, 4));
    final keyMap = KeyMap.constant(KeySignature(0, KeyMode.major));

    final chordTrack = ChordTrack(
      id: SongTrackId('legacy_${record.id}_chord_track'),
      name: legacyAdapterChordTrackName,
      instrument: _guitarInstrument,
      events: chordEvents,
    );
    final strumTrack = StrumTrack(
      id: SongTrackId('legacy_${record.id}_strum_track'),
      name: legacyAdapterStrumTrackName,
      instrument: _guitarInstrument,
      events: strumEvents,
    );

    final title = record.name.trim().isEmpty ? record.id : record.name.trim();
    final metadata = SongMetadata(title: title);

    final source = SongSource(
      type: SongSourceType.legacyLocal,
      originalFileName: 'song_${record.id}.json',
      sha256: record.canonicalSha256,
      importedAt: importedAt,
      importerVersion: legacyAdapterImporterVersion,
      warningSummary: const <String>[],
    );

    SongDocument document = SongDocument(
      schemaVersion: songDocumentSchemaVersion,
      id: SongId(record.id),
      revision: revision,
      metadata: metadata,
      source: source,
      sections: sections,
      measures: measures,
      tempoMap: tempoMap,
      meterMap: meterMap,
      keyMap: keyMap,
      tracks: <SongTrack>[chordTrack, strumTrack],
      createdAt: importedAt,
      updatedAt: importedAt,
    );

    // Attach the warning summary AFTER construction so we don't have to
    // re-build the document — but SongSource is immutable, so we rebuild
    // it explicitly here and replace the field.
    if (issues.isNotEmpty) {
      final report = LegacyMigrationReport.from(issues);
      final sourceWithWarnings = SongSource(
        type: source.type,
        originalFileName: source.originalFileName,
        sha256: source.sha256,
        importedAt: source.importedAt,
        importerVersion: source.importerVersion,
        formatVersion: source.formatVersion,
        warningSummary: report.warningSummary,
        originalAssetId: source.originalAssetId,
      );
      document = _documentWithSource(document, sourceWithWarnings);
      return LegacySongAdaptation(document: document, report: report);
    }

    return LegacySongAdaptation(
      document: document,
      report: LegacyMigrationReport.empty,
    );
  }

  static int _clampBpm(int value) {
    if (value < legacyMinBpm) return legacyMinBpm;
    if (value > legacyMaxBpm) return legacyMaxBpm;
    return value;
  }

  /// Converts a half-beat position directly to wall-clock microseconds.
  ///
  /// The legacy model computes each Analyze timestamp from its full beat
  /// position. Keep the numerator intact until this boundary so a 76 BPM
  /// 3/4 song, for example, ends at 4,736,842µs rather than drifting by
  /// one rounded microsecond per beat.
  static int _microsForHalfBeats(int halfBeats, int bpm) =>
      (halfBeats * 60000000 / (bpm * 2)).round();

  /// Mirror of the legacy `Song._fitToMeter` — truncate / rest-pad to
  /// exactly `beatsPerBar * 2` slots. Used by the adapter when the raw
  /// pattern length differs.
  static List<StrumDirection?> _fitToMeter(
    List<StrumDirection?> pattern,
    int beatsPerBar,
  ) {
    final want = beatsPerBar * 2;
    if (pattern.length == want) return pattern;
    return [
      for (var i = 0; i < want; i++) i < pattern.length ? pattern[i] : null,
    ];
  }

  static bool _listEquals(List<StrumDirection?> a, List<StrumDirection?> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  /// Build a new document identical to [original] but with [source]
  /// swapped in (SongDocument is immutable).
  static SongDocument _documentWithSource(
    SongDocument original,
    SongSource source,
  ) {
    return SongDocument(
      schemaVersion: original.schemaVersion,
      id: original.id,
      revision: original.revision,
      metadata: original.metadata,
      source: source,
      sections: original.sections,
      measures: original.measures,
      tempoMap: original.tempoMap,
      meterMap: original.meterMap,
      keyMap: original.keyMap,
      assets: original.assets,
      markers: original.markers,
      tracks: original.tracks,
      createdAt: original.createdAt,
      updatedAt: original.updatedAt,
    );
  }
}
