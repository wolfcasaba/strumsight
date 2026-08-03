import 'dart:io';

import 'package:test/test.dart';

// The tool is also analyzed from the root Flutter package in CI.
// ignore: avoid_relative_lib_imports
import '../lib/gp_spike.dart';

void main() {
  final fixtureDirectory = _fixtureDirectory();
  final alphaTabModule = Platform.environment['ALPHATAB_MODULE_PATH'];

  group('AlphaTabProbe', () {
    test('reports the documented GP3 fidelity snapshot', () async {
      final result = await AlphaTabProbe(
        modulePath: alphaTabModule!,
      ).probe(File('${fixtureDirectory.path}/minimal_gp3.gp3').uri);

      expect(result, minimalGp3Expectation);
    });

    test('reports the documented GP5 fidelity snapshot', () async {
      final result = await AlphaTabProbe(
        modulePath: alphaTabModule!,
      ).probe(File('${fixtureDirectory.path}/minimal_gp5.gp5').uri);

      expect(result, minimalGp5Expectation);
    });

    test('reports the documented GPX fidelity snapshot', () async {
      final result = await AlphaTabProbe(
        modulePath: alphaTabModule!,
      ).probe(File('${fixtureDirectory.path}/minimal_gpx.gpx').uri);

      expect(result, minimalGpxExpectation);
    });

    test(
      'contains a malformed GP input failure without terminating the tool',
      () async {
        final malformed = await Directory.systemTemp.createTemp('gp-spike-');
        addTearDown(() => malformed.delete(recursive: true));
        final file = File('${malformed.path}/malformed.gp5');
        await file.writeAsBytes(const [
          0x46,
          0x49,
          0x43,
          0x48,
          0x49,
          0x45,
          0x52,
        ]);

        final outcome = await AlphaTabProbe(
          modulePath: alphaTabModule!,
        ).tryProbe(file.uri);

        expect(outcome, isA<GuitarProProbeFailure>());
      },
    );
  });
}

Directory _fixtureDirectory() {
  const relativePath = 'test/fixtures/song_trainer/guitar_pro';
  final fromRepositoryRoot = Directory(relativePath);
  if (fromRepositoryRoot.existsSync()) {
    return fromRepositoryRoot;
  }
  final fromToolDirectory = Directory('../../$relativePath');
  if (fromToolDirectory.existsSync()) {
    return fromToolDirectory;
  }
  throw StateError('Guitar Pro technical fixtures are unavailable.');
}
