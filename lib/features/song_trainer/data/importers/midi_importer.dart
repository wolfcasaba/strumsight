import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../domain/models/key_map.dart';
import '../../domain/models/meter_map.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_event.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/song_instrument.dart';
import '../../domain/models/song_marker.dart';
import '../../domain/models/song_metadata.dart';
import '../../domain/models/song_source.dart';
import '../../domain/models/song_track.dart';
import '../../domain/models/tempo_map.dart';
import 'midi_parser_adapter.dart';
import 'midi_timeline_mapper.dart';
import 'midi_track_preview.dart';
import 'musicxml_importer.dart';
import 'song_importer.dart';

abstract final class MidiImportFailureCode {
  static const String sourceRead = 'songImport.midi.sourceRead';
  static const String sourceTooLarge = 'songImport.midi.sourceTooLarge';
  static const String invalidHeader = MidiParserFailureCode.invalidHeader;
  static const String invalidChunk = MidiParserFailureCode.invalidChunk;
  static const String invalidEvent = MidiParserFailureCode.invalidEvent;
  static const String smpteUnsupported = MidiParserFailureCode.smpteUnsupported;
}

abstract final class MidiImportWarningCode {
  static const String danglingNote = 'songImport.midi.danglingNote';
  static const String extensionMismatch = 'songImport.midi.extensionMismatch';
}

final class MidiImporter implements SongImporter {
  const MidiImporter({
    this.parser = const MidiParserAdapter(),
    this.timeline = const MidiTimelineMapper(),
  });
  final MidiParserAdapter parser;
  final MidiTimelineMapper timeline;
  @override
  Set<String> get supportedExtensions => const <String>{'.mid', '.midi'};

  @override
  Future<ImportProbeResult> probe(
    ImportSourceFile source,
    CancellationToken token,
  ) async {
    final parsed = await _readAndParse(source, token);
    if (parsed.cancelled) {
      return const ImportProbeResult.failure(FailureCode.cancelled);
    }
    if (parsed.failureCode != null) {
      return ImportProbeResult.failure(parsed.failureCode!);
    }
    final mapped = _map(parsed.file!, source.displayName, const <int>[]);
    return ImportProbeResult.recognized(
      warnings: mapped.warnings,
      parts: mapped.parts,
    );
  }

  @override
  Future<AppResult<SongImportResult>> import(
    ImportSourceFile source,
    SongImportOptions options,
    CancellationToken token,
  ) async {
    final read = await readImportSource(source, token);
    if (read.cancelled) {
      return const AppResult<SongImportResult>.failure(CancelledFailure());
    }
    if (read.failureCode != null) return _failure(read.failureCode!);
    final parsed = parser.parse(read.bytes!, token);
    if (parsed.cancelled || token.isCancelled) {
      return const AppResult<SongImportResult>.failure(CancelledFailure());
    }
    if (parsed.failureCode != null) return _failure(parsed.failureCode!);
    try {
      return AppResult<SongImportResult>.success(
        _map(parsed.file!, source.displayName, read.bytes!),
      );
    } on ArgumentError {
      return _failure(MidiImportFailureCode.invalidEvent);
    }
  }

  Future<MidiParseResult> _readAndParse(
    ImportSourceFile source,
    CancellationToken token,
  ) async {
    final read = await readImportSource(source, token);
    if (read.cancelled) return const MidiParseResult.cancelled();
    if (read.failureCode != null) {
      return MidiParseResult.failure(read.failureCode!);
    }
    return parser.parse(read.bytes!, token);
  }

  AppResult<SongImportResult> _failure(String code) =>
      AppResult<SongImportResult>.failure(ValidationFailure(code: code));

  SongImportResult _map(
    MidiFileData file,
    String displayName,
    List<int> original,
  ) {
    final all = file.tracks.expand((track) => track).toList()
      ..sort((a, b) => a.tick.compareTo(b.tick));
    final warnings = <String>[];
    final tracks = <SongTrack>[];
    final parts = <ImportPartPreview>[];
    for (var index = 0; index < file.tracks.length; index++) {
      final events = file.tracks[index];
      final name = _text(events, 0x103) ?? 'Track ${index + 1}';
      final notes = <SongNoteEvent>[];
      final active = <String, MidiEventData>{};
      int? channel;
      int? program;
      var endTick = 0;
      for (final event in events) {
        if (event.tick > endTick) endTick = event.tick;
        if (event.kind == 0xc0) {
          channel ??= event.channel;
          program = event.data.first;
        }
        if (event.kind == 0x90 && event.data[1] > 0) {
          channel ??= event.channel;
          active['${event.channel}-${event.data[0]}'] = event;
        }
        if (event.kind == 0x80 || (event.kind == 0x90 && event.data[1] == 0)) {
          final start = active.remove('${event.channel}-${event.data[0]}');
          if (start != null) {
            notes.add(_note(index, notes.length, start, event, file, all));
          }
        }
      }
      if (active.isNotEmpty) {
        warnings.add(MidiImportWarningCode.danglingNote);
        for (final start in active.values) {
          final end = MidiEventData(
            tick: endTick + file.ppq,
            track: index,
            kind: 0x80,
            channel: start.channel,
            data: start.data,
          );
          notes.add(_note(index, notes.length, start, end, file, all));
        }
      }
      if (notes.isNotEmpty) {
        final track = NoteTrack(
          id: SongTrackId('midi-track-${index + 1}'),
          name: name,
          instrument: SongInstrument(name: channel == 9 ? 'Percussion' : name),
          enabled: channel != 9,
          events: notes,
        );
        tracks.add(track);
        parts.add(
          midiPreview(
            id: track.id.value,
            name: name,
            channel: channel ?? 0,
            program: program,
            notes: notes,
            duration: timeline.atTick(endTick, file.ppq, all),
          ),
        );
      }
    }
    final tempo = _tempo(file, all);
    final meter = _meter(all);
    final key = _key(all);
    final markers = <SongMarker>[
      for (final event in all.where((e) => e.kind == 0x106))
        SongMarker(
          SongMarkerId('midi-marker-${event.tick}'),
          _utf8(event.data),
          0,
          SongMarkerKind.rehearsal,
        ),
    ];
    final lyrics = <SongLyricEvent>[
      for (final event in all.where((e) => e.kind == 0x105))
        SongLyricEvent(
          id: SongEventId('midi-lyric-${event.tick}'),
          at: timeline.atTick(event.tick, file.ppq, all),
          text: _utf8(event.data),
        ),
    ];
    if (lyrics.isNotEmpty) {
      tracks.add(
        LyricsTrack(
          id: SongTrackId('midi-lyrics'),
          name: 'Lyrics',
          instrument: SongInstrument(name: 'Vocals'),
          events: lyrics,
        ),
      );
    }
    final title = _text(all, 0x103) ?? _base(displayName);
    final document = SongDocument(
      schemaVersion: songDocumentSchemaVersion,
      id: SongId('midi-${_slug(title)}'),
      revision: 0,
      metadata: SongMetadata(title: title),
      source: SongSource(
        type: SongSourceType.midi,
        originalFileName: displayName,
        sha256: sha256.convert(original).toString(),
        importedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        importerVersion: 'midi@1',
        warningSummary: warnings,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      tracks: tracks,
      markers: markers,
      tempoMap: tempo,
      meterMap: meter,
      keyMap: key,
    );
    return SongImportResult(
      document: document,
      warnings: warnings,
      parts: parts,
    );
  }

  SongNoteEvent _note(
    int track,
    int number,
    MidiEventData start,
    MidiEventData end,
    MidiFileData file,
    List<MidiEventData> all,
  ) {
    final at = timeline.atTick(start.tick, file.ppq, all);
    return SongNoteEvent(
      id: SongEventId('midi-note-${track + 1}-${number + 1}'),
      start: at,
      duration: timeline.atTick(end.tick, file.ppq, all) - at,
      midiPitch: start.data[0],
      velocity: start.data[1],
    );
  }

  TempoMap _tempo(MidiFileData file, List<MidiEventData> events) {
    final changes = <TempoChange>[
      TempoChange(at: BeatPosition.zero, bpm: Tempo(120)),
    ];
    for (final e in events.where(
      (e) => e.kind == 0x151 && e.data.length == 3,
    )) {
      final bpm =
          (60000000 / ((e.data[0] << 16) | (e.data[1] << 8) | e.data[2]))
              .round();
      final at = timeline.beatAt(e.tick, file.ppq);
      if (at == BeatPosition.zero) {
        changes[0] = TempoChange(at: at, bpm: Tempo(bpm));
      } else if (changes.last.at != at) {
        changes.add(TempoChange(at: at, bpm: Tempo(bpm)));
      }
    }
    return TempoMap(changes);
  }

  MeterMap _meter(List<MidiEventData> events) {
    final event = events
        .where((e) => e.kind == 0x158 && e.data.length >= 2)
        .firstOrNull;
    return MeterMap([
      MeterChange(
        atMeasure: 0,
        meter: event == null
            ? Meter(4, 4)
            : Meter(event.data[0], 1 << event.data[1]),
      ),
    ]);
  }

  KeyMap _key(List<MidiEventData> events) {
    final event = events
        .where((e) => e.kind == 0x159 && e.data.length >= 2)
        .firstOrNull;
    final tonic = event == null
        ? 0
        : (event.data[0] > 127 ? event.data[0] - 256 : event.data[0]);
    return KeyMap([
      KeyChange(
        at: BeatPosition.zero,
        key: KeySignature(
          tonic.clamp(-6, 11),
          event?.data[1] == 1 ? KeyMode.minor : KeyMode.major,
        ),
      ),
    ]);
  }
}

String? _text(List<MidiEventData> events, int kind) {
  final event = events.where((event) => event.kind == kind).firstOrNull;
  return event == null ? null : _utf8(event.data);
}

String _utf8(List<int> value) =>
    utf8.decode(value, allowMalformed: true).trim();
String _base(String name) =>
    name.replaceFirst(RegExp(r'\.(mid|midi)$', caseSensitive: false), '');
String _slug(String value) =>
    value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '')
        .isEmpty
    ? 'import'
    : value
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
