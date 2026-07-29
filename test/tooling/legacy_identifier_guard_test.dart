import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SDD Ch2, Kör 2 (§2.5) — the inherited pre-StrumSight project identifiers
/// must never come back into production files.
///
/// The banned literals are assembled from fragments on purpose: if this file
/// spelled them out it would be its own first failure, and self-excluding the
/// guard from its own scan would leave a blind spot.
const _fragment = 'music';
final _legacyPackageName = '${_fragment}_theory';
final _legacyDartImport = 'package:$_legacyPackageName';
final _legacyAndroidId = 'com.${_fragment}theory.$_legacyPackageName';
final _legacyIosId = 'com.${_fragment}theory.${_fragment}Theory';

/// Directories that are generated, vendored or binary — never source.
const _skippedDirs = <String>{
  '.git',
  '.dart_tool',
  'build',
  'node_modules',
  'Pods',
  '.gradle',
  '.idea',
};

/// Historical documents are allowed to name the old identifiers: the SDD
/// chapters specify the rename itself, and HANDOFF/baseline/plan chunks are a
/// dated record of how the project got here. Rewriting them would falsify
/// history, so they are allowlisted rather than scrubbed.
///
/// Every entry is a repo-relative path prefix.
const _historicalDocAllowlist = <String>['docs/', 'HANDOFF.md'];

/// Only text formats that can plausibly carry an identifier are read.
const _scannedExtensions = <String>{
  '.dart',
  '.kt',
  '.java',
  '.gradle',
  '.kts',
  '.yaml',
  '.yml',
  '.json',
  '.xml',
  '.plist',
  '.pbxproj',
  '.entitlements',
  '.xcconfig',
  '.html',
  '.md',
  '.py',
  '.sh',
  '.mjs',
  '.js',
  '.toml',
  '.cfg',
  '.properties',
  '.arb',
  '.txt',
};

bool _isAllowlisted(String relativePath) =>
    _historicalDocAllowlist.any(relativePath.startsWith);

bool _isScannable(String relativePath) {
  final dot = relativePath.lastIndexOf('.');
  if (dot < 0) return false;
  return _scannedExtensions.contains(relativePath.substring(dot));
}

Iterable<File> _sourceFiles(Directory root) sync* {
  final rootPath = root.path;
  for (final entity in root.listSync(recursive: false, followLinks: false)) {
    final name = entity.path.split(Platform.pathSeparator).last;
    if (entity is Directory) {
      if (_skippedDirs.contains(name)) continue;
      yield* _sourceFiles(entity);
    } else if (entity is File) {
      final relative = entity.path
          .substring(rootPath.length)
          .replaceAll(Platform.pathSeparator, '/')
          .replaceFirst(RegExp('^/'), '');
      if (!_isScannable(relative)) continue;
      yield entity;
    }
  }
}

void main() {
  test(
    'no production file carries a legacy $_legacyPackageName identifier',
    () {
      final root = Directory.current;
      final rootPath = root.path;
      final banned = <String, String>{
        _legacyDartImport: 'legacy Dart package import',
        _legacyAndroidId: 'legacy Android application id / namespace',
        _legacyIosId: 'legacy iOS bundle identifier',
        _legacyPackageName: 'legacy project name',
      };

      final offences = <String>[];
      for (final file in _sourceFiles(root)) {
        final relative = file.path
            .substring(rootPath.length)
            .replaceAll(Platform.pathSeparator, '/')
            .replaceFirst(RegExp('^/'), '');
        if (_isAllowlisted(relative)) continue;

        final String contents;
        try {
          contents = file.readAsStringSync();
        } on FileSystemException {
          continue; // unreadable or not valid UTF-8 — not a source file
        }

        final lines = contents.split('\n');
        for (var i = 0; i < lines.length; i++) {
          for (final entry in banned.entries) {
            if (lines[i].contains(entry.key)) {
              offences.add(
                '$relative:${i + 1} — ${entry.value} '
                '("${entry.key}")',
              );
              break; // one report per line; the broadest pattern is last
            }
          }
        }
      }

      expect(
        offences,
        isEmpty,
        reason:
            'SDD Ch2 Kör 2 §2.5: the app is StrumSight '
            '(package:strumsight, com.wolfcasaba.strumsight). Found:\n'
            '${offences.join('\n')}\n'
            'If the hit is a historical document, add it to '
            '_historicalDocAllowlist with a reason.',
      );
    },
  );

  test('pubspec is the single source of the client version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('name: strumsight'));
    expect(
      RegExp(
        r'^version:\s*\d+\.\d+\.\d+\+\d+$',
        multiLine: true,
      ).hasMatch(pubspec),
      isTrue,
      reason: 'pubspec.yaml must declare a `version: X.Y.Z+build`',
    );

    // The README must point at pubspec instead of restating a version.
    final readme = File('README.md').readAsStringSync();
    expect(
      RegExp(r'\bv\d+\.\d+\.\d+\b').hasMatch(readme),
      isFalse,
      reason: 'README must not restate a client version — link pubspec.yaml',
    );
  });
}
