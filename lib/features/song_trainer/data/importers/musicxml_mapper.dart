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

  /// Returns source-derived, selectable part summaries without persisting data.
  List<ImportPartPreview> preview(XmlDocument xml) {
    final root = xml.rootElement;
    final parts = root.findAllElements('part').toList(growable: false);
    final definitions = root
        .findAllElements('score-part')
        .toList(growable: false);
    return List<ImportPartPreview>.unmodifiable(<ImportPartPreview>[
      for (var index = 0; index < parts.length; index++)
        _previewPart(parts[index], definitions, index),
    ]);
  }

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
    final partPreviews = preview(xml);
    final warnings = <String>[];
    final measures = <SongMeasure>[];
    final tempos = <TempoChange>[
      TempoChange(at: BeatPosition.zero, bpm: Tempo(120)),
    ];
    final meters = <MeterChange>[MeterChange(atMeasure: 0, meter: Meter(4, 4))];
    final keys = <KeyChange>[
      KeyChange(at: BeatPosition.zero, key: KeySignature(0, KeyMode.major)),
    ];
    final markers = <SongMarker>[];
    final tracks = <SongTrack>[];

    for (var partIndex = 0; partIndex < parts.length; partIndex++) {
      final part = parts[partIndex];
      final partPreview = partPreviews[partIndex];
      final state = _MapState();
      final partMeasures = <SongMeasure>[];
      final chords = <SongChordEvent>[];
      final notes = <SongNoteEvent>[];
      final lyrics = <SongLyricEvent>[];
      var globalTicks = 0;

      for (final measure in part.findElements('measure')) {
        final measureIndex = partMeasures.length;
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
              if (partIndex == 0) {
                if (measureIndex == 0) {
                  meters[0] = MeterChange(atMeasure: 0, meter: state.meter);
                } else {
                  meters.add(
                    MeterChange(atMeasure: measureIndex, meter: state.meter),
                  );
                }
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
            if (partIndex == 0) {
              final keyChange = KeyChange(
                at: BeatPosition.fromTicks(globalTicks),
                key: state.key,
              );
              if (measureIndex == 0) {
                keys[0] = keyChange;
              } else {
                keys.add(keyChange);
              }
            }
          }
        }
        final sound = measure.findElements('sound').firstOrNull;
        final tempo = sound == null
            ? null
            : int.tryParse(sound.getAttribute('tempo') ?? '');
        if (tempo != null && tempo > 0 && tempo != state.tempo) {
          state.tempo = tempo;
          if (partIndex == 0 && globalTicks > 0) {
            tempos.add(
              TempoChange(
                at: BeatPosition.fromTicks(globalTicks),
                bpm: Tempo(tempo),
              ),
            );
          } else if (partIndex == 0) {
            tempos[0] = TempoChange(at: BeatPosition.zero, bpm: Tempo(tempo));
          }
        }
        for (final direction in measure.findElements('direction')) {
          final rehearsal = _firstText(direction, 'rehearsal');
          if (partIndex == 0 &&
              rehearsal != null &&
              rehearsal.trim().isNotEmpty) {
            markers.add(
              SongMarker(
                SongMarkerId('marker-$measureIndex-${markers.length}'),
                rehearsal.trim(),
                measureIndex,
                SongMarkerKind.rehearsal,
              ),
            );
          }
          if (_hasUnsupportedDirection(direction)) {
            _addWarning(warnings, MusicXmlMapWarningCode.unsupportedElement);
          }
        }
        var cursor = 0;
        var maxCursor = 0;
        var previousNoteCursor = 0;
        for (final child in measure.children.whereType<XmlElement>()) {
          if (!_supportedMeasureChildren.contains(child.name.local)) {
            _addWarning(warnings, MusicXmlMapWarningCode.unsupportedElement);
            continue;
          }
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
          if (_hasUnsupportedNotation(child)) {
            _addWarning(warnings, MusicXmlMapWarningCode.unsupportedElement);
          }
          final durationTicks = _ticks(
            _integer(child, 'duration') ?? 0,
            state.divisions,
            warnings,
          );
          final isChord = child.findElements('chord').isNotEmpty;
          final startTicks =
              globalTicks + (isChord ? previousNoteCursor : cursor);
          if (child.findElements('rest').isEmpty) {
            final pitch = child.findElements('pitch').firstOrNull;
            final step = pitch == null ? null : _firstText(pitch, 'step');
            final octave = pitch == null ? null : _integer(pitch, 'octave');
            if (step != null && octave != null) {
              final technical = child.findAllElements('technical').firstOrNull;
              final string = technical == null
                  ? null
                  : _integer(technical, 'string');
              final fret = technical == null
                  ? null
                  : _integer(technical, 'fret');
              notes.add(
                SongNoteEvent(
                  id: SongEventId('note-$measureIndex-${notes.length}'),
                  start: _duration(startTicks, state.tempo),
                  duration: _duration(durationTicks, state.tempo),
                  midiPitch: _midi(
                    step,
                    _integer(pitch!, 'alter') ?? 0,
                    octave,
                  ),
                  stringIndex: string == null || fret == null
                      ? null
                      : 6 - string,
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
          if (!isChord) {
            previousNoteCursor = cursor;
            cursor += durationTicks;
          }
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
        final expected =
            state.meter.beatsPerMeasure * BeatPosition.ticksPerBeat;
        partMeasures.add(
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
      final repeat = repeatExpander.expand(partMeasures);
      if (repeat.isDisplayOnly) {
        _addWarning(warnings, MusicXmlMapWarningCode.repeatDisplayOnly);
      }
      if (repeat.measureIndexes.length > partMeasures.length) {
        _addWarning(warnings, MusicXmlMapWarningCode.repeatExpanded);
      }
      if (partIndex == 0) measures.addAll(partMeasures);
      if (chords.isNotEmpty) {
        tracks.add(
          ChordTrack(
            id: SongTrackId('part-${partIndex + 1}-chords'),
            name: '${partPreview.name} Chords',
            instrument: SongInstrument(name: partPreview.name),
            events: chords,
          ),
        );
      }
      if (notes.isNotEmpty) {
        tracks.add(
          NoteTrack(
            id: SongTrackId('part-${partIndex + 1}'),
            name: partPreview.name,
            instrument: SongInstrument(name: partPreview.name),
            events: notes,
          ),
        );
      }
      if (lyrics.isNotEmpty) {
        tracks.add(
          LyricsTrack(
            id: SongTrackId('part-${partIndex + 1}-lyrics'),
            name: '${partPreview.name} Lyrics',
            instrument: SongInstrument(name: 'Vocals'),
            events: lyrics,
          ),
        );
      }
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
    return SongImportResult(
      document: document,
      warnings: warnings,
      parts: partPreviews,
    );
  }
}

final class _MapState {
  int divisions = 1;
  Meter meter = Meter(4, 4);
  int tempo = 120;
  KeySignature key = KeySignature(0, KeyMode.major);
}

const Set<String> _supportedMeasureChildren = <String>{
  'attributes',
  'backup',
  'barline',
  'direction',
  'forward',
  'harmony',
  'note',
  'sound',
};

ImportPartPreview _previewPart(
  XmlElement part,
  List<XmlElement> definitions,
  int index,
) {
  final id = part.getAttribute('id') ?? 'part-${index + 1}';
  final definition = definitions
      .where((candidate) => candidate.getAttribute('id') == id)
      .firstOrNull;
  final name =
      _firstText(definition ?? part, 'part-name') ?? 'Part ${index + 1}';
  final midiProgram = definition == null
      ? null
      : int.tryParse(_firstText(definition, 'midi-program') ?? '');
  final staffCount = int.tryParse(_firstText(part, 'staves') ?? '') ?? 1;
  final pitches = <int>[];
  final intervals = <_NoteInterval>[];
  var hasTablature = false;
  var divisions = 1;
  var globalTicks = 0;

  for (final measure in part.findElements('measure')) {
    final attributes = measure.findElements('attributes').firstOrNull;
    final parsedDivisions = attributes == null
        ? null
        : _integer(attributes, 'divisions');
    if (parsedDivisions != null && parsedDivisions > 0) {
      divisions = parsedDivisions;
    }
    var cursor = 0;
    var maxCursor = 0;
    var previousNoteCursor = 0;
    for (final child in measure.children.whereType<XmlElement>()) {
      switch (child.name.local) {
        case 'backup':
          cursor -= _previewTicks(_integer(child, 'duration') ?? 0, divisions);
        case 'forward':
          cursor += _previewTicks(_integer(child, 'duration') ?? 0, divisions);
          maxCursor = cursor > maxCursor ? cursor : maxCursor;
        case 'note':
          final duration = _previewTicks(
            _integer(child, 'duration') ?? 0,
            divisions,
          );
          final isChord = child.findElements('chord').isNotEmpty;
          if (child.findElements('rest').isEmpty) {
            final pitch = child.findElements('pitch').firstOrNull;
            final step = pitch == null ? null : _firstText(pitch, 'step');
            final octave = pitch == null ? null : _integer(pitch, 'octave');
            if (step != null && octave != null) {
              final midi = _midi(step, _integer(pitch!, 'alter') ?? 0, octave);
              pitches.add(midi);
              intervals.add(
                _NoteInterval(
                  start: globalTicks + (isChord ? previousNoteCursor : cursor),
                  end:
                      globalTicks +
                      (isChord ? previousNoteCursor : cursor) +
                      duration,
                ),
              );
            }
            final technical = child.findAllElements('technical').firstOrNull;
            hasTablature =
                hasTablature ||
                (technical != null &&
                    _integer(technical, 'string') != null &&
                    _integer(technical, 'fret') != null);
          }
          if (!isChord) {
            previousNoteCursor = cursor;
            cursor += duration;
          }
          maxCursor = cursor > maxCursor ? cursor : maxCursor;
        default:
          break;
      }
    }
    globalTicks += maxCursor;
  }
  return ImportPartPreview(
    id: id,
    name: name,
    midiProgram: midiProgram,
    staffCount: staffCount,
    noteCount: pitches.length,
    lowestMidiPitch: pitches.isEmpty ? null : pitches.reduce(_minimum),
    highestMidiPitch: pitches.isEmpty ? null : pitches.reduce(_maximum),
    isPolyphonic: _hasOverlappingIntervals(intervals),
    chordSymbolCount: part.findAllElements('harmony').length,
    hasTablature: hasTablature,
  );
}

final class _NoteInterval {
  const _NoteInterval({required this.start, required this.end});

  final int start;
  final int end;
}

bool _hasOverlappingIntervals(List<_NoteInterval> intervals) {
  for (var index = 0; index < intervals.length; index++) {
    for (var otherIndex = 0; otherIndex < index; otherIndex++) {
      final current = intervals[index];
      final other = intervals[otherIndex];
      if (current.start < other.end && other.start < current.end) return true;
    }
  }
  return false;
}

bool _hasUnsupportedDirection(XmlElement direction) {
  final directionType = direction.findElements('direction-type').firstOrNull;
  if (directionType == null) return true;
  return directionType.children.whereType<XmlElement>().any(
    (element) => element.name.local != 'rehearsal',
  );
}

bool _hasUnsupportedNotation(XmlElement note) {
  for (final notations in note.findElements('notations')) {
    for (final notation in notations.children.whereType<XmlElement>()) {
      if (notation.name.local != 'technical') return true;
      if (notation.children.whereType<XmlElement>().any(
        (element) =>
            element.name.local != 'string' && element.name.local != 'fret',
      )) {
        return true;
      }
    }
  }
  return false;
}

void _addWarning(List<String> warnings, String warning) {
  if (!warnings.contains(warning)) warnings.add(warning);
}

int _previewTicks(int duration, int divisions) =>
    (duration * BeatPosition.ticksPerBeat / divisions).round();
int _minimum(int left, int right) => left < right ? left : right;
int _maximum(int left, int right) => left > right ? left : right;

int? _integer(XmlElement element, String name) =>
    int.tryParse(_firstText(element, name) ?? '');
String? _firstText(XmlElement element, String name) =>
    element.findAllElements(name).firstOrNull?.innerText;
int _ticks(int duration, int divisions, List<String> warnings) {
  final scaled = duration * BeatPosition.ticksPerBeat;
  if (scaled % divisions != 0) {
    _addWarning(warnings, MusicXmlMapWarningCode.timingQuantized);
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
