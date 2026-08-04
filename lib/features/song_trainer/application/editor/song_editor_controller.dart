import 'dart:async';

import '../../../../core/foundation/app_result.dart';
import '../../../../core/music/chord.dart';
import '../../../../core/music/strum.dart';
import '../../domain/models/meter_map.dart';
import '../../domain/models/song_asset_reference.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_event.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/song_instrument.dart';
import '../../domain/models/song_measure.dart';
import '../../domain/models/song_metadata.dart';
import '../../domain/models/song_section.dart';
import '../../domain/models/song_track.dart';
import '../../domain/models/tempo_map.dart';
import '../../domain/repositories/song_asset_repository.dart';
import '../../domain/repositories/song_repository.dart';
import '../../domain/services/song_validator.dart';
import 'editor_command.dart';
import 'editor_history.dart';
import 'song_editor_state.dart';

/// Owns a local immutable draft and only changes persistence on explicit save.
final class SongEditorController {
  SongEditorController({
    required this.repository,
    required this.assetRepository,
    this.validator = const SongValidator(),
    DateTime Function()? clock,
    EditorHistory? history,
  }) : _clock = clock ?? DateTime.now,
       _history = history ?? EditorHistory();

  final SongRepository repository;
  final SongAssetRepository assetRepository;
  final SongValidator validator;
  final DateTime Function() _clock;
  final EditorHistory _history;
  final StreamController<SongEditorState> _states =
      StreamController<SongEditorState>.broadcast(sync: true);
  SongEditorState _state = const SongEditorState.loading();
  var _nextId = 0;
  var _disposed = false;

  SongEditorState get state => _state;
  Stream<SongEditorState> get states => _states.stream;

  Future<void> load(SongId id) async {
    if (_disposed) return;
    _publish(const SongEditorState.loading());
    final result = await repository.get(id);
    if (_disposed) return;
    switch (result) {
      case Success<SongDocument?>(value: final document?):
        _publishReady(document, document);
      case Success<SongDocument?>():
        _publish(
          SongEditorState(
            status: SongEditorStatus.failure,
            failureCode: SongRepositoryErrorCode.notFound,
          ),
        );
      case Failure<SongDocument?>(error: final error):
        _publish(
          SongEditorState(
            status: SongEditorStatus.failure,
            failureCode: error.code,
          ),
        );
    }
  }

  /// Starts a new, unsaved document. The first save uses repository create.
  void startNew(SongDocument document) {
    if (_disposed) return;
    _publish(
      SongEditorState(
        status: SongEditorStatus.ready,
        draft: document,
        canUndo: _history.canUndo,
        canRedo: _history.canRedo,
      ),
    );
  }

  void editMetadata(SongMetadata metadata) =>
      _edit('metadata', (document) => _copy(document, metadata: metadata));

  void reorderSections(int oldIndex, int newIndex) {
    _edit('section.reorder', (document) {
      final sections = document.sections.toList();
      if (oldIndex < 0 ||
          oldIndex >= sections.length ||
          newIndex < 0 ||
          newIndex >= sections.length) {
        return document;
      }
      final section = sections.removeAt(oldIndex);
      sections.insert(newIndex, section);
      return _copy(document, sections: sections);
    });
  }

  void insertMeasure(int index) {
    _edit('measure.insert', (document) {
      final insertion = index.clamp(0, document.measures.length);
      final measures = document.measures.toList()
        ..insert(
          insertion,
          SongMeasure(
            index: insertion,
            durationBeats: BeatPosition.fromBeats(4),
          ),
        );
      return _copy(
        document,
        measures: _renumberMeasures(measures),
        sections: _shiftSections(document.sections, insertion, 1),
      );
    });
  }

  void copyMeasure({required int sourceIndex, required int destinationIndex}) {
    _edit('measure.copy', (document) {
      if (sourceIndex < 0 || sourceIndex >= document.measures.length) {
        return document;
      }
      final insertion = destinationIndex.clamp(0, document.measures.length);
      final source = document.measures[sourceIndex];
      final measures = document.measures.toList()
        ..insert(
          insertion,
          SongMeasure(
            index: insertion,
            durationBeats: source.durationBeats,
            pickup: source.pickup,
          ),
        );
      return _copy(
        document,
        measures: _renumberMeasures(measures),
        sections: _shiftSections(document.sections, insertion, 1),
      );
    });
  }

  void deleteMeasure(int index) {
    _edit('measure.delete', (document) {
      if (document.measures.length <= 1 ||
          index < 0 ||
          index >= document.measures.length) {
        return document;
      }
      final measures = document.measures.toList()..removeAt(index);
      return _copy(
        document,
        measures: _renumberMeasures(measures),
        sections: _deleteMeasureFromSections(
          document.sections,
          index,
          measures.length,
        ),
      );
    });
  }

  void addChord({required int measureIndex, required String symbol}) {
    _edit('chord.add', (document) {
      final tracks = document.tracks.toList();
      final existingIndex = tracks.indexWhere((track) => track is ChordTrack);
      final event = SongChordEvent(
        id: SongEventId(_id('chord')),
        start: _measureStart(measureIndex),
        duration: const Duration(milliseconds: 500),
        symbol: Chord(symbol),
      );
      final track = existingIndex < 0
          ? ChordTrack(
              id: SongTrackId(_id('chord-track')),
              name: 'Chords',
              instrument: SongInstrument(name: 'Guitar'),
              events: <SongChordEvent>[event],
            )
          : _appendChord(tracks[existingIndex] as ChordTrack, event);
      if (existingIndex < 0) {
        tracks.add(track);
      } else {
        tracks[existingIndex] = track;
      }
      return _copy(document, tracks: tracks);
    });
  }

  void applyStrumPattern({
    required int measureIndex,
    required List<StrumDirection> pattern,
  }) {
    _edit('strum.pattern', (document) {
      final events = <SongStrumEvent>[
        for (var i = 0; i < pattern.length; i++)
          SongStrumEvent(
            id: SongEventId(_id('strum')),
            at: _measureStart(measureIndex) + Duration(milliseconds: i * 500),
            direction: pattern[i],
          ),
      ];
      final tracks = document.tracks.toList();
      final existingIndex = tracks.indexWhere((track) => track is StrumTrack);
      final existing = existingIndex < 0
          ? const <SongStrumEvent>[]
          : (tracks[existingIndex] as StrumTrack).events;
      final track = StrumTrack(
        id: existingIndex < 0
            ? SongTrackId(_id('strum-track'))
            : (tracks[existingIndex] as StrumTrack).id,
        name: existingIndex < 0
            ? 'Strum'
            : (tracks[existingIndex] as StrumTrack).name,
        instrument: SongInstrument(name: 'Guitar'),
        events: <SongStrumEvent>[
          ...existing.where(
            (event) =>
                event.at < _measureStart(measureIndex) ||
                event.at >= _measureStart(measureIndex + 1),
          ),
          ...events,
        ],
      );
      if (existingIndex < 0) {
        tracks.add(track);
      } else {
        tracks[existingIndex] = track;
      }
      return _copy(document, tracks: tracks);
    });
  }

  void addBasicNote({required int measureIndex, required int midiPitch}) {
    _edit('note.add', (document) {
      final tracks = document.tracks.toList();
      final index = tracks.indexWhere((track) => track is NoteTrack);
      final note = SongNoteEvent(
        id: SongEventId(_id('note')),
        start: _measureStart(measureIndex),
        duration: const Duration(milliseconds: 500),
        midiPitch: midiPitch,
      );
      final existing = index < 0
          ? const <SongNoteEvent>[]
          : (tracks[index] as NoteTrack).events;
      final track = NoteTrack(
        id: index < 0
            ? SongTrackId(_id('note-track'))
            : (tracks[index] as NoteTrack).id,
        name: index < 0 ? 'Notes' : (tracks[index] as NoteTrack).name,
        instrument: SongInstrument(name: 'Guitar'),
        events: <SongNoteEvent>[...existing, note],
      );
      if (index < 0) {
        tracks.add(track);
      } else {
        tracks[index] = track;
      }
      return _copy(document, tracks: tracks);
    });
  }

  void setTempo({required int atBeat, required int bpm}) => _edit('tempo.set', (
    document,
  ) {
    final changes =
        document.tempoMap.changes
            .where((change) => change.at != BeatPosition.fromBeats(atBeat))
            .toList()
          ..add(
            TempoChange(at: BeatPosition.fromBeats(atBeat), bpm: Tempo(bpm)),
          )
          ..sort((a, b) => a.at.compareTo(b.at));
    return _copy(document, tempoMap: TempoMap(changes));
  });

  void setMeter({
    required int atMeasure,
    required int numerator,
    required int denominator,
  }) => _edit('meter.set', (document) {
    final changes =
        document.meterMap.changes
            .where((change) => change.atMeasure != atMeasure)
            .toList()
          ..add(
            MeterChange(
              atMeasure: atMeasure,
              meter: Meter(numerator, denominator),
            ),
          )
          ..sort((a, b) => a.atMeasure.compareTo(b.atMeasure));
    return _copy(document, meterMap: MeterMap(changes));
  });

  Future<void> attachBacking(SongAssetWriteRequest request) async {
    if (_disposed || _state.draft == null) return;
    final stored = await assetRepository.put(request);
    if (_disposed || stored is Failure<SongAssetStoreReceipt>) {
      if (stored is Failure<SongAssetStoreReceipt>) {
        _publish(
          _state.copyWith(
            status: SongEditorStatus.failure,
            failureCode: stored.error.code,
          ),
        );
      }
      return;
    }
    final receipt = (stored as Success<SongAssetStoreReceipt>).value;
    _edit('backing.attach', (document) {
      final asset = SongAssetReference(
        id: receipt.assetId,
        sha256: receipt.sha256,
        extension: request.extension,
        byteLength: receipt.byteLength,
        mimeType: request.mimeType,
        durationMs: request.durationMs,
      );
      final tracks = document.tracks.whereType<BackingAudioTrack>().isEmpty
          ? <SongTrack>[
              ...document.tracks,
              BackingAudioTrack(
                id: SongTrackId(_id('backing-track')),
                name: 'Backing',
                instrument: SongInstrument(name: 'Audio'),
                assetId: asset.id,
                gridOffset: Duration.zero,
              ),
            ]
          : document.tracks
                .map<SongTrack>(
                  (track) => track is BackingAudioTrack
                      ? BackingAudioTrack(
                          id: track.id,
                          name: track.name,
                          instrument: track.instrument,
                          assetId: asset.id,
                          gridOffset: track.gridOffset,
                          gainDb: track.gainDb,
                          enabled: track.enabled,
                        )
                      : track,
                )
                .toList();
      return _copy(
        document,
        assets: <SongAssetReference>[
          ...document.assets.where((item) => item.id != asset.id),
          asset,
        ],
        tracks: tracks,
      );
    });
  }

  void detachBacking() => _edit(
    'backing.detach',
    (document) => _copy(
      document,
      tracks: document.tracks
          .where((track) => track is! BackingAudioTrack)
          .toList(),
    ),
  );

  void undo() {
    if (_disposed || _state.draft == null) return;
    final command = _history.takeUndo();
    if (command != null) {
      _publishReady(_state.persisted, command.revert(_state.draft!));
    }
  }

  void redo() {
    if (_disposed || _state.draft == null) return;
    final command = _history.takeRedo();
    if (command != null) {
      _publishReady(_state.persisted, command.apply(_state.draft!));
    }
  }

  Future<void> save() async {
    final draft = _state.draft;
    if (_disposed || draft == null) return;
    final report = validator.validate(draft);
    if (report.hasFatalIssue) {
      _publish(
        _state.copyWith(
          status: SongEditorStatus.validationFailed,
          validation: report,
          clearFailure: true,
        ),
      );
      return;
    }
    _publish(
      _state.copyWith(
        status: SongEditorStatus.saving,
        validation: report,
        clearFailure: true,
      ),
    );
    final persisted = _state.persisted;
    final result = persisted == null
        ? await repository.create(draft)
        : await repository.update(draft, expectedRevision: persisted.revision);
    if (_disposed) return;
    if (result case Failure<void>(error: final error)) {
      _publish(
        _state.copyWith(
          status: error.code == SongRepositoryErrorCode.staleRevision
              ? SongEditorStatus.conflict
              : SongEditorStatus.failure,
          failureCode: error.code,
        ),
      );
      return;
    }
    final readBack = await repository.get(draft.id);
    if (_disposed) return;
    if (readBack case Success<SongDocument?>(value: final saved?)) {
      _publishReady(saved, saved);
    } else if (readBack case Failure<SongDocument?>(error: final error)) {
      _publish(
        _state.copyWith(
          status: SongEditorStatus.failure,
          failureCode: error.code,
        ),
      );
    }
  }

  void discard() {
    final persisted = _state.persisted;
    if (_disposed) return;
    if (persisted == null) {
      _publish(const SongEditorState.loading());
      return;
    }
    _publishReady(persisted, persisted);
  }

  void _edit(
    String label,
    SongDocument Function(SongDocument document) mutate,
  ) {
    final current = _state.draft;
    if (_disposed || current == null) return;
    final next = mutate(current);
    if (next == current) return;
    _history.record(
      DocumentEditorCommand(label: label, before: current, after: next),
    );
    _publishReady(_state.persisted, next);
  }

  void _publishReady(SongDocument? persisted, SongDocument draft) => _publish(
    SongEditorState(
      status: SongEditorStatus.ready,
      persisted: persisted,
      draft: draft,
      canUndo: _history.canUndo,
      canRedo: _history.canRedo,
    ),
  );

  void _publish(SongEditorState value) {
    _state = value;
    if (!_states.isClosed) _states.add(value);
  }

  String _id(String prefix) =>
      '$prefix-${++_nextId}-${_clock().microsecondsSinceEpoch}';

  static Duration _measureStart(int index) =>
      Duration(milliseconds: index * 4000);
  static ChordTrack _appendChord(ChordTrack track, SongChordEvent event) =>
      ChordTrack(
        id: track.id,
        name: track.name,
        instrument: track.instrument,
        enabled: track.enabled,
        events: <SongChordEvent>[...track.events, event],
      );
  static List<SongMeasure> _renumberMeasures(List<SongMeasure> measures) =>
      <SongMeasure>[
        for (var index = 0; index < measures.length; index++)
          SongMeasure(
            index: index,
            durationBeats: measures[index].durationBeats,
            pickup: measures[index].pickup,
            repeatStart: measures[index].repeatStart,
            repeatEndCount: measures[index].repeatEndCount,
            alternateEnding: measures[index].alternateEnding,
          ),
      ];
  static List<SongSection> _shiftSections(
    List<SongSection> sections,
    int at,
    int delta,
  ) => sections
      .map(
        (section) => SongSection(
          id: section.id,
          name: section.name,
          startMeasure: section.startMeasure >= at
              ? section.startMeasure + delta
              : section.startMeasure,
          endMeasureExclusive: section.endMeasureExclusive >= at
              ? section.endMeasureExclusive + delta
              : section.endMeasureExclusive,
          kind: section.kind,
          colorKey: section.colorKey,
        ),
      )
      .toList();
  static List<SongSection> _deleteMeasureFromSections(
    List<SongSection> sections,
    int deleted,
    int count,
  ) => sections
      .where(
        (section) =>
            !(section.startMeasure == deleted &&
                section.endMeasureExclusive == deleted + 1),
      )
      .map((section) {
        final start = section.startMeasure > deleted
            ? section.startMeasure - 1
            : section.startMeasure;
        final end = section.endMeasureExclusive > deleted
            ? section.endMeasureExclusive - 1
            : section.endMeasureExclusive;
        return SongSection(
          id: section.id,
          name: section.name,
          startMeasure: start.clamp(0, count - 1),
          endMeasureExclusive: end.clamp(1, count),
          kind: section.kind,
          colorKey: section.colorKey,
        );
      })
      .where((section) => section.endMeasureExclusive > section.startMeasure)
      .toList();
  static SongDocument _copy(
    SongDocument source, {
    SongMetadata? metadata,
    List<SongAssetReference>? assets,
    List<SongTrack>? tracks,
    List<SongSection>? sections,
    List<SongMeasure>? measures,
    TempoMap? tempoMap,
    MeterMap? meterMap,
  }) => SongDocument(
    schemaVersion: source.schemaVersion,
    id: source.id,
    revision: source.revision,
    metadata: metadata ?? source.metadata,
    source: source.source,
    createdAt: source.createdAt,
    updatedAt: source.updatedAt,
    assets: assets ?? source.assets,
    markers: source.markers,
    tracks: tracks ?? source.tracks,
    sections: sections ?? source.sections,
    measures: measures ?? source.measures,
    tempoMap: tempoMap ?? source.tempoMap,
    meterMap: meterMap ?? source.meterMap,
    keyMap: source.keyMap,
  );

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _history.dispose();
    _publish(const SongEditorState(status: SongEditorStatus.disposed));
    await _states.close();
  }
}
