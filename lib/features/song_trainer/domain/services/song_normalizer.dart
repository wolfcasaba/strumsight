/// Stable, idempotent [SongDocument] normalizer (E03-R05, ADR 0114
/// §Döntés 3, SDD §7 + §12).
///
/// The normalizer is the SINGLE, side-effect-free producer of the
/// canonical event ordering the codec and downstream consumers rely
/// on. The transform is intentionally narrow (§5 kötött döntés 4):
///
///   * tracks are sorted by `(kind asc, track.id asc)` and rewrapped
///     as an unmodifiable view; the original track IDs are
///     preserved verbatim — the normalizer never derives a new ID
///     for a track that already has one;
///   * events inside every supported track subtype are sorted by
///     their canonical ordering key (start asc, then event id asc),
///     and the result is rewrapped as an unmodifiable view;
///   * collections on the document (assets, markers, sections,
///     measures) are reordered by their canonical keys and
///     rewrapped as unmodifiable views.
///
/// The transform is **idempotent**: `normalize(normalize(x)) ==
/// normalize(x)` for every input that survived construction, and the
/// canonical ordering is **stable** across runs (§6 acceptance
/// "normalize(normalize(x)) == normalize(x) és canonical event
/// ordering stabil").
///
/// The normalizer is **framework-independent**: no Flutter, Riverpod,
/// Dio, SharedPreferences, l10n or storage plugin import is allowed.
library;

import 'package:meta/meta.dart';

import '../models/song_asset_reference.dart';
import '../models/song_document.dart';
import '../models/song_marker.dart';
import '../models/song_measure.dart';
import '../models/song_section.dart';
import '../models/song_event.dart';
import '../models/song_track.dart';

/// Pure, deterministic [SongDocument] normalizer (E03-R05).
@immutable
final class SongNormalizer {
  /// Constructs a normalizer. The normalizer is stateless and pure;
  /// the constructor is `const` so callers can share a single
  /// instance per process.
  const SongNormalizer();

  /// Returns a [SongDocument] with every collection sorted into its
  /// canonical order. The original document's IDs are preserved
  /// verbatim — the normalizer never derives a new identifier for a
  /// track or an event that already has one (§5 kötött döntés 4).
  ///
  /// The returned document compares equal to the input when the
  /// input was already canonical; the operation is idempotent
  /// (`normalize(normalize(x)) == normalize(x)`).
  SongDocument normalize(SongDocument document) {
    final tracks = _normalizeTracks(document.tracks);
    final sections = _normalizeSections(document.sections);
    final measures = _normalizeMeasures(document.measures);
    final assets = _normalizeAssets(document.assets);
    final markers = _normalizeMarkers(document.markers);

    return _withCollections(
      document,
      assets: assets,
      markers: markers,
      tracks: tracks,
      sections: sections,
      measures: measures,
    );
  }

  // ---------------------------------------------------------------------------
  // Track normalization.
  // ---------------------------------------------------------------------------

  List<SongTrack> _normalizeTracks(List<SongTrack> tracks) {
    final ordered = tracks.toList()
      ..sort((a, b) {
        final kindCompare = _trackKindOrder(a).compareTo(_trackKindOrder(b));
        if (kindCompare != 0) return kindCompare;
        return a.id.value.compareTo(b.id.value);
      });
    return List<SongTrack>.unmodifiable(ordered.map(_normalizeTrack));
  }

  SongTrack _normalizeTrack(SongTrack track) {
    switch (track) {
      case ChordTrack():
        final events = List<SongChordEvent>.of(track.events)
          ..sort((a, b) {
            final startCompare = a.start.compareTo(b.start);
            if (startCompare != 0) return startCompare;
            return a.id.value.compareTo(b.id.value);
          });
        return ChordTrack(
          id: track.id,
          name: track.name,
          instrument: track.instrument,
          enabled: track.enabled,
          events: events,
        );
      case StrumTrack():
        final events = List<SongStrumEvent>.of(track.events)
          ..sort((a, b) {
            final atCompare = a.at.compareTo(b.at);
            if (atCompare != 0) return atCompare;
            return a.id.value.compareTo(b.id.value);
          });
        return StrumTrack(
          id: track.id,
          name: track.name,
          instrument: track.instrument,
          enabled: track.enabled,
          events: events,
        );
      case NoteTrack():
        final events = List<SongNoteEvent>.of(track.events)
          ..sort((a, b) {
            final startCompare = a.start.compareTo(b.start);
            if (startCompare != 0) return startCompare;
            return a.id.value.compareTo(b.id.value);
          });
        return NoteTrack(
          id: track.id,
          name: track.name,
          instrument: track.instrument,
          enabled: track.enabled,
          events: events,
        );
      case LyricsTrack():
        final events = List<SongLyricEvent>.of(track.events)
          ..sort((a, b) {
            final atCompare = a.at.compareTo(b.at);
            if (atCompare != 0) return atCompare;
            return a.id.value.compareTo(b.id.value);
          });
        return LyricsTrack(
          id: track.id,
          name: track.name,
          instrument: track.instrument,
          enabled: track.enabled,
          events: events,
        );
      case MarkerTrack():
        final events = List<SongMarkerEvent>.of(track.events)
          ..sort((a, b) {
            final atCompare = a.at.compareTo(b.at);
            if (atCompare != 0) return atCompare;
            return a.id.value.compareTo(b.id.value);
          });
        return MarkerTrack(
          id: track.id,
          name: track.name,
          instrument: track.instrument,
          enabled: track.enabled,
          events: events,
        );
      case BackingAudioTrack():
        // BackingAudioTrack carries no event list; nothing to sort.
        return track;
    }
  }

  /// Canonical kind ordering: chord, strum, note, lyrics, marker,
  /// backingAudio — matching the `SongTrackKind` constants' source
  /// order. Defined here so the ordering survives a future
  /// alphabetical sort of the constant declarations.
  static int _trackKindOrder(SongTrack track) {
    if (track is ChordTrack) return 0;
    if (track is StrumTrack) return 1;
    if (track is NoteTrack) return 2;
    if (track is LyricsTrack) return 3;
    if (track is MarkerTrack) return 4;
    return 5; // BackingAudioTrack
  }

  // ---------------------------------------------------------------------------
  // Document-level collection normalization.
  // ---------------------------------------------------------------------------

  List<SongSection> _normalizeSections(List<SongSection> sections) {
    final ordered = sections.toList()
      ..sort((a, b) {
        final startCompare = a.startMeasure.compareTo(b.startMeasure);
        if (startCompare != 0) return startCompare;
        return a.id.value.compareTo(b.id.value);
      });
    return List<SongSection>.unmodifiable(ordered);
  }

  List<SongMeasure> _normalizeMeasures(List<SongMeasure> measures) {
    final ordered = measures.toList()
      ..sort((a, b) {
        final indexCompare = a.index.compareTo(b.index);
        if (indexCompare != 0) return indexCompare;
        return a.index.compareTo(b.index);
      });
    return List<SongMeasure>.unmodifiable(ordered);
  }

  List<SongAssetReference> _normalizeAssets(List<SongAssetReference> assets) {
    final ordered = assets.toList()
      ..sort((a, b) => a.id.value.compareTo(b.id.value));
    return List<SongAssetReference>.unmodifiable(ordered);
  }

  List<SongMarker> _normalizeMarkers(List<SongMarker> markers) {
    final ordered = markers.toList()
      ..sort((a, b) {
        final measureCompare = a.measureIndex.compareTo(b.measureIndex);
        if (measureCompare != 0) return measureCompare;
        return a.id.value.compareTo(b.id.value);
      });
    return List<SongMarker>.unmodifiable(ordered);
  }

  /// Returns a copy of [document] with the given collections
  /// rewrapped. All other fields are preserved verbatim — the
  /// normalizer never derives a new identifier.
  SongDocument _withCollections(
    SongDocument document, {
    required List<SongAssetReference> assets,
    required List<SongMarker> markers,
    required List<SongTrack> tracks,
    required List<SongSection> sections,
    required List<SongMeasure> measures,
  }) {
    // Short-circuit: when the input is already canonical, return the
    // same instance. The reference equality keeps the contract
    // `normalize(x) == x` observable when no work was needed.
    if (identical(assets, document.assets) &&
        identical(markers, document.markers) &&
        identical(tracks, document.tracks) &&
        identical(sections, document.sections) &&
        identical(measures, document.measures)) {
      return document;
    }
    return SongDocument(
      schemaVersion: document.schemaVersion,
      id: document.id,
      revision: document.revision,
      metadata: document.metadata,
      source: document.source,
      createdAt: document.createdAt,
      updatedAt: document.updatedAt,
      assets: assets,
      markers: markers,
      tracks: tracks,
      sections: sections,
      measures: measures,
      tempoMap: document.tempoMap,
      meterMap: document.meterMap,
      keyMap: document.keyMap,
    );
  }
}
