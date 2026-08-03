import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import '../../../../core/music/chord.dart';
import '../../domain/models/key_map.dart';
import '../../domain/models/meter_map.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_event.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/song_instrument.dart';
import '../../domain/models/song_marker.dart';
import '../../domain/models/song_measure.dart';
import '../../domain/models/song_metadata.dart';
import '../../domain/models/song_source.dart';
import '../../domain/models/song_track.dart';
import '../../domain/models/tempo_map.dart';
import 'musicxml_repeat_expander.dart';
import 'song_importer.dart';

abstract final class MusicXmlMapWarningCode {
  static const String unsupportedElement =
      'songImport.musicXml.unsupportedElement';
  static const String timingQuantized = 'songImport.musicXml.timingQuantized';
  static const String repeatExpanded = 'songImport.musicXml.repeatExpanded';
  static const String repeatDisplayOnly =
      'songImport.musicXml.repeatDisplayOnly';
}

/// Maps the documented MusicXML subset into framework-free Song Trainer values.
final class MusicXmlMapper {
  const MusicXmlMapper({this.repeatExpander = const MusicXmlRepeatExpander()});

  final MusicXmlRepeatExpander repeatExpander;

  SongImportResult map({
    required XmlDocument xml,
    required String displayName,
    required List<int> originalBytes,
    required SongSourceType sourceType,
  }) {
    final root = xml.rootElement;
    final title =
        _firstText(root, 'work-title') ??
        _firstText(root, 'movement-title') ??
        'Untitled MusicXML';
    final creator = root
        .findAllElements('creator')
        .firstOrNull
        ?.innerText
        .trim();
    final parts = root.findAllElements('part').toList(growable: false);
    if (parts.isEmpty) throw const FormatException('missing part');
    final warnings = <String>[];
    final state = _MapState();
    final measures = <SongMeasure>[];
    final tempos = <TempoChange>[
      TempoChange(at: BeatPosition.zero, bpm: Tempo(120)),
    ];
    final meters = <MeterChange>[MeterChange(atMeasure: 0, meter: Meter(4, 4))];
    final keys = <KeyChange>[
      KeyChange(at: BeatPosition.zero, key: KeySignature(0, KeyMode.major)),
    ];
    final chords = <SongChordEvent>[];
    final notes = <SongNoteEvent>[];
    final lyrics = <SongLyricEvent>[];
    final markers = <SongMarker>[];
    var globalTicks = 0;

    for (final measure in parts.first.findElements('measure')) {
      final measureIndex = measures.length;
      final attributes = measure.findElements('attributes').firstOrNull;
      if (attributes != null) {
        final divisions = _integer(attributes, 'divisions');
        if (divisions != null && divisions > 0) state.divisions = divisions;
        final time = attributes.findElements('time').firstOrNull;
        if (time != null) {
          final beats = _integer(time, 'beats');
          final beatType = _integer(time, 'beat-type');
          if (beats != null && beatType != null && beatType > 0) {
            state.meter = Meter(beats, beatType);
            if (measureIndex > 0) {
              meters.add(
                MeterChange(atMeasure: measureIndex, meter: state.meter),
              );
            }
          }
        }
        final key = attributes.findElements('key').firstOrNull;
        final fifths = key == null ? null : _integer(key, 'fifths');
        if (fifths != null) {
          final mode = _firstText(key!, 'mode')?.trim() == 'minor'
              ? KeyMode.minor
              : KeyMode.major;
          state.key = KeySignature(fifths.clamp(-6, 11), mode);
          if (measureIndex > 0) {
            keys.add(
              KeyChange(
                at: BeatPosition.fromTicks(globalTicks),
                key: state.key,
              ),
            );
          }
        }
      }
      final sound = measure.findElements('sound').firstOrNull;
      final tempo = sound == null
          ? null
          : int.tryParse(sound.getAttribute('tempo') ?? '');
      if (tempo != null && tempo > 0 && tempo != state.tempo) {
        state.tempo = tempo;
        if (globalTicks > 0) {
          tempos.add(
            TempoChange(
              at: BeatPosition.fromTicks(globalTicks),
              bpm: Tempo(tempo),
            ),
          );
        } else {
          tempos[0] = TempoChange(at: BeatPosition.zero, bpm: Tempo(tempo));
        }
      }
      for (final direction in measure.findElements('direction')) {
        final rehearsal = _firstText(direction, 'rehearsal');
        if (rehearsal != null && rehearsal.trim().isNotEmpty) {
          markers.add(
            SongMarker(
              SongMarkerId('marker-$measureIndex-${markers.length}'),
              rehearsal.trim(),
              measureIndex,
              SongMarkerKind.rehearsal,
            ),
          );
        }
      }
      var cursor = 0;
      var maxCursor = 0;
      for (final child in measure.children.whereType<XmlElement>()) {
        if (child.name.local == 'backup') {
          cursor -= _ticks(
            _integer(child, 'duration') ?? 0,
            state.divisions,
            warnings,
          );
          continue;
        }
        if (child.name.local == 'forward') {
          cursor += _ticks(
            _integer(child, 'duration') ?? 0,
            state.divisions,
            warnings,
          );
          maxCursor = cursor > maxCursor ? cursor : maxCursor;
          continue;
        }
        if (child.name.local == 'harmony') {
          final rootStep = _firstText(child, 'root-step');
          if (rootStep != null) {
            final alter = _integer(child, 'root-alter') ?? 0;
            final kind = _firstText(child, 'kind')?.trim() ?? '';
            final label =
                '$rootStep${alter == 1
                    ? '#'
                    : alter == -1
                    ? 'b'
                    : ''}${kind == 'minor' ? 'm' : ''}';
            chords.add(
              SongChordEvent(
                id: SongEventId('chord-$measureIndex-${chords.length}'),
                start: _duration(globalTicks + cursor, state.tempo),
                duration: _duration(
                  state.meter.beatsPerMeasure * BeatPosition.ticksPerBeat,
                  state.tempo,
                ),
                symbol: Chord(label),
              ),
            );
          }
          continue;
        }
        if (child.name.local != 'note') continue;
        final durationTicks = _ticks(
          _integer(child, 'duration') ?? 0,
          state.divisions,
          warnings,
        );
        final isChord = child.findElements('chord').isNotEmpty;
        final startTicks = globalTicks + cursor;
        if (child.findElements('rest').isEmpty) {
          final pitch = child.findElements('pitch').firstOrNull;
          final step = pitch == null ? null : _firstText(pitch, 'step');
          final octave = pitch == null ? null : _integer(pitch, 'octave');
          if (step != null && octave != null) {
            final technical = child.findElements('technical').firstOrNull;
            final string = technical == null
                ? null
                : _integer(technical, 'string');
            final fret = technical == null ? null : _integer(technical, 'fret');
            notes.add(
              SongNoteEvent(
                id: SongEventId('note-$measureIndex-${notes.length}'),
                start: _duration(startTicks, state.tempo),
                duration: _duration(durationTicks, state.tempo),
                midiPitch: _midi(step, _integer(pitch!, 'alter') ?? 0, octave),
                stringIndex: string == null || fret == null ? null : 6 - string,
                fret: fret,
                tieGroupId: child.findElements('tie').isEmpty
                    ? null
                    : 'tie-${_midi(step, _integer(pitch, 'alter') ?? 0, octave)}',
              ),
            );
          }
          final lyric = _firstText(child, 'text');
          if (lyric != null && lyric.trim().isNotEmpty) {
            lyrics.add(
              SongLyricEvent(
                id: SongEventId('lyric-$measureIndex-${lyrics.length}'),
                at: _duration(startTicks, state.tempo),
                text: lyric.trim(),
              ),
            );
          }
        }
        if (!isChord) cursor += durationTicks;
        maxCursor = cursor > maxCursor ? cursor : maxCursor;
      }
      final repeatStart = measure
          .findAllElements('repeat')
          .any((value) => value.getAttribute('direction') == 'forward');
      final repeatEnd = measure
          .findAllElements('repeat')
          .where((value) => value.getAttribute('direction') == 'backward')
          .firstOrNull;
      final repeats =
          int.tryParse(repeatEnd?.getAttribute('times') ?? '') ??
          (repeatEnd == null ? null : 2);
      final expected = state.meter.beatsPerMeasure * BeatPosition.ticksPerBeat;
      measures.add(
        SongMeasure(
          index: measureIndex,
          displayNumber: int.tryParse(measure.getAttribute('number') ?? ''),
          durationBeats: BeatPosition.fromTicks(
            maxCursor == 0 ? expected : maxCursor,
          ),
          pickup: measure.getAttribute('implicit') == 'yes',
          repeatStart: repeatStart,
          repeatEndCount: repeats,
        ),
      );
      globalTicks += maxCursor == 0 ? expected : maxCursor;
    }
    final repeat = repeatExpander.expand(measures);
    if (repeat.isDisplayOnly) {
      warnings.add(MusicXmlMapWarningCode.repeatDisplayOnly);
    }
    if (repeat.measureIndexes.length > measures.length) {
      warnings.add(MusicXmlMapWarningCode.repeatExpanded);
    }
    final tracks = <SongTrack>[];
    if (chords.isNotEmpty) {
      tracks.add(
        ChordTrack(
          id: SongTrackId('chords'),
          name: 'Chords',
          instrument: SongInstrument(name: 'Guitar'),
          events: chords,
        ),
      );
    }
    if (notes.isNotEmpty) {
      tracks.add(
        NoteTrack(
          id: SongTrackId('part-1'),
          name: 'Part 1',
          instrument: SongInstrument(name: 'Guitar'),
          events: notes,
        ),
      );
    }
    if (lyrics.isNotEmpty) {
      tracks.add(
        LyricsTrack(
          id: SongTrackId('lyrics'),
          name: 'Lyrics',
          instrument: SongInstrument(name: 'Vocals'),
          events: lyrics,
        ),
      );
    }
    final document = SongDocument(
      schemaVersion: songDocumentSchemaVersion,
      id: SongId('musicxml-${_slug(title)}'),
      revision: 0,
      metadata: SongMetadata(title: title, composer: creator),
      source: SongSource(
        type: sourceType,
        originalFileName: displayName,
        sha256: _hash(originalBytes),
        importedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        importerVersion: 'musicxml@1',
        warningSummary: warnings,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      measures: measures,
      tracks: tracks,
      markers: markers,
      tempoMap: TempoMap(tempos),
      meterMap: MeterMap(meters),
      keyMap: KeyMap(keys),
    );
    return SongImportResult(document: document, warnings: warnings);
  }
}

final class _MapState {
  int divisions = 1;
  Meter meter = Meter(4, 4);
  int tempo = 120;
  KeySignature key = KeySignature(0, KeyMode.major);
}

int? _integer(XmlElement element, String name) =>
    int.tryParse(_firstText(element, name) ?? '');
String? _firstText(XmlElement element, String name) =>
    element.findAllElements(name).firstOrNull?.innerText;
int _ticks(int duration, int divisions, List<String> warnings) {
  final scaled = duration * BeatPosition.ticksPerBeat;
  if (scaled % divisions != 0) {
    warnings.add(MusicXmlMapWarningCode.timingQuantized);
  }
  return (scaled / divisions).round();
}

Duration _duration(int ticks, int bpm) => Duration(
  microseconds: (ticks * 60000000 / (BeatPosition.ticksPerBeat * bpm)).round(),
);
int _midi(String step, int alter, int octave) {
  const steps = <String, int>{
    'C': 0,
    'D': 2,
    'E': 4,
    'F': 5,
    'G': 7,
    'A': 9,
    'B': 11,
  };
  return (octave + 1) * 12 + (steps[step] ?? 0) + alter;
}

String _slug(String input) {
  final result = input
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return result.isEmpty ? 'score' : result;
}

String _hash(List<int> bytes) {
  return sha256.convert(bytes).toString();
}
