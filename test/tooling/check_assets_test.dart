import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/ci/check_assets.dart';

void main() {
  late Directory projectRoot;

  setUp(() {
    projectRoot = Directory.systemTemp.createTempSync(
      'strumsight_asset_check_',
    );
  });

  tearDown(() {
    projectRoot.deleteSync(recursive: true);
  });

  test('accepts existing declared Flutter assets and fonts', () {
    _writePubspec(projectRoot, '''
name: asset_fixture
dependencies:
  flutter:
    sdk: flutter
flutter:
  assets:
    - assets/ml/model.bin
  fonts:
    - family: Fixture
      fonts:
        - asset: assets/fonts/Fixture.ttf
''');
    _writeBytes(projectRoot, 'assets/ml/model.bin', const [1, 2, 3]);
    _writeBytes(projectRoot, 'assets/fonts/Fixture.ttf', const [4]);

    final report = checkAssets(projectRoot: projectRoot);

    expect(report.isClean, isTrue);
    expect(
      report.declaredPaths,
      equals(['assets/fonts/Fixture.ttf', 'assets/ml/model.bin']),
    );
  });

  test('reports every missing declared asset and font', () {
    _writePubspec(projectRoot, '''
name: asset_fixture
flutter:
  assets:
    - assets/ml/missing.bin
  fonts:
    - family: Fixture
      fonts:
        - asset: assets/fonts/Missing.ttf
''');

    final report = checkAssets(projectRoot: projectRoot);

    expect(report.isClean, isFalse);
    expect(
      report.issues
          .map((issue) => (issue.path, issue.kind))
          .toList(growable: false),
      equals([
        ('assets/fonts/Missing.ttf', AssetIssueKind.missing),
        ('assets/ml/missing.bin', AssetIssueKind.missing),
      ]),
    );
  });

  test('rejects only empty declared ML binaries', () {
    _writePubspec(projectRoot, '''
name: asset_fixture
flutter:
  assets:
    - assets/ml/model.bin
  fonts:
    - family: Fixture
      fonts:
        - asset: assets/fonts/Fixture.ttf
''');
    _writeBytes(projectRoot, 'assets/ml/model.bin', const []);
    _writeBytes(projectRoot, 'assets/fonts/Fixture.ttf', const []);
    _writeBytes(projectRoot, 'ml/strum_direction.tflite', const []);

    final report = checkAssets(projectRoot: projectRoot);

    expect(report.isClean, isFalse);
    expect(report.issues, hasLength(1));
    expect(report.issues.single.path, 'assets/ml/model.bin');
    expect(report.issues.single.kind, AssetIssueKind.emptyMlBinary);
  });
}

void _writePubspec(Directory projectRoot, String contents) {
  File('${projectRoot.path}/pubspec.yaml').writeAsStringSync(contents);
}

void _writeBytes(Directory projectRoot, String path, List<int> bytes) {
  final file = File('${projectRoot.path}/$path');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
}
