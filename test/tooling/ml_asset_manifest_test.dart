import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/ci/check_assets.dart';

const _manifestPath = 'assets/ml/model_manifest.json';
final _modelPathPattern = RegExp(
  r'^assets/ml/[A-Za-z0-9][A-Za-z0-9._-]*\.bin$',
);
final _checksumPattern = RegExp(r'^[0-9a-f]{64}$');

void main() {
  test('SHA-256 implementation matches standard vectors', () {
    expect(
      _sha256Hex(const []),
      'e3b0c44298fc1c149afbf4c8996fb924'
      '27ae41e4649b934ca495991b7852b855',
    );
    expect(
      _sha256Hex(utf8.encode('abc')),
      'ba7816bf8f01cfea414140de5dae2223'
      'b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('shipping manifest covers four valid declared ML binaries', () {
    final projectRoot = _findProjectRoot();

    final issues = _validateManifest(
      projectRoot: projectRoot,
      expectedModelCount: 4,
    );

    expect(issues, isEmpty, reason: issues.join('\n'));
  });

  test('fixture manifest asset is declared in its pubspec', () {
    final projectRoot = Directory.systemTemp.createTempSync(
      'strumsight_ml_manifest_',
    );
    addTearDown(() => projectRoot.deleteSync(recursive: true));
    const modelPath = 'assets/ml/model.bin';
    const modelBytes = [1, 2, 3, 4];
    _writeBytes(projectRoot, modelPath, modelBytes);
    _writeText(projectRoot, 'ml/export_fixture.py', '# fixture exporter\n');
    _writeText(projectRoot, 'pubspec.yaml', '''
name: ml_manifest_fixture
flutter:
  assets:
    - assets/ml/model.bin
''');
    _writeText(
      projectRoot,
      _manifestPath,
      '${jsonEncode({
        'schema_version': 1,
        'models': [
          {
            'filename': 'model.bin',
            'path': modelPath,
            'sha256': _sha256Hex(modelBytes),
            'format': 'SSML',
            'format_version': 1,
            'input_shape': [15, 128],
            'output_classes': ['down', 'up'],
            'training_run': {'origin': 'pre-manifest'},
            'export_script': {'path': 'ml/export_fixture.py', 'version': 'fixture-v1'},
            'created_at': '2026-07-30T00:00:00Z',
          },
        ],
      })}\n',
    );

    final issues = _validateManifest(projectRoot: projectRoot);

    expect(issues, isEmpty, reason: issues.join('\n'));
  });
}

Directory _findProjectRoot() {
  var candidate = Directory.current.absolute;
  while (true) {
    if (_isRegularFile('${candidate.path}/pubspec.yaml') &&
        _isRegularFile('${candidate.path}/AGENTS.md')) {
      return candidate;
    }
    final parent = candidate.parent;
    if (parent.path == candidate.path) {
      throw StateError('Could not find the StrumSight repository root.');
    }
    candidate = parent;
  }
}

List<String> _validateManifest({
  required Directory projectRoot,
  int? expectedModelCount,
}) {
  final issues = <String>[];
  final manifestFile = File('${projectRoot.absolute.path}/$_manifestPath');
  if (!_isRegularFile(manifestFile.path)) {
    return ['missing manifest: $_manifestPath'];
  }

  Object? decoded;
  try {
    decoded = jsonDecode(manifestFile.readAsStringSync());
  } on FormatException catch (error) {
    return ['invalid manifest JSON: $error'];
  }
  if (decoded is! Map<String, Object?>) {
    return ['manifest root must be a JSON object'];
  }
  if (decoded['schema_version'] != 1) {
    issues.add('manifest schema_version must be 1');
  }

  final models = decoded['models'];
  if (models is! List<Object?> || models.isEmpty) {
    issues.add('manifest models must be a non-empty list');
    return issues;
  }
  if (expectedModelCount != null && models.length != expectedModelCount) {
    issues.add(
      'manifest must name $expectedModelCount shipping models, '
      'found ${models.length}',
    );
  }

  final manifestPaths = <String>{};
  for (var index = 0; index < models.length; index++) {
    final model = models[index];
    if (model is! Map<String, Object?>) {
      issues.add('models[$index] must be a JSON object');
      continue;
    }

    final filename = _requiredString(model, 'filename', index, issues);
    final path = _requiredString(model, 'path', index, issues);
    final checksum = _requiredString(model, 'sha256', index, issues);
    _requiredString(model, 'format', index, issues);
    _validatePositiveInt(model, 'format_version', index, issues);
    _validatePositiveIntList(model, 'input_shape', index, issues);
    _validateOutputClasses(model, index, issues);
    _validateTrainingRun(model, index, issues);
    _validateExportScript(projectRoot, model, index, issues);
    _validateCreatedAt(model, index, issues);

    if (path == null) {
      continue;
    }
    if (!_modelPathPattern.hasMatch(path)) {
      issues.add(
        'models[$index].path must be a safe assets/ml/*.bin path: $path',
      );
      continue;
    }
    if (!manifestPaths.add(path)) {
      issues.add('duplicate manifest path: $path');
    }
    if (filename != path.substring(path.lastIndexOf('/') + 1)) {
      issues.add('models[$index].filename does not match its path: $path');
    }
    if (checksum == null || !_checksumPattern.hasMatch(checksum)) {
      issues.add('models[$index].sha256 must be 64 lowercase hex characters');
      continue;
    }

    final asset = File('${projectRoot.absolute.path}/$path');
    final entityType = FileSystemEntity.typeSync(
      asset.path,
      followLinks: false,
    );
    if (entityType != FileSystemEntityType.file) {
      issues.add('manifest asset is missing or not a regular file: $path');
      continue;
    }
    if (asset.lengthSync() == 0) {
      issues.add('manifest asset is empty: $path');
      continue;
    }
    final actualChecksum = _sha256Hex(asset.readAsBytesSync());
    if (actualChecksum != checksum) {
      issues.add(
        'checksum mismatch for $path: expected $checksum, '
        'actual $actualChecksum',
      );
    }
  }

  AssetCheckReport assetReport;
  try {
    assetReport = checkAssets(projectRoot: projectRoot);
  } on Object catch (error) {
    issues.add('could not read pubspec asset declarations: $error');
    return issues;
  }
  final declaredMlPaths = assetReport.declaredPaths
      .where(_modelPathPattern.hasMatch)
      .toSet();
  for (final path in manifestPaths.difference(declaredMlPaths)) {
    issues.add('manifest asset is not declared in pubspec: $path');
  }
  for (final path in declaredMlPaths.difference(manifestPaths)) {
    issues.add('pubspec ML binary is missing from manifest: $path');
  }
  return issues;
}

String? _requiredString(
  Map<String, Object?> model,
  String field,
  int index,
  List<String> issues,
) {
  final value = model[field];
  if (value is! String || value.trim().isEmpty) {
    issues.add('models[$index].$field must be a non-empty string');
    return null;
  }
  return value;
}

void _validatePositiveInt(
  Map<String, Object?> model,
  String field,
  int index,
  List<String> issues,
) {
  final value = model[field];
  if (value is! int || value <= 0) {
    issues.add('models[$index].$field must be a positive integer');
  }
}

void _validatePositiveIntList(
  Map<String, Object?> model,
  String field,
  int index,
  List<String> issues,
) {
  final value = model[field];
  if (value is! List<Object?> ||
      value.isEmpty ||
      value.any((dimension) => dimension is! int || dimension <= 0)) {
    issues.add('models[$index].$field must contain positive integers');
  }
}

void _validateOutputClasses(
  Map<String, Object?> model,
  int index,
  List<String> issues,
) {
  final value = model['output_classes'];
  if (value is! List<Object?> ||
      value.isEmpty ||
      value.any((label) => label is! String || label.trim().isEmpty)) {
    issues.add(
      'models[$index].output_classes must contain non-empty class labels',
    );
    return;
  }
  if (value.toSet().length != value.length) {
    issues.add('models[$index].output_classes contains duplicate labels');
  }
}

void _validateTrainingRun(
  Map<String, Object?> model,
  int index,
  List<String> issues,
) {
  final value = model['training_run'];
  if (value is! Map<String, Object?> ||
      value['origin'] is! String ||
      (value['origin'] as String).trim().isEmpty) {
    issues.add('models[$index].training_run.origin must be non-empty');
  }
}

void _validateExportScript(
  Directory projectRoot,
  Map<String, Object?> model,
  int index,
  List<String> issues,
) {
  final value = model['export_script'];
  if (value is! Map<String, Object?>) {
    issues.add('models[$index].export_script must be a JSON object');
    return;
  }
  final path = value['path'];
  final version = value['version'];
  if (path is! String ||
      path.trim().isEmpty ||
      path.startsWith('/') ||
      path.split('/').contains('..') ||
      !path.endsWith('.py')) {
    issues.add('models[$index].export_script.path must be a safe Python path');
  } else if (!_isRegularFile('${projectRoot.absolute.path}/$path')) {
    issues.add('models[$index].export_script.path does not exist: $path');
  }
  if (version is! String || version.trim().isEmpty) {
    issues.add('models[$index].export_script.version must be non-empty');
  }
}

void _validateCreatedAt(
  Map<String, Object?> model,
  int index,
  List<String> issues,
) {
  final value = model['created_at'];
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null || !parsed.isUtc) {
    issues.add('models[$index].created_at must be an ISO-8601 UTC timestamp');
  }
}

void _writeText(Directory projectRoot, String path, String contents) {
  final file = File('${projectRoot.path}/$path');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

void _writeBytes(Directory projectRoot, String path, List<int> bytes) {
  final file = File('${projectRoot.path}/$path');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
}

bool _isRegularFile(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false) ==
    FileSystemEntityType.file;

const _sha256Constants = <int>[
  0x428a2f98,
  0x71374491,
  0xb5c0fbcf,
  0xe9b5dba5,
  0x3956c25b,
  0x59f111f1,
  0x923f82a4,
  0xab1c5ed5,
  0xd807aa98,
  0x12835b01,
  0x243185be,
  0x550c7dc3,
  0x72be5d74,
  0x80deb1fe,
  0x9bdc06a7,
  0xc19bf174,
  0xe49b69c1,
  0xefbe4786,
  0x0fc19dc6,
  0x240ca1cc,
  0x2de92c6f,
  0x4a7484aa,
  0x5cb0a9dc,
  0x76f988da,
  0x983e5152,
  0xa831c66d,
  0xb00327c8,
  0xbf597fc7,
  0xc6e00bf3,
  0xd5a79147,
  0x06ca6351,
  0x14292967,
  0x27b70a85,
  0x2e1b2138,
  0x4d2c6dfc,
  0x53380d13,
  0x650a7354,
  0x766a0abb,
  0x81c2c92e,
  0x92722c85,
  0xa2bfe8a1,
  0xa81a664b,
  0xc24b8b70,
  0xc76c51a3,
  0xd192e819,
  0xd6990624,
  0xf40e3585,
  0x106aa070,
  0x19a4c116,
  0x1e376c08,
  0x2748774c,
  0x34b0bcb5,
  0x391c0cb3,
  0x4ed8aa4a,
  0x5b9cca4f,
  0x682e6ff3,
  0x748f82ee,
  0x78a5636f,
  0x84c87814,
  0x8cc70208,
  0x90befffa,
  0xa4506ceb,
  0xbef9a3f7,
  0xc67178f2,
];

String _sha256Hex(List<int> input) {
  final bitLength = input.length * 8;
  final padded = BytesBuilder(copy: false)
    ..add(input)
    ..addByte(0x80);
  while ((padded.length + 8) % 64 != 0) {
    padded.addByte(0);
  }
  for (var shift = 56; shift >= 0; shift -= 8) {
    padded.addByte((bitLength >> shift) & 0xff);
  }
  final message = padded.takeBytes();
  final hash = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  final words = Uint32List(64);

  for (var offset = 0; offset < message.length; offset += 64) {
    for (var index = 0; index < 16; index++) {
      final start = offset + index * 4;
      words[index] =
          (message[start] << 24) |
          (message[start + 1] << 16) |
          (message[start + 2] << 8) |
          message[start + 3];
    }
    for (var index = 16; index < 64; index++) {
      final s0 =
          _rotateRight(words[index - 15], 7) ^
          _rotateRight(words[index - 15], 18) ^
          (words[index - 15] >> 3);
      final s1 =
          _rotateRight(words[index - 2], 17) ^
          _rotateRight(words[index - 2], 19) ^
          (words[index - 2] >> 10);
      words[index] =
          (words[index - 16] + s0 + words[index - 7] + s1) & 0xffffffff;
    }

    var a = hash[0];
    var b = hash[1];
    var c = hash[2];
    var d = hash[3];
    var e = hash[4];
    var f = hash[5];
    var g = hash[6];
    var h = hash[7];
    for (var index = 0; index < 64; index++) {
      final upperSigma1 =
          _rotateRight(e, 6) ^ _rotateRight(e, 11) ^ _rotateRight(e, 25);
      final choose = (e & f) ^ ((~e) & g);
      final temp1 =
          (h + upperSigma1 + choose + _sha256Constants[index] + words[index]) &
          0xffffffff;
      final upperSigma0 =
          _rotateRight(a, 2) ^ _rotateRight(a, 13) ^ _rotateRight(a, 22);
      final majority = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (upperSigma0 + majority) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xffffffff;
    }
    hash[0] = (hash[0] + a) & 0xffffffff;
    hash[1] = (hash[1] + b) & 0xffffffff;
    hash[2] = (hash[2] + c) & 0xffffffff;
    hash[3] = (hash[3] + d) & 0xffffffff;
    hash[4] = (hash[4] + e) & 0xffffffff;
    hash[5] = (hash[5] + f) & 0xffffffff;
    hash[6] = (hash[6] + g) & 0xffffffff;
    hash[7] = (hash[7] + h) & 0xffffffff;
  }

  return hash.map((word) => word.toRadixString(16).padLeft(8, '0')).join();
}

int _rotateRight(int value, int count) =>
    ((value >> count) | (value << (32 - count))) & 0xffffffff;
