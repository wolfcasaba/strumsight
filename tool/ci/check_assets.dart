import 'dart:io';

/// The kinds of asset declaration failures enforced by the CI gate.
enum AssetIssueKind { missing, emptyMlBinary }

/// One invalid path declared by `flutter.assets` or `flutter.fonts`.
final class AssetIssue {
  const AssetIssue({required this.path, required this.kind});

  final String path;
  final AssetIssueKind kind;
}

/// Complete result of checking the assets declared in a project's pubspec.
final class AssetCheckReport {
  AssetCheckReport({
    required List<String> declaredPaths,
    required List<AssetIssue> issues,
  }) : declaredPaths = List.unmodifiable(declaredPaths),
       issues = List.unmodifiable(issues);

  final List<String> declaredPaths;
  final List<AssetIssue> issues;

  bool get isClean => issues.isEmpty;

  /// Human-readable CLI output containing no asset contents.
  String format() {
    if (isClean) {
      final mlBinaryCount = declaredPaths.where(_isMlBinary).length;
      return 'Asset check OK '
          '(${declaredPaths.length} declared asset(s), '
          '$mlBinaryCount non-empty ML binary/binaries).';
    }

    final output = StringBuffer('Asset check failed.');
    for (final issue in issues) {
      final description = switch (issue.kind) {
        AssetIssueKind.missing => 'declared asset does not exist',
        AssetIssueKind.emptyMlBinary => 'declared ML binary is empty',
      };
      output
        ..writeln()
        ..write('- ${issue.path}: $description');
    }
    return output.toString();
  }
}

/// Checks only paths declared below `flutter.assets` and `flutter.fonts`.
///
/// Other repository files are intentionally outside the traversal set.
AssetCheckReport checkAssets({required Directory projectRoot}) {
  final pubspec = File('${projectRoot.absolute.path}/pubspec.yaml');
  final declaredPaths = _declaredAssetPaths(pubspec.readAsStringSync()).toList()
    ..sort();
  final issues = <AssetIssue>[];

  for (final path in declaredPaths) {
    final absolutePath = '${projectRoot.absolute.path}/$path';
    final entityType = FileSystemEntity.typeSync(absolutePath);
    if (entityType == FileSystemEntityType.notFound) {
      issues.add(AssetIssue(path: path, kind: AssetIssueKind.missing));
      continue;
    }
    if (_isMlBinary(path) &&
        (entityType != FileSystemEntityType.file ||
            File(absolutePath).lengthSync() == 0)) {
      issues.add(AssetIssue(path: path, kind: AssetIssueKind.emptyMlBinary));
    }
  }

  return AssetCheckReport(declaredPaths: declaredPaths, issues: issues);
}

Iterable<String> _declaredAssetPaths(String pubspec) sync* {
  final paths = <String>{};
  var inFlutter = false;
  var flutterIndent = -1;
  int? assetsIndent;
  int? fontsIndent;

  for (final rawLine in pubspec.split('\n')) {
    final line = _withoutYamlComment(rawLine);
    if (line.trim().isEmpty) continue;

    final indent = _leadingSpaceCount(line);
    final trimmed = line.trim();
    if (!inFlutter) {
      if (indent == 0 && trimmed == 'flutter:') {
        inFlutter = true;
        flutterIndent = indent;
      }
      continue;
    }
    if (indent <= flutterIndent) break;

    if (assetsIndent != null) {
      if (indent > assetsIndent) {
        if (trimmed.startsWith('- ')) {
          paths.add(_yamlScalar(trimmed.substring(2)));
        }
        continue;
      }
      assetsIndent = null;
    }

    if (fontsIndent != null) {
      if (indent > fontsIndent) {
        final match = RegExp(r'^-\s+asset\s*:\s*(.+)$').firstMatch(trimmed);
        if (match != null) {
          paths.add(_yamlScalar(match.group(1)!));
        }
        continue;
      }
      fontsIndent = null;
    }

    if (trimmed == 'assets:') {
      assetsIndent = indent;
    } else if (trimmed == 'fonts:') {
      fontsIndent = indent;
    }
  }

  yield* paths;
}

String _withoutYamlComment(String line) {
  var inSingleQuotes = false;
  var inDoubleQuotes = false;
  var escaped = false;

  for (var index = 0; index < line.length; index++) {
    final character = line[index];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (character == r'\' && inDoubleQuotes) {
      escaped = true;
      continue;
    }
    if (character == "'" && !inDoubleQuotes) {
      inSingleQuotes = !inSingleQuotes;
      continue;
    }
    if (character == '"' && !inSingleQuotes) {
      inDoubleQuotes = !inDoubleQuotes;
      continue;
    }
    if (character == '#' && !inSingleQuotes && !inDoubleQuotes) {
      return line.substring(0, index);
    }
  }
  return line;
}

String _yamlScalar(String value) {
  final scalar = value.trim();
  if (scalar.length >= 2 && scalar.startsWith("'") && scalar.endsWith("'")) {
    return scalar.substring(1, scalar.length - 1).replaceAll("''", "'");
  }
  if (scalar.length >= 2 && scalar.startsWith('"') && scalar.endsWith('"')) {
    return scalar.substring(1, scalar.length - 1);
  }
  return scalar;
}

int _leadingSpaceCount(String line) {
  var count = 0;
  while (count < line.length && line.codeUnitAt(count) == 0x20) {
    count++;
  }
  return count;
}

bool _isMlBinary(String path) =>
    path.startsWith('assets/ml/') && path.endsWith('.bin');

void main(List<String> arguments) {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/ci/check_assets.dart');
    exitCode = 64;
    return;
  }

  try {
    final report = checkAssets(projectRoot: Directory.current);
    if (report.isClean) {
      stdout.writeln(report.format());
      return;
    }
    stderr.writeln(report.format());
    exitCode = 1;
  } on Object catch (error, stackTrace) {
    stderr.writeln('Asset check could not run: $error');
    stderr.writeln(stackTrace);
    exitCode = 2;
  }
}
