import 'dart:io';

/// The kinds of outcomes a barrel regeneration or check can produce.
enum PublicBarrelOutcome {
  /// The on-disk barrel matches what the fragments would generate.
  fresh,

  /// The on-disk barrel differs from the fragments — needs regeneration.
  stale,

  /// Two fragments export the same `path`; this is always a bug.
  duplicateExport,
}

/// One generated public.dart barrel for `lib/features/<feature>/`.
///
/// Fragments live in `<feature>/public/*.dart` and are concatenated in
/// **filename order** to form `<feature>/public.dart`. The barrel's header
/// (the doc-comment + `library;` prefix) is preserved from the on-disk barrel
/// when present, and a default header is generated for new barrels. Duplicate
/// `export '...';` paths across fragments are a hard error.
final class PublicBarrel {
  PublicBarrel({required this.projectRoot, required this.feature});

  final Directory projectRoot;
  final String feature;

  Directory get _fragmentsDir =>
      Directory('${projectRoot.absolute.path}/lib/features/$feature/public');

  File get _barrelFile =>
      File('${projectRoot.absolute.path}/lib/features/$feature/public.dart');

  /// Every Dart fragment under `lib/features/<feature>/public/`, in
  /// filename order. The order is the contract: it determines the order of
  /// `export` directives in the rendered barrel.
  List<File> get fragments {
    if (!_fragmentsDir.existsSync()) return const <File>[];
    final files = _fragmentsDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
    files.sort((left, right) => left.path.compareTo(right.path));
    return List.unmodifiable(files);
  }

  /// Renders the full barrel text. Throws [_DuplicateExportError] if two
  /// fragments export the same `path`.
  String render() {
    final buffer = StringBuffer(_header());
    final seenPaths = <String>{};
    for (final fragment in fragments) {
      final content = fragment.readAsStringSync();
      final normalized = _normalizeFragment(content);
      buffer.write(normalized);
      buffer.write('\n');
      for (final exportPath in _exportPaths(content)) {
        if (!seenPaths.add(exportPath)) {
          throw _DuplicateExportError(
            feature: feature,
            fragment: fragment,
            exportPath: exportPath,
          );
        }
      }
    }
    return buffer.toString();
  }

  /// True iff the on-disk barrel exists and equals [render].
  bool isFresh() {
    if (!_barrelFile.existsSync()) return false;
    return _barrelFile.readAsStringSync() == render();
  }

  /// Overwrites the on-disk barrel with [render]. Returns the new contents.
  String write() {
    final rendered = render();
    _barrelFile.writeAsStringSync(rendered);
    return rendered;
  }

  String _header() {
    if (_barrelFile.existsSync()) {
      final text = _barrelFile.readAsStringSync();
      // Lazily match every line up to and including the first `library;`
      // directive. The captured span is then padded with a single blank
      // line so the first fragment can begin on its own line — the standard
      // barrel layout (and the one the existing practice_generator barrel
      // already uses).
      final match = RegExp(r'^(?:.*\n)*?library;\n').firstMatch(text);
      if (match != null) return '${match.group(0)}\n';
    }
    return _defaultHeader();
  }

  String _defaultHeader() {
    final title = _humanTitle(feature);
    return '/// Public domain contract for cross-feature $title consumers.\n'
        'library;\n'
        '\n';
  }
}

String _normalizeFragment(String content) {
  var trimmed = content;
  // Drop leading blank lines so the fragment starts cleanly after the header.
  while (trimmed.startsWith('\n')) {
    trimmed = trimmed.substring(1);
  }
  if (!trimmed.endsWith('\n')) {
    trimmed = '$trimmed\n';
  }
  return trimmed;
}

String _humanTitle(String feature) {
  return feature
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

/// The `path` strings quoted by `export 'path';` directives in [source].
///
/// Skips lines that start with `//` (line comments). Block comments and
/// string-literal contents are not specially masked here because the
/// fragments are short, hand-authored files whose exports always live on
/// their own line — the same convention the original barrel followed.
Iterable<String> _exportPaths(String source) sync* {
  final exportRegex = RegExp(r'''^\s*export\s+r?['"]([^'"]+)['"]''');
  for (final rawLine in source.split('\n')) {
    final trimmed = rawLine.trimLeft();
    if (trimmed.startsWith('//')) continue;
    final match = exportRegex.firstMatch(rawLine);
    if (match != null) yield match.group(1)!;
  }
}

/// Every feature under `lib/features/` that has at least one
/// `lib/features/<feature>/public/*.dart` fragment.
List<String> featuresWithPublicFragments(Directory projectRoot) {
  final featuresDir = Directory('${projectRoot.absolute.path}/lib/features');
  if (!featuresDir.existsSync()) return const <String>[];
  final features = <String>[];
  for (final entity in featuresDir.listSync()) {
    if (entity is! Directory) continue;
    final publicDir = Directory('${entity.path}/public');
    if (!publicDir.existsSync()) continue;
    final hasFragments = publicDir.listSync().whereType<File>().any(
      (file) => file.path.endsWith('.dart'),
    );
    if (hasFragments) {
      features.add(_featureNameFromPath(entity.path));
    }
  }
  features.sort();
  return features;
}

String _featureNameFromPath(String absolutePath) {
  final normalized = absolutePath
      .replaceAll(r'\', '/')
      .replaceAll(RegExp(r'/+$'), '');
  const prefix = 'lib/features/';
  final index = normalized.lastIndexOf(prefix);
  if (index < 0) return normalized;
  return normalized.substring(index + prefix.length);
}

/// Thrown when two fragments in the same feature export the same `path`.
final class _DuplicateExportError implements Exception {
  _DuplicateExportError({
    required this.feature,
    required this.fragment,
    required this.exportPath,
  });

  final String feature;
  final File fragment;
  final String exportPath;

  @override
  String toString() =>
      'Duplicate export "$exportPath" in $feature: '
      'also defined in ${fragment.path}';
}

/// Run the generator against every feature with a `public/` fragment
/// directory (or the explicit [features] list).
///
/// Mode:
///   --check   Only verify; exit 1 if any barrel is stale. (default)
///   --write   Regenerate every targeted barrel in place.
///   --quiet   Suppress per-feature success output (errors still print).
int runGenerator({
  required Directory projectRoot,
  List<String> features = const <String>[],
  required bool check,
  required bool write,
  required bool quiet,
}) {
  final targets = features.isNotEmpty
      ? features
      : featuresWithPublicFragments(projectRoot);
  if (targets.isEmpty) {
    if (!quiet) stdout.writeln('No public/ fragment directories found.');
    return 0;
  }

  final failures = <String>[];
  final duplicates = <String>[];
  var staleCount = 0;
  var writtenCount = 0;

  for (final feature in targets) {
    final barrel = PublicBarrel(projectRoot: projectRoot, feature: feature);
    try {
      if (write) {
        barrel.write();
        writtenCount++;
        continue;
      }
      if (!barrel.isFresh()) {
        staleCount++;
        failures.add(feature);
        stderr.writeln(
          '$feature: barrel is out of date '
          '(regenerate with --write).',
        );
      } else if (!quiet) {
        stdout.writeln('$feature: up to date');
      }
    } on _DuplicateExportError catch (error) {
      duplicates.add(error.toString());
      stderr.writeln(error.toString());
    } on FileSystemException catch (error) {
      failures.add(feature);
      stderr.writeln('$feature: ${error.message}');
    }
  }

  if (duplicates.isNotEmpty) return 2;
  if (write) {
    if (!quiet) stdout.writeln('Wrote $writtenCount barrel(s).');
    return 0;
  }
  if (staleCount > 0) {
    stderr.writeln('$staleCount barrel(s) out of date.');
    return 1;
  }
  if (!quiet) {
    stdout.writeln('All ${targets.length} barrel(s) up to date.');
  }
  return 0;
}

void main(List<String> arguments) {
  var check = false;
  var write = false;
  var quiet = false;
  final features = <String>[];

  for (final argument in arguments) {
    switch (argument) {
      case '--check':
        check = true;
      case '--write':
        write = true;
      case '--quiet':
        quiet = true;
      case '--help':
      case '-h':
        stdout.writeln(
          'Usage: dart run tool/gen_public_barrel.dart '
          '[--check] [--write] [--quiet] [feature ...]\n'
          '\n'
          'Modes (pick at most one of --check / --write):\n'
          '  --check   Verify the on-disk barrel is fresh. Exit 1 if stale.\n'
          '  --write   Regenerate every targeted barrel in place.\n'
          '\n'
          'Without --check or --write, defaults to --check (CI-safe).',
        );
        return;
      default:
        if (argument.startsWith('-')) {
          stderr.writeln('Unknown flag: $argument');
          exitCode = 64;
          return;
        }
        features.add(argument);
    }
  }

  if (check && write) {
    stderr.writeln('--check and --write are mutually exclusive.');
    exitCode = 64;
    return;
  }

  // Default to --check (CI-safe) when neither flag is given: an implementer
  // who forgets --write will get a loud failure instead of a silent write.
  if (!check && !write) check = true;

  exitCode = runGenerator(
    projectRoot: Directory.current,
    features: features,
    check: check,
    write: write,
    quiet: quiet,
  );
}
