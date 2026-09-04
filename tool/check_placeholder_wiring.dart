import 'dart:convert';
import 'dart:io';

import 'check_screen_reachability.dart';

/// One `(file, declaration-name, reason)` entry that suppresses a single
/// measured finding (round brief §5.3). `declarationName` identifies WHICH
/// finding it covers: for P2/P3 it is the top-level `final`/`const`
/// identifier; for P1 it is `ClassName.argName`. An entry only suppresses
/// when [reason] is non-empty — an empty-reason entry is itself a finding
/// (A7: the exception list must never become a silent escape hatch).
final class PlaceholderException {
  const PlaceholderException({
    required this.file,
    required this.declarationName,
    required this.reason,
  });

  final String file;
  final String declarationName;
  final String reason;
}

/// The round's own, kept-deliberately-short exception list (§5.3). The ONLY
/// entry on the tree today covers `progressV2IsOffline`
/// (`lib/features/progress_v2/application/progress_providers.dart`) — its
/// own doc-comment already states it is a measured constant (Progress V2 is
/// 100% local, §5.7), not a placeholder standing in for a missing
/// sync-status source. `lib/**` is this round's forbidden zone, so the
/// source itself cannot carry a different marker — this entry is the only
/// way to make the P3 finding non-vacuous (A7 requires it to stay real: a
/// second entry added "just to go green" without a genuinely new source
/// justification would be exactly the vacuum-cell failure this round exists
/// to catch).
const List<PlaceholderException> placeholderExceptions = [
  PlaceholderException(
    file: 'lib/features/progress_v2/application/progress_providers.dart',
    declarationName: 'progressV2IsOffline',
    reason:
        "Progress V2 is 100% local (own doc-comment, §5.7): the dashboard "
        'reads only the local practice-history repository and never syncs '
        'with an account layer, so a "not yet synced" state cannot occur '
        'here. Measured, not a placeholder standing in for a missing '
        'sync-status source.',
  ),
];

/// A single placeholder-wiring finding (round brief §5.3 P1/P2/P3).
final class PlaceholderFinding {
  const PlaceholderFinding({
    required this.rule,
    required this.file,
    required this.line,
    required this.declarationName,
    required this.detail,
  });

  /// `P1`, `P2`, `P3`, or `EXC` (a vacuous exception-list entry).
  final String rule;
  final String file;
  final int line;
  final String declarationName;
  final String detail;

  String get location => '$file:$line';

  Map<String, Object?> toJson() => {
    'rule': rule,
    'file': file,
    'line': line,
    'declarationName': declarationName,
    'detail': detail,
  };
}

/// Low-level scan over one file's raw source: brackets are depth-tracked
/// while STRING LITERALS and `//` comments are skipped whole, so a comma or
/// bracket inside either never confuses argument/declaration extraction.
/// Deliberately not a real Dart parser (matches this tool family's existing
/// discipline — `check_screen_reachability.dart`'s indentation-based flag
/// scopes are the same kind of bounded heuristic over `dart format`-clean
/// source, not a grammar).
final class _CodeScanner {
  const _CodeScanner(this.source);

  final String source;

  static const _opens = '([{';
  static const _closes = ')]}';
  static const _matchingClose = {'(': ')', '[': ']', '{': '}'};

  /// The index just past the string/comment starting at [i], or [i] itself
  /// if nothing special starts there.
  int _skipNonCode(int i) {
    final ch = source[i];
    if (ch == "'" || ch == '"') {
      var j = i + 1;
      while (j < source.length) {
        if (source[j] == r'\') {
          j += 2;
          continue;
        }
        if (source[j] == ch) return j + 1;
        j++;
      }
      return j;
    }
    if (ch == '/' && i + 1 < source.length && source[i + 1] == '/') {
      var j = i;
      while (j < source.length && source[j] != '\n') {
        j++;
      }
      return j;
    }
    return -1;
  }

  /// The index of the bracket that matches the open bracket at [openIndex].
  int matchingClose(int openIndex) {
    final open = source[openIndex];
    final close = _matchingClose[open]!;
    var depth = 0;
    var i = openIndex;
    while (i < source.length) {
      final skip = _skipNonCode(i);
      if (skip != -1) {
        i = skip;
        continue;
      }
      final ch = source[i];
      if (ch == open) depth++;
      if (ch == close) {
        depth--;
        if (depth == 0) return i;
      }
      i++;
    }
    throw StateError('unbalanced "$open" starting at offset $openIndex');
  }

  /// Splits the text strictly between [openIndex] and [closeIndex]
  /// (exclusive of both bracket characters) into top-level (depth-0),
  /// comma-separated segments.
  List<String> splitTopLevel(int openIndex, int closeIndex) {
    final segments = <String>[];
    var depth = 0;
    var segStart = openIndex + 1;
    var i = segStart;
    while (i < closeIndex) {
      final skip = _skipNonCode(i);
      if (skip != -1) {
        i = skip < closeIndex ? skip : closeIndex;
        continue;
      }
      final ch = source[i];
      if (_opens.contains(ch)) depth++;
      if (_closes.contains(ch)) depth--;
      if (ch == ',' && depth == 0) {
        segments.add(source.substring(segStart, i));
        segStart = i + 1;
      }
      i++;
    }
    if (segStart < closeIndex) {
      segments.add(source.substring(segStart, closeIndex));
    }
    return segments;
  }

  /// The index of the first top-level `;` at or after [start] (depth
  /// relative to [start] returning to 0), i.e. the end of one statement.
  int topLevelSemicolon(int start) {
    var depth = 0;
    var i = start;
    while (i < source.length) {
      final skip = _skipNonCode(i);
      if (skip != -1) {
        i = skip;
        continue;
      }
      final ch = source[i];
      if (_opens.contains(ch)) depth++;
      if (_closes.contains(ch)) depth--;
      if (ch == ';' && depth <= 0) return i;
      i++;
    }
    throw StateError('no top-level ";" found starting at offset $start');
  }

  int lineOf(int offset) =>
      '\n'.allMatches(source.substring(0, offset)).length + 1;
}

/// The closed placeholder-literal set (round brief §5.3). `includeBool`
/// widens it with `true`/`false` — used ONLY for P3 (bare top-level
/// const/final values), matching the round's own measured baseline
/// (§0.0.1/R3: the P3 grep alternation explicitly adds `|false`, while the
/// P1/P2 greps do not). A boolean default is routinely a real, meaningful
/// value for a named constructor argument or a provider's computed result —
/// widening P1/P2 the same way would make the rule noisy without adding a
/// signal the round asked for.
RegExp _exactPlaceholder({required bool includeBool}) {
  final alternatives = <String>[
    r'0\.0',
    r'0',
    r"''",
    r'""',
    r'\[\]',
    r'\{\}',
    r'null',
    r'const\s*\[\]',
    r'const\s*\{\}',
    r'const\s*<[^>]*>\s*\[\]',
    r'const\s*<[^,>]*,\s*[^>]*>\s*\{\}',
    if (includeBool) ...['true', 'false'],
  ];
  return RegExp('^(?:${alternatives.join('|')})\$');
}

final RegExp _namedArgPattern = RegExp(r'^\s*([A-Za-z_]\w*)\s*:\s*([\s\S]*)$');

final RegExp _topLevelDeclStart = RegExp(
  r'^(final|const)\s+(?:[A-Za-z_]\w*(?:<[^;]*?>)?\s+)?([A-Za-z_]\w*)\s*=',
  multiLine: true,
);

final RegExp _providerCallStart = RegExp(r'\w*Provider\w*(?:<[^;]*?>)?\s*\(');

final RegExp _arrowBuilderExact = RegExp(
  r'^\(\s*(?:ref|_)\s*,?\s*\)\s*(?:async\s*)?=>\s*([\s\S]*?)\s*$',
);

/// Strips a trailing line comment and trailing comma from an extracted
/// argument/value segment, then trims whitespace — the shape every
/// extracted candidate needs before an exact-literal comparison.
String _cleanCandidate(String raw) {
  var text = raw;
  final commentIndex = text.indexOf('//');
  if (commentIndex != -1) text = text.substring(0, commentIndex);
  text = text.trim();
  if (text.endsWith(',')) text = text.substring(0, text.length - 1).trim();
  return text;
}

/// Measures whether the routing layer (H1) and the composition/provider
/// layer (H2) feed a screen or a provider a placeholder literal instead of
/// a real source (round brief §5.3, ADR 0312-driven E16-R05).
///
/// **Mért fájlhalmaz** (not parameterizable by the caller — kimondva a
/// mérőben, §5.3):
/// - H1 — `lib/app/routing/*.dart`.
/// - H2 — `lib/features/*/application/*providers*.dart` and
///   `lib/features/*/providers/*providers*.dart`.
///
/// Fail-closed on an empty measured file set (A8): an empty glob is a
/// measurement error, never a vacuously green result (L606).
final class PlaceholderWiring {
  PlaceholderWiring(this.repository);

  final Directory repository;

  List<String> get h1Files {
    final dir = Directory(
      '${repository.path}${Platform.pathSeparator}lib${Platform.pathSeparator}app${Platform.pathSeparator}routing',
    );
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .map((f) => _relativePath(f.path))
        .where((p) => p.endsWith('.dart'))
        .toList()
      ..sort();
  }

  List<String> get h2Files {
    final featuresDir = Directory(
      '${repository.path}${Platform.pathSeparator}lib${Platform.pathSeparator}features',
    );
    if (!featuresDir.existsSync()) return const [];
    final matches = <String>[];
    for (final featureEntry in featuresDir.listSync().whereType<Directory>()) {
      for (final sub in const ['application', 'providers']) {
        final subDir = Directory(
          '${featureEntry.path}${Platform.pathSeparator}$sub',
        );
        if (!subDir.existsSync()) continue;
        for (final file in subDir.listSync().whereType<File>()) {
          final relative = _relativePath(file.path);
          final basename = relative.split('/').last;
          if (basename.endsWith('.dart') && basename.contains('providers')) {
            matches.add(relative);
          }
        }
      }
    }
    matches.sort();
    return matches;
  }

  PlaceholderWiringResult render() {
    final h1 = h1Files;
    final h2 = h2Files;
    final findings = <PlaceholderFinding>[];
    final suppressed = <PlaceholderFinding>[];
    final vacuousExceptions = <PlaceholderException>[];

    if (h1.isEmpty || h2.isEmpty) {
      return PlaceholderWiringResult._(
        h1Files: h1,
        h2Files: h2,
        findings: const [],
        suppressedFindings: const [],
        vacuousExceptions: const [],
        fileSetEmpty: true,
      );
    }

    final screenClassNames = ScreenReachability(
      repository,
    ).render().verdicts.map((v) => v.className).toSet();

    for (final entry in placeholderExceptions) {
      if (entry.reason.trim().isEmpty) vacuousExceptions.add(entry);
    }

    for (final file in h1) {
      findings.addAll(
        _scanP1(file, screenClassNames).map((f) => f).where((f) {
          if (_isExcepted(f)) {
            suppressed.add(f);
            return false;
          }
          return true;
        }),
      );
    }

    for (final file in h2) {
      final p2 = _scanP2(file);
      final p3 = _scanP3(file);
      for (final f in [...p2, ...p3]) {
        if (_isExcepted(f)) {
          suppressed.add(f);
        } else {
          findings.add(f);
        }
      }
    }

    return PlaceholderWiringResult._(
      h1Files: h1,
      h2Files: h2,
      findings: List.unmodifiable(findings),
      suppressedFindings: List.unmodifiable(suppressed),
      vacuousExceptions: List.unmodifiable(vacuousExceptions),
      fileSetEmpty: false,
    );
  }

  bool _isExcepted(PlaceholderFinding finding) => placeholderExceptions.any(
    (e) =>
        e.file == finding.file &&
        e.declarationName == finding.declarationName &&
        e.reason.trim().isNotEmpty,
  );

  /// P1 — a screen-class constructor call in an H1 file whose named
  /// argument value is exactly a placeholder literal.
  List<PlaceholderFinding> _scanP1(String file, Set<String> screenClassNames) {
    final source = _read(file);
    final scanner = _CodeScanner(source);
    final findings = <PlaceholderFinding>[];
    final exact = _exactPlaceholder(includeBool: false);
    final callSite = RegExp(r'\b([A-Za-z0-9_]*Screen)\s*\(');

    for (final match in callSite.allMatches(source)) {
      final className = match.group(1)!;
      if (!screenClassNames.contains(className)) continue;
      final openIndex = match.end - 1;
      final int closeIndex;
      try {
        closeIndex = scanner.matchingClose(openIndex);
      } on StateError {
        continue;
      }
      for (final segment in scanner.splitTopLevel(openIndex, closeIndex)) {
        final argMatch = _namedArgPattern.firstMatch(segment);
        if (argMatch == null) continue;
        final argName = argMatch.group(1)!;
        final candidate = _cleanCandidate(argMatch.group(2)!);
        if (!exact.hasMatch(candidate)) continue;
        findings.add(
          PlaceholderFinding(
            rule: 'P1',
            file: file,
            line: scanner.lineOf(match.start),
            declarationName: '$className.$argName',
            detail:
                '$className\'s "$argName" argument is the placeholder '
                'literal "$candidate"',
          ),
        );
      }
    }
    return findings;
  }

  /// P2 — a top-level provider declaration whose ENTIRE builder body is a
  /// bare placeholder literal: `SomeProvider<T>((ref) => <literal>)` (or
  /// `(_)`), nothing else in the call.
  List<PlaceholderFinding> _scanP2(String file) {
    final source = _read(file);
    final scanner = _CodeScanner(source);
    final findings = <PlaceholderFinding>[];
    final exact = _exactPlaceholder(includeBool: false);

    for (final declMatch in _topLevelDeclStart.allMatches(source)) {
      final declarationName = declMatch.group(2)!;
      final rhsStart = declMatch.end;
      final providerMatch = _providerCallStart.matchAsPrefix(
        source,
        _skipWhitespace(source, rhsStart),
      );
      if (providerMatch == null) continue;
      final openIndex = providerMatch.end - 1;
      final int closeIndex;
      try {
        closeIndex = scanner.matchingClose(openIndex);
      } on StateError {
        continue;
      }
      final callBody = source
          .substring(openIndex + 1, closeIndex)
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final arrowMatch = _arrowBuilderExact.firstMatch(callBody);
      if (arrowMatch == null) continue;
      final candidate = _cleanCandidate(arrowMatch.group(1)!);
      if (!exact.hasMatch(candidate)) continue;
      findings.add(
        PlaceholderFinding(
          rule: 'P2',
          file: file,
          line: scanner.lineOf(declMatch.start),
          declarationName: declarationName,
          detail:
              'top-level provider "$declarationName" resolves to the bare '
              'placeholder literal "$candidate"',
        ),
      );
    }
    return findings;
  }

  /// P3 — a top-level `const`/`final` declaration whose ENTIRE value
  /// expression (up to the terminating `;`) is exactly a placeholder
  /// literal — the boolean-widened variant (§0.0.1/R3).
  List<PlaceholderFinding> _scanP3(String file) {
    final source = _read(file);
    final scanner = _CodeScanner(source);
    final findings = <PlaceholderFinding>[];
    final exact = _exactPlaceholder(includeBool: true);

    for (final declMatch in _topLevelDeclStart.allMatches(source)) {
      final declarationName = declMatch.group(2)!;
      final rhsStart = declMatch.end;
      final int semicolonIndex;
      try {
        semicolonIndex = scanner.topLevelSemicolon(rhsStart);
      } on StateError {
        continue;
      }
      final candidate = _cleanCandidate(
        source.substring(rhsStart, semicolonIndex),
      );
      if (!exact.hasMatch(candidate)) continue;
      findings.add(
        PlaceholderFinding(
          rule: 'P3',
          file: file,
          line: scanner.lineOf(declMatch.start),
          declarationName: declarationName,
          detail:
              'top-level "$declarationName" is the bare placeholder '
              'literal "$candidate"',
        ),
      );
    }
    return findings;
  }

  int _skipWhitespace(String source, int start) {
    var i = start;
    while (i < source.length && source[i].trim().isEmpty) {
      i++;
    }
    return i;
  }

  String _read(String relativePath) => File(
    '${repository.path}${Platform.pathSeparator}$relativePath',
  ).readAsStringSync();

  String _relativePath(String absolutePath) {
    final normalizedRoot = repository.absolute.path;
    final normalizedPath = File(absolutePath).absolute.path;
    final prefix = '$normalizedRoot${Platform.pathSeparator}';
    if (!normalizedPath.startsWith(prefix)) {
      throw ArgumentError.value(
        absolutePath,
        'absolutePath',
        'outside repository',
      );
    }
    return normalizedPath.substring(prefix.length).replaceAll('\\', '/');
  }
}

/// Immutable render() result. [exitCode] is `0` only when there are zero
/// unsuppressed findings, zero vacuous exceptions, AND neither measured file
/// set is empty (A8 fail-closed rule).
final class PlaceholderWiringResult {
  const PlaceholderWiringResult._({
    required this.h1Files,
    required this.h2Files,
    required this.findings,
    required this.suppressedFindings,
    required this.vacuousExceptions,
    required this.fileSetEmpty,
  });

  final List<String> h1Files;
  final List<String> h2Files;
  final List<PlaceholderFinding> findings;
  final List<PlaceholderFinding> suppressedFindings;
  final List<PlaceholderException> vacuousExceptions;

  /// `true` when H1 or H2's glob matched zero files — the fail-closed case
  /// (§5.3, A8): never treated as a clean zero-findings run.
  final bool fileSetEmpty;

  int get exitCode =>
      (fileSetEmpty || findings.isNotEmpty || vacuousExceptions.isNotEmpty)
      ? 1
      : 0;

  Map<String, Object?> toJson() => {
    'h1Files': h1Files,
    'h2Files': h2Files,
    'fileSetEmpty': fileSetEmpty,
    'findings': [for (final f in findings) f.toJson()],
    'suppressedFindings': [for (final f in suppressedFindings) f.toJson()],
    'vacuousExceptions': [
      for (final e in vacuousExceptions)
        {
          'file': e.file,
          'declarationName': e.declarationName,
          'reason': e.reason,
        },
    ],
    'exitCode': exitCode,
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  String toMarkdownTable() {
    final buffer = StringBuffer()
      ..writeln('# Placeholder wiring (measured)')
      ..writeln()
      ..writeln(
        'H1 (routing) files: ${h1Files.length}. H2 (composition provider) '
        'files: ${h2Files.length}. Findings: ${findings.length}. '
        'Suppressed by exception: ${suppressedFindings.length}. '
        'Vacuous exceptions: ${vacuousExceptions.length}. '
        'Exit code: $exitCode.',
      )
      ..writeln();
    if (fileSetEmpty) {
      buffer.writeln(
        '**FAIL-CLOSED**: H1 or H2 matched zero files — this is a '
        'measurement error, not a clean run.',
      );
      return buffer.toString();
    }
    buffer
      ..writeln('| Rule | Location | Declaration | Detail |')
      ..writeln('| --- | --- | --- | --- |');
    for (final f in findings) {
      buffer.writeln(
        '| ${f.rule} | `${f.location}` | `${f.declarationName}` | ${f.detail} |',
      );
    }
    if (vacuousExceptions.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## Vacuous exception-list entries (empty reason)')
        ..writeln()
        ..writeln('| File | Declaration |')
        ..writeln('| --- | --- |');
      for (final e in vacuousExceptions) {
        buffer.writeln('| `${e.file}` | `${e.declarationName}` |');
      }
    }
    buffer
      ..writeln()
      ..writeln('## Suppressed by a real exception-list entry')
      ..writeln()
      ..writeln('| Rule | Location | Declaration | Reason |')
      ..writeln('| --- | --- | --- | --- |');
    for (final f in suppressedFindings) {
      final reason = placeholderExceptions
          .firstWhere(
            (e) => e.file == f.file && e.declarationName == f.declarationName,
          )
          .reason;
      buffer.writeln(
        '| ${f.rule} | `${f.location}` | `${f.declarationName}` | $reason |',
      );
    }
    return buffer.toString();
  }
}

void main(List<String> arguments) {
  var format = 'table';
  var repoPath = Directory.current.path;
  for (var i = 0; i < arguments.length; i++) {
    final arg = arguments[i];
    if (arg == '--format' && i + 1 < arguments.length) {
      format = arguments[i + 1];
      i++;
    } else if (arg.startsWith('--format=')) {
      format = arg.substring('--format='.length);
    } else if (!arg.startsWith('--')) {
      repoPath = arg;
    }
  }

  final result = PlaceholderWiring(Directory(repoPath)).render();
  if (format == 'json') {
    stdout.writeln(result.toJsonString());
  } else {
    stdout.write(result.toMarkdownTable());
  }
  exit(result.exitCode);
}
