import 'dart:convert';
import 'dart:io';

import 'ui_inventory.dart';

/// A source location that produced part of a [ScreenVerdict].
final class SourceRef {
  const SourceRef(this.path, this.line);

  final String path;
  final int line;

  String get location => '$path:$line';

  Map<String, Object?> toJson() => {'path': path, 'line': line};

  @override
  String toString() => location;
}

/// One declarative (router-side) reference to a screen's class, together
/// with the feature-flag conditions that gate THAT specific registration
/// (ADR 0471 D4). A screen can be registered more than once under
/// unrelated gates (e.g. once in a legacy `!adaptiveShellEnabled` branch and
/// once in the adaptive shell), so the flags are attached per reference —
/// flattening them into one screen-level list would wrongly read as a
/// single joint condition.
final class DeclarativeReference {
  const DeclarativeReference(this.source, this.flagConditions);

  final SourceRef source;
  final List<String> flagConditions;

  bool get isFlagGated => flagConditions.isNotEmpty;

  Map<String, Object?> toJson() => {
    ...source.toJson(),
    'flagConditions': flagConditions,
  };
}

/// The measured reachability verdict for one `*_screen.dart` source.
///
/// Reachability has two independent channels (ADR 0471 D2): a screen is
/// reachable if the router NAMES its class (declarative) OR anything else
/// under `lib/` CONSTRUCTS its class (imperative). Both channels match by
/// class name, never by import path or file name (ADR 0471 D3) — the router
/// reaches some features only through a `public.dart` barrel, and a
/// path-based match would under-report those as unreachable.
final class ScreenVerdict {
  const ScreenVerdict({
    required this.screenPath,
    required this.className,
    required this.declaredAt,
    required this.declarativeReferences,
    required this.imperativeReferences,
    required this.testReferences,
  });

  final String screenPath;
  final String className;
  final SourceRef declaredAt;
  final List<DeclarativeReference> declarativeReferences;
  final List<SourceRef> imperativeReferences;
  final List<SourceRef> testReferences;

  bool get isDeclarativelyReachable => declarativeReferences.isNotEmpty;

  bool get isImperativelyReachable => imperativeReferences.isNotEmpty;

  bool get isReachable => isDeclarativelyReachable || isImperativelyReachable;

  bool get isTestCovered => testReferences.isNotEmpty;

  /// Every declarative registration is behind a flag AND there is no
  /// unconditional imperative construction either — i.e. reaching this
  /// screen today requires at least one flag to be on. Reported as a
  /// dimension (ADR 0471 D4), not folded into [isReachable]: a flag-gated
  /// route is reachable code with a closed door, not dead code.
  bool get isFlagGated =>
      isDeclarativelyReachable &&
      declarativeReferences.every((r) => r.isFlagGated) &&
      !isImperativelyReachable;

  /// Union of every flag condition seen across all declarative references,
  /// for a quick at-a-glance summary. This is a UNION, not a conjunction —
  /// two entries here may gate two DIFFERENT registrations of this screen
  /// (see [declarativeReferences] for the per-registration detail).
  List<String> get flagConditions =>
      {for (final r in declarativeReferences) ...r.flagConditions}.toList()
        ..sort();

  /// The first known source reference for this screen — used as the
  /// evidence citation when a human-readable table needs exactly one
  /// location per row. Falls back to the class declaration site when the
  /// screen has no measured reference at all, so every one of the 97
  /// verdicts still carries a source location (ADR 0471 D1).
  SourceRef get primaryReference {
    if (declarativeReferences.isNotEmpty) {
      return declarativeReferences.first.source;
    }
    if (imperativeReferences.isNotEmpty) return imperativeReferences.first;
    return declaredAt;
  }

  Map<String, Object?> toJson() => {
    'screenPath': screenPath,
    'className': className,
    'declaredAt': declaredAt.toJson(),
    'reachable': isReachable,
    'declarative': {
      'reachable': isDeclarativelyReachable,
      'references': [for (final r in declarativeReferences) r.toJson()],
    },
    'imperative': {
      'reachable': isImperativelyReachable,
      'references': [for (final r in imperativeReferences) r.toJson()],
    },
    'tests': {
      'covered': isTestCovered,
      'references': [for (final r in testReferences) r.toJson()],
    },
    'flagGated': isFlagGated,
    'flagConditions': flagConditions,
    'primaryReference': primaryReference.toJson(),
  };
}

/// Immutable, sorted collection of every measured [ScreenVerdict].
final class ScreenReachabilityResult {
  ScreenReachabilityResult._(this.verdicts);

  final List<ScreenVerdict> verdicts;

  int get reachableCount => verdicts.where((v) => v.isReachable).length;

  int get unreachableCount => verdicts.length - reachableCount;

  int get flagGatedCount => verdicts.where((v) => v.isFlagGated).length;

  Map<String, Object?> toJson() => {
    'measuredScreenCount': verdicts.length,
    'reachableCount': reachableCount,
    'unreachableCount': unreachableCount,
    'flagGatedCount': flagGatedCount,
    'screens': [for (final v in verdicts) v.toJson()],
  };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  String toMarkdownTable() {
    final buffer = StringBuffer()
      ..writeln('# Screen reachability (measured)')
      ..writeln()
      ..writeln(
        'Measured screens: ${verdicts.length}. Reachable: $reachableCount. '
        'Unreachable: $unreachableCount. Flag-gated: $flagGatedCount.',
      )
      ..writeln()
      ..writeln(
        '| Screen | Class | Declarative | Imperative | Tests | Flag gate | Source |',
      )
      ..writeln('| --- | --- | --- | --- | --- | --- | --- |');
    for (final v in verdicts) {
      final declarative = v.isDeclarativelyReachable
          ? v.declarativeReferences.map((r) => r.source.location).join('; ')
          : '—';
      final imperative = v.isImperativelyReachable
          ? v.imperativeReferences.map((r) => r.location).join('; ')
          : '—';
      final tests = v.isTestCovered ? '${v.testReferences.length}' : '0';
      // Only a genuine closed-door gate (every path in requires a flag) is
      // shown here — a screen that ALSO has an unconditional reference is
      // not usefully summarised as "gated" even though one of its several
      // registrations happens to sit behind a flag (see the JSON output's
      // per-reference `flagConditions` for that detail).
      final flags = v.isFlagGated ? v.flagConditions.join(' | ') : '—';
      buffer.writeln(
        '| `${v.screenPath}` | `${v.className}` | $declarative | $imperative | '
        '$tests | $flags | ${v.primaryReference.location} |',
      );
    }
    return buffer.toString();
  }
}

/// Measures, for every production `*_screen.dart` source under
/// `lib/features/`, whether the user can actually reach it (ADR 0471 D1).
///
/// Follows the `tool/ui_inventory.dart` shape: a class over a repository
/// [Directory] plus a `render()` call, so a test can instantiate it
/// directly instead of shelling out.
///
/// **Static-analysis limit (ADR 0471 D7):** this tool only sees text —
/// direct construction (`ClassName(`), named-constructor construction
/// (`ClassName.named(`), and class-name mentions in source. It cannot see
/// reflective or data-driven navigation (a class looked up by a runtime
/// string key, a plugin registry, and similar). An `unreachable` verdict is
/// therefore a proposal for human/round review, never an automatic
/// authorisation to delete anything (ADR 0471 D5).
final class ScreenReachability {
  ScreenReachability(this.repository);

  final Directory repository;

  /// The declarative surface (ADR 0471 D2/1): a screen named here — by
  /// class name, not import path (D3) — counts as reachable regardless of
  /// whether the surrounding registration is behind a feature flag (D4).
  static const List<String> routingSources = [
    'lib/app/routing/app_router.dart',
    'lib/app/routing/adaptive_shell_routes.dart',
    'lib/app/routing/route_guards.dart',
  ];

  /// A screen class declaration. The `(?:V\d+)?` tail is measured, not
  /// cosmetic: `SetlistListScreenV2` was invisible to every channel of
  /// this tool because `Screen\b` cannot match a name that continues
  /// with `V2` — its references counted as zero everywhere.
  static final RegExp _classDeclaration = RegExp(
    r'class\s+([A-Za-z0-9_]*Screen(?:V\d+)?)\b',
  );

  /// A single-line `if (...)` condition that mentions a flag identifier.
  /// Every rollout flag in this codebase is named `somethingEnabled`
  /// (`practiceEnabled`, `visionSetupEnabled`, `adaptiveShellEnabled`, …),
  /// so requiring the literal substring `Enabled` distinguishes a route
  /// rollout gate from unrelated `if` statements (redirect logic, type
  /// checks) without needing a full Dart parser.
  static final RegExp _flagIf = RegExp(r'if\s*\(([^()]*Enabled[^()]*)\)');

  ScreenReachabilityResult render() {
    final screenPaths = UiInventory(repository).render().screenPaths;

    // Comment lines are stripped (kept as blank lines so every line NUMBER
    // stays truthful). MÉRT hiba (2026-09-06 review, MAJOR-4b): a router
    // egy magyarázó kommentje NEVET ejtett (`PracticeHubScreen`), és a
    // tool azt VALÓDI, kapu nélküli deklaratív hivatkozásnak számolta —
    // a képernyő `isFlagGated` értéke ettől hamisan `false` lett. Egy
    // komment nem regisztrál route-ot.
    final routingLines = {
      for (final path in routingSources)
        path: _withoutCommentLines(_readLines(path)),
    };
    final flagScopes = {
      for (final entry in routingLines.entries)
        entry.key: _computeFlagScopes(entry.value),
    };

    final libFiles = _allDartFiles('lib');
    final testFiles = _allDartFiles('test');

    // One pass over every `lib/`+`test/` file, instead of one pass PER
    // screen (was O(screens × files); this is O(files)) — see ADR 0471 /
    // E15-R03 MAJOR-2. Every screen class ends in "Screen" (enforced by
    // `_classDeclaration`), so a single generalised token regex can find
    // every candidate name on a line in one shot; the per-class-name regex
    // loop below only runs against the (typically one) screen(s) that
    // actually own that token, via [screenIndicesByClassName].
    final classNames = [
      for (final screenPath in screenPaths) _classNameOf(screenPath),
    ];
    final screenIndicesByClassName = <String, List<int>>{};
    for (var i = 0; i < classNames.length; i++) {
      screenIndicesByClassName.putIfAbsent(classNames[i], () => <int>[]).add(i);
    }

    final declarativeByScreen = List.generate(
      screenPaths.length,
      (_) => <DeclarativeReference>[],
    );
    for (final routingPath in routingSources) {
      final lines = routingLines[routingPath]!;
      final scopes = flagScopes[routingPath]!;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!line.contains('Screen')) continue;
        final matchedNames = <String>{
          for (final m in _referenceToken.allMatches(line)) m.group(1)!,
        };
        for (final name in matchedNames) {
          final indices = screenIndicesByClassName[name];
          if (indices == null) continue;
          final reference = DeclarativeReference(
            SourceRef(routingPath, i + 1),
            List.unmodifiable(scopes[i]),
          );
          for (final idx in indices) {
            declarativeByScreen[idx].add(reference);
          }
        }
      }
    }

    final imperativeByScreen = List.generate(
      screenPaths.length,
      (_) => <SourceRef>[],
    );
    for (final libPath in libFiles) {
      if (routingSources.contains(libPath)) continue;
      final lines = _readLines(libPath);
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!line.contains('Screen')) continue;
        final matchedNames = <String>{
          for (final m in _constructToken.allMatches(line)) m.group(1)!,
        };
        for (final name in matchedNames) {
          final indices = screenIndicesByClassName[name];
          if (indices == null) continue;
          final reference = SourceRef(libPath, i + 1);
          for (final idx in indices) {
            if (screenPaths[idx] == libPath) continue;
            imperativeByScreen[idx].add(reference);
          }
        }
      }
    }

    final testRefsByScreen = List.generate(
      screenPaths.length,
      (_) => <SourceRef>[],
    );
    for (final testPath in testFiles) {
      final lines = _readLines(testPath);
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!line.contains('Screen')) continue;
        final matchedNames = <String>{
          for (final m in _referenceToken.allMatches(line)) m.group(1)!,
        };
        for (final name in matchedNames) {
          final indices = screenIndicesByClassName[name];
          if (indices == null) continue;
          final reference = SourceRef(testPath, i + 1);
          for (final idx in indices) {
            testRefsByScreen[idx].add(reference);
          }
        }
      }
    }

    final verdicts = <ScreenVerdict>[];
    for (var idx = 0; idx < screenPaths.length; idx++) {
      final screenPath = screenPaths[idx];
      final className = classNames[idx];
      verdicts.add(
        ScreenVerdict(
          screenPath: screenPath,
          className: className,
          declaredAt: _declarationRef(screenPath, className),
          declarativeReferences: List.unmodifiable(declarativeByScreen[idx]),
          imperativeReferences: List.unmodifiable(imperativeByScreen[idx]),
          testReferences: List.unmodifiable(testRefsByScreen[idx]),
        ),
      );
    }

    verdicts.sort((a, b) => a.screenPath.compareTo(b.screenPath));
    return ScreenReachabilityResult._(List.unmodifiable(verdicts));
  }

  String _classNameOf(String screenPath) {
    final source = File(
      '${repository.path}${Platform.pathSeparator}$screenPath',
    ).readAsStringSync();
    final match = _classDeclaration.firstMatch(source);
    if (match == null) {
      throw StateError('$screenPath declares no class ending in "Screen"');
    }
    return match.group(1)!;
  }

  SourceRef _declarationRef(String screenPath, String className) {
    final lines = _readLines(screenPath);
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].contains('class $className')) {
        return SourceRef(screenPath, i + 1);
      }
    }
    return SourceRef(screenPath, 1);
  }

  /// Every `[A-Za-z0-9_]*Screen`-shaped token on a line, word-bounded. Used
  /// to find declarative/test mentions of any of the 96 screen classes in
  /// one pass; the caller intersects the captured names against the known
  /// class-name set, so a token that merely SHAPE-matches (ends in
  /// `Screen`) but isn't one of the 97 real classes is a harmless no-op.
  static final RegExp _referenceToken = RegExp(
    r'\b([A-Za-z0-9_]*Screen(?:V\d+)?)\b',
  );

  /// A construction site: `ClassName(` or `ClassName.namedCtor(`. Stricter
  /// than [_referenceToken] on purpose — ADR 0471 D2 requires the imperative
  /// channel to see the class actually being CONSTRUCTED, not merely
  /// mentioned as a type (a generic parameter or a doc comment does not
  /// make a screen reachable).
  static final RegExp _constructToken = RegExp(
    r'\b([A-Za-z0-9_]*Screen(?:V\d+)?)(?:\.[A-Za-z_][A-Za-z0-9_]*)?\s*\(',
  );

  /// For each line of a routing source, the list of flag conditions whose
  /// `if (...)` guard textually encloses it, using `dart format`'s
  /// consistent indentation as the scope signal: everything indented
  /// further than an `if (...Enabled...)` line belongs to it, until a line
  /// dedents back to (or past) the `if`'s own indentation.
  ///
  /// This is an indentation heuristic, not a bracket-matching parser — it
  /// is intentionally simpler than a full Dart parser and relies on the
  /// tree staying `dart format`-clean (the project's standing convention).
  static List<List<String>> _computeFlagScopes(List<String> lines) {
    final scopes = List<List<String>>.generate(lines.length, (_) => []);
    final stack = <_FlagGate>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      if (trimmed.isEmpty) {
        for (final gate in stack) {
          scopes[i].add(gate.condition);
        }
        continue;
      }
      final indent = line.length - trimmed.length;
      while (stack.isNotEmpty && indent <= stack.last.indent) {
        stack.removeLast();
      }
      for (final gate in stack) {
        scopes[i].add(gate.condition);
      }
      final match = _flagIf.firstMatch(trimmed);
      if (match != null) {
        final condition = match.group(1)!.trim();
        stack.add(_FlagGate(indent, condition));
        scopes[i].add(condition);
      }
    }
    return scopes;
  }

  /// Blanks every whole-line `//` comment, preserving the line count so a
  /// [SourceRef]'s line number still points at the real source line.
  ///
  /// Deliberately line-based, matching the rest of this tool: a trailing
  /// comment after real code stays (the code on that line is what counts),
  /// and block comments (`/* ... */`) are not used in the routing sources.
  static List<String> _withoutCommentLines(List<String> lines) => [
    for (final line in lines)
      if (line.trimLeft().startsWith('//')) '' else line,
  ];

  List<String> _readLines(String relativePath) => File(
    '${repository.path}${Platform.pathSeparator}$relativePath',
  ).readAsLinesSync();

  List<String> _allDartFiles(String subdirectory) {
    final dir = Directory(
      '${repository.path}${Platform.pathSeparator}$subdirectory',
    );
    if (!dir.existsSync()) return const [];
    final files =
        dir
            .listSync(recursive: true)
            .whereType<File>()
            .map((file) => _relativePath(file.path))
            .where((path) => path.endsWith('.dart'))
            .toList()
          ..sort();
    return files;
  }

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

final class _FlagGate {
  const _FlagGate(this.indent, this.condition);

  final int indent;
  final String condition;
}

// ---------------------------------------------------------------------------
// Incoming-reference measurement for the route constants (WP-C, 2026-09-06)
// ---------------------------------------------------------------------------

/// One `AppRoutes.<name>` constant together with every place OUTSIDE the
/// routing declaration itself that names it.
///
/// **Why this is a separate channel from [ScreenVerdict].** A screen counts
/// as "reachable" the moment the router NAMES its class — but a registered
/// `GoRoute` nobody ever navigates to is a door with no handle. That is
/// exactly the measured 2026-09-06 community defect: all thirteen community
/// screens were `reachable: true` while the shipped UI reached none of them.
/// This cell measures the other direction: does anything push/go to the
/// route constant?
final class RouteConstantVerdict {
  const RouteConstantVerdict({
    required this.name,
    required this.path,
    required this.declaredAt,
    required this.incomingReferences,
  });

  /// The constant's identifier, e.g. `communityFeed`.
  final String name;

  /// Its literal value, e.g. `/community/feed`.
  final String path;

  final SourceRef declaredAt;

  /// `AppRoutes.<name>` mentions under `lib/`, excluding the route-constant
  /// declaration file and the router table itself.
  final List<SourceRef> incomingReferences;

  bool get hasIncomingReference => incomingReferences.isNotEmpty;

  Map<String, Object?> toJson() => {
    'name': name,
    'path': path,
    'declaredAt': declaredAt.toJson(),
    'hasIncomingReference': hasIncomingReference,
    'incomingReferences': [for (final r in incomingReferences) r.toJson()],
  };
}

/// The measured route-constant reference table.
final class RouteReferenceResult {
  RouteReferenceResult._(this.verdicts);

  final List<RouteConstantVerdict> verdicts;

  int get withIncomingCount =>
      verdicts.where((v) => v.hasIncomingReference).length;

  int get withoutIncomingCount => verdicts.length - withIncomingCount;

  /// The summary line the CI log greps for.
  String get summaryLine =>
      'Route constants without incoming reference: $withoutIncomingCount';

  Map<String, Object?> toJson() => {
    'routeConstantCount': verdicts.length,
    'withIncomingReferenceCount': withIncomingCount,
    'withoutIncomingReferenceCount': withoutIncomingCount,
    'routes': [for (final v in verdicts) v.toJson()],
  };

  String toMarkdownTable() {
    final buffer = StringBuffer()
      ..writeln('# Route-constant incoming references (measured)')
      ..writeln()
      ..writeln(
        'Route constants: ${verdicts.length}. With an incoming reference: '
        '$withIncomingCount. Without: $withoutIncomingCount.',
      )
      ..writeln()
      ..writeln('| Route constant | Path | Incoming | Referenced from |')
      ..writeln('| --- | --- | --- | --- |');
    for (final v in verdicts) {
      final referenced = v.hasIncomingReference
          ? v.incomingReferences.map((r) => r.location).join('; ')
          : '—';
      buffer.writeln(
        '| `AppRoutes.${v.name}` | `${v.path}` | '
        '${v.hasIncomingReference ? 'yes' : 'NO'} | $referenced |',
      );
    }
    buffer
      ..writeln()
      ..writeln(summaryLine);
    return buffer.toString();
  }
}

/// Measures, for every `static const String` in `lib/app/routing/
/// app_route.dart`, whether anything else under `lib/` names it.
///
/// **Deliberately NON-failing (WP-C).** A missing incoming reference is not
/// automatically a defect: several hubs reach their screens with
/// `Navigator.push` and never touch the route constant. The table is a
/// review input, printed next to the reachability verdicts — not a gate.
final class RouteConstantReferences {
  RouteConstantReferences(this.repository);

  final Directory repository;

  /// Where the constants are declared.
  static const String routeConstantSource = 'lib/app/routing/app_route.dart';

  /// The declaration file plus the router table: naming a constant in
  /// either is what CREATES the route, never what REACHES it.
  static const List<String> excludedSources = [
    routeConstantSource,
    'lib/app/routing/app_router.dart',
  ];

  static final RegExp _constantDeclaration = RegExp(
    r'static\s+const\s+String\s+([A-Za-z0-9_]+)\s*=',
  );

  RouteReferenceResult render() {
    final lines = _readLines(routeConstantSource);
    final source = lines.join('\n');
    final names = <String, SourceRef>{};
    final values = <String, String>{};
    for (var i = 0; i < lines.length; i++) {
      final match = _constantDeclaration.firstMatch(lines[i]);
      if (match == null) continue;
      final name = match.group(1)!;
      names[name] = SourceRef(routeConstantSource, i + 1);
      values[name] = _literalAfter(source, lines, i) ?? '';
    }

    final incoming = {for (final name in names.keys) name: <SourceRef>[]};
    for (final libPath in _allDartFiles('lib')) {
      if (excludedSources.contains(libPath)) continue;
      final fileLines = _readLines(libPath);
      for (var i = 0; i < fileLines.length; i++) {
        final line = fileLines[i];
        if (!line.contains('AppRoutes.')) continue;
        for (final match in _usageToken.allMatches(line)) {
          final name = match.group(1)!;
          incoming[name]?.add(SourceRef(libPath, i + 1));
        }
      }
    }

    final verdicts = [
      for (final entry in names.entries)
        RouteConstantVerdict(
          name: entry.key,
          path: values[entry.key] ?? '',
          declaredAt: entry.value,
          incomingReferences: List.unmodifiable(incoming[entry.key]!),
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));
    return RouteReferenceResult._(List.unmodifiable(verdicts));
  }

  static final RegExp _usageToken = RegExp(r'\bAppRoutes\.([A-Za-z0-9_]+)\b');

  /// The single-quoted literal that follows the `=` of a constant. The
  /// declaration may wrap onto the next line (`dart format` does this for
  /// long paths), so the search continues past the declaration line.
  String? _literalAfter(String source, List<String> lines, int index) {
    for (var i = index; i < lines.length && i <= index + 2; i++) {
      final match = RegExp("'([^']*)'").firstMatch(lines[i]);
      if (match != null) return match.group(1);
    }
    return null;
  }

  List<String> _readLines(String relativePath) => File(
    '${repository.path}${Platform.pathSeparator}$relativePath',
  ).readAsLinesSync();

  List<String> _allDartFiles(String subdirectory) {
    final dir = Directory(
      '${repository.path}${Platform.pathSeparator}$subdirectory',
    );
    if (!dir.existsSync()) return const [];
    final root = repository.absolute.path;
    final files =
        dir
            .listSync(recursive: true)
            .whereType<File>()
            .map(
              (file) => file.absolute.path
                  .substring(root.length + 1)
                  .replaceAll('\\', '/'),
            )
            .where((path) => path.endsWith('.dart'))
            .toList()
          ..sort();
    return files;
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

  final repository = Directory(repoPath);
  final result = ScreenReachability(repository).render();
  final routeReferences = RouteConstantReferences(repository).render();
  if (format == 'json') {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        ...result.toJson(),
        'routeConstants': routeReferences.toJson(),
      }),
    );
  } else {
    stdout
      ..write(result.toMarkdownTable())
      ..writeln()
      ..write(routeReferences.toMarkdownTable());
  }
}
