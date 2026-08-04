import 'dart:io';

import 'package:crypto/crypto.dart';

final class _FixtureProvenance {
  const _FixtureProvenance({
    required this.path,
    required this.provenance,
    required this.licence,
    required this.sha256,
  });

  final String path;
  final String provenance;
  final String licence;
  final String sha256;
}

const _projectAuthored =
    'project-authored synthetic test fixture, no third-party musical content';
const _projectAuthoredLicence = 'Project-authored synthetic test fixture.';

const _manifest = <_FixtureProvenance>[
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/guitar_pro/minimal_gp3.gp3',
    provenance:
        'New, one-track score authored for this repository and written with PyGuitarPro 0.11.0.',
    licence: _projectAuthoredLicence,
    sha256: '53ee2cc024d46a8fb3c761f857f589eb3d0901468a323adea2e98247d59fb473',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/guitar_pro/minimal_gp5.gp5',
    provenance:
        'Same newly authored score, written as GP 5.1 with PyGuitarPro 0.11.0.',
    licence: _projectAuthoredLicence,
    sha256: '140cccae4b4cb228ce262cbf76a94326b0dcabea9c9e98f9dfc83e3cdb8cd216',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/guitar_pro/minimal_gpx.gpx',
    provenance:
        '`packages/alphatab/test-data/guitarpro6/notes.gpx` from alphaTab commit `a186437bb3263e5ae3f8fd373aef1fef5ebbc7e7`, retained under its MPL-2.0 licence.',
    licence: 'MPL-2.0',
    sha256: 'b437b7a2b3e212822acadd67877807baee48837ea76d9b737bfbf9f5db9c07fc',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/legacy/setlist_duplicate.json',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: '4fa9d22d856154572b35d0020cf6cd29aa86e190203bc57f573ce631538ba7b2',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/legacy/setlist_missing_song.json',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: '6d9492bfa7713a54d5afe854244e6357fc771ed7bc59bd502a8a430c68f30756',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/legacy/setlist_mixed_bpm.json',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: 'f3fc76d1122add6bd5e6811fcdb68a83839c0d03f6e55a34ae48acc0e482e1f1',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/legacy/song_34.json',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: '878a557da2bc6c76c42593af798ae570c3e78bae0841aeccdeb68b644bdb69f7',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/legacy/song_44.json',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: '1c6390a2700be0226d7b0706b36d05a4ad064f43e4add98ba62db6be5a7f7b41',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/legacy/song_multiple_chords.json',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: '727b56a0df6ac9ad4a58583add1c5f5f417504f8b668df89f9677e7c02e202ee',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/legacy/song_rests.json',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: '9bab452ee9bbe01de35ec02b680cfac35307f4e9f8e9693358f11dd2ccbbbaed',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/midi/format0.mid',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: 'c1b7c74fd988bc25e434dd80c6a1b570464c5d28c0d96a6468f4dbbed6b91f93',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/midi/format1_multitrack.mid',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: 'c4b5ccd72251a3e3b30eb9d1147d8ed04df1ec0c73f77ac428aac7dc09fa75d3',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/midi/malformed_chunks.mid',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: '1dc972dc7beb3ce451e7c94a69dde1088ec427112f30c93f03800595ade98ce0',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/midi/polyphonic_drum.mid',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: 'bf74291c359b790c648d2a590545beb748578fb5d323937f6ba1146732b4e83e',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/midi/running_velocity0.mid',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: '1f598d44510c8251c316994fdbcc30e0ec7e592018d34998cbcd8011da15ce7e',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/midi/tempo_meter_marker.mid',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: 'b7884f6a7e1bc1b1774689b0a9731e52c54f851ef7b065b8afe8f250951e0ebf',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/musicxml/chord_chart_44.musicxml',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: '99f0838343bf8ef32af524cc415d5f711b1f65153afe603601818c3a003a5d25',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/musicxml/corrupt.musicxml',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: '7f1fe8373cef67deb860f9dbe35fe1c81d70e86ca8c6aded239fc4c6d81c4be5',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/musicxml/markers_lyrics_repeat.musicxml',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: '25c73cb1abf24ea6111f911927686bf702040cf666423dbcbc52ca0e20c0a194',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/musicxml/meter_68.musicxml',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: '04393a7c1327156d72d3eb3b0e2ed0473f130f5e05de48febab796a36fcdf979',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/musicxml/monophonic_tie_rest.musicxml',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: '626856970f2c522263880d118efb3246b3d1772a30ba84c250428b525576600d',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/musicxml/multipart_polyphonic.musicxml',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: '0c0d69f2cb45502e4b1c3c2b4bf56eb5f7523bd07ce0b506e7f57cd29a79986a',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/musicxml/tempo_meter_pickup.musicxml',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: 'ddecbe808e8821379cc1f6e6b1e1a5b3a5b9018066c30eaf75dd7526eee8362f',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/musicxml/two_chords.musicxml',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: '6a35ee52c1ab8e1e1b501c04f9f4aa591a5606a71344a346c2a873108e801604',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/musicxml/waltz_34.musicxml',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: '398ac32be7fb7b8fd239e977fb182b9afb62f292160eaaee7dd22a362046fb44',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/mxl/extracted_limit.mxl',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: '893af338d04a433be060acd7cc71cc7455c64841cee0c419f5baaaa63a0f6e08',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/mxl/malicious_path.mxl',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: '62e505213895a61ea8e5a047297d219f803bdd37631b488f192c463d67a1096f',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/native/corrupt.strumsight-song.json',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: '14b3f36a005f062412df3c2f1b90b55180ace98f87b118b52badc3d2be70a466',
  ),
  _FixtureProvenance(
    path: 'test/fixtures/song_trainer/native/full_song.strumsight-song.json',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: 'bf0b360733eac1521757183061e74e17efeb14f6b776355491623a06fb5d3d9a',
  ),
  _FixtureProvenance(
    path:
        'test/fixtures/song_trainer/native/newer_version.strumsight-song.json',
    provenance: _projectAuthored,
    licence: _projectAuthoredLicence,
    sha256: '6cfd985e9604454e0b94d7b30dcfbde74ff104076c7d66b53da4aff7fd3b68b5',
  ),
];

Future<List<String>> _fixtureFiles(Directory root) async {
  final fixtureRoot = Directory(
    '${root.path}${Platform.pathSeparator}test${Platform.pathSeparator}fixtures${Platform.pathSeparator}song_trainer',
  );
  final entries = <String>[];
  await for (final entity in fixtureRoot.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File ||
        entity.path.endsWith('${Platform.pathSeparator}README.md')) {
      continue;
    }
    final prefix = '${root.absolute.path}${Platform.pathSeparator}';
    final absolute = entity.absolute.path;
    if (absolute.startsWith(prefix)) {
      entries.add(absolute.substring(prefix.length).replaceAll('\\', '/'));
    }
  }
  entries.sort();
  return entries;
}

Future<List<String>> _issues(Directory root) async {
  final issues = <String>[];
  final manifestByPath = <String, _FixtureProvenance>{};
  for (final entry in _manifest) {
    if (entry.provenance.isEmpty ||
        entry.licence.isEmpty ||
        entry.sha256.isEmpty) {
      issues.add('${entry.path}: incomplete provenance entry');
    }
    if (manifestByPath.containsKey(entry.path)) {
      issues.add('${entry.path}: duplicate manifest entry');
    }
    manifestByPath[entry.path] = entry;
  }

  final fixturePaths = await _fixtureFiles(root);
  final fixtureSet = fixturePaths.toSet();
  for (final entry in _manifest) {
    if (!fixtureSet.contains(entry.path)) {
      issues.add('${entry.path}: manifest fixture is missing');
      continue;
    }
    final bytes = await File(
      '${root.path}${Platform.pathSeparator}${entry.path}',
    ).readAsBytes();
    if (sha256.convert(bytes).toString() != entry.sha256) {
      issues.add('${entry.path}: SHA-256 differs from provenance manifest');
    }
  }
  for (final path in fixturePaths) {
    if (!manifestByPath.containsKey(path)) {
      issues.add('$path: fixture has no provenance manifest entry');
    }
  }
  return issues;
}

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/ci/check_song_fixture_licenses.dart');
    exitCode = 64;
    return;
  }
  final issues = await _issues(Directory.current);
  if (issues.isEmpty) {
    stdout.writeln(
      'Song fixture provenance OK (${_manifest.length} fixtures).',
    );
    return;
  }
  stderr
    ..writeln('Song fixture provenance failed.')
    ..writeAll(issues.map((issue) => '- $issue\n'));
  exitCode = 1;
}
