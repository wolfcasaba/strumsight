import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';
import 'package:strumsight/features/song_trainer/data/importers/musicxml_importer.dart';
import 'package:strumsight/features/song_trainer/data/importers/midi_importer.dart';
import 'package:strumsight/features/song_trainer/data/importers/mxl_importer.dart';

void main() {
  test('production import registry wires MusicXML, MXL and MIDI importers', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final registry = container.read(songImporterRegistryProvider);

    expect(registry.importers, contains(isA<MusicXmlImporter>()));
    expect(registry.importers, contains(isA<MxlImporter>()));
    expect(registry.importers, contains(isA<MidiImporter>()));
  });
}
