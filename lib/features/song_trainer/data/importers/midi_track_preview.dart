import '../../domain/models/song_event.dart';
import '../../domain/services/note_track_analyzer.dart';
import 'song_importer.dart';

ImportPartPreview midiPreview({
  required String id,
  required String name,
  required int channel,
  required int? program,
  required List<SongNoteEvent> notes,
  required Duration duration,
}) {
  final analysis = const NoteTrackAnalyzer().analyze(notes);
  return ImportPartPreview(
    id: id,
    name: name,
    staffCount: 1,
    noteCount: notes.length,
    isPolyphonic: !analysis.isMonophonic,
    chordSymbolCount: 0,
    hasTablature: false,
    midiProgram: program,
    lowestMidiPitch: analysis.lowestPitch,
    highestMidiPitch: analysis.highestPitch,
    channel: channel,
    duration: duration,
    suspectedDrum: channel == 9,
    isMonophonic: analysis.isMonophonic,
  );
}
