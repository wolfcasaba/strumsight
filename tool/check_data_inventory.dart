import 'dart:io';

/// One data field declared under a route in `docs/privacy/data-inventory.yaml`.
final class InventoryField {
  const InventoryField({
    required this.name,
    required this.purpose,
    required this.legalBasis,
    required this.retention,
    required this.storage,
    required this.leavesDevice,
    required this.leavesDeviceDeclared,
    required this.line,
  });

  final String name;
  final String purpose;
  final String legalBasis;
  final String retention;
  final String storage;
  final bool leavesDevice;

  /// Whether a `leaves_device:` line was actually present — [leavesDevice]
  /// alone cannot distinguish "declared false" from "never declared",
  /// since the parser must default to something when the key is absent.
  final bool leavesDeviceDeclared;

  /// 1-based line of the field's `- name:` entry in the source YAML.
  final int line;

  /// The A1 acceptance cell: every field must carry a purpose, a legal
  /// basis, a retention statement, a storage location and an explicit
  /// leaves_device verdict. Returns the names of whichever are blank.
  List<String> missingAttributes() {
    final missing = <String>[];
    if (purpose.trim().isEmpty) missing.add('purpose');
    if (legalBasis.trim().isEmpty) missing.add('legal_basis');
    if (retention.trim().isEmpty) missing.add('retention');
    if (storage.trim().isEmpty) missing.add('storage');
    if (!leavesDeviceDeclared) missing.add('leaves_device');
    return missing;
  }
}

/// One egress route declared in `docs/privacy/data-inventory.yaml`.
///
/// [source] is the cross-check key against [DiscoveredEgressRoute.source] —
/// it must read EXACTLY `DioFactory.create<Name>Client` for a pattern-(a)
/// route, or the bare class name for a pattern-(b)/(c) route (ADR 0479 D1).
final class InventoryRoute {
  const InventoryRoute({
    required this.id,
    required this.source,
    required this.file,
    required this.wired,
    required this.gate,
    required this.consentSwitch,
    required this.fields,
    required this.line,
  });

  final String id;
  final String source;
  final String file;
  final bool wired;
  final String gate;
  final String consentSwitch;
  final List<InventoryField> fields;

  /// 1-based line of the route's `- id:` entry in the source YAML.
  final int line;
}

/// Parses the restricted YAML subset `docs/privacy/data-inventory.yaml` is
/// written in (see that file's own header comment for the schema).
///
/// This is deliberately NOT a general YAML parser — the project has no
/// `package:yaml` dependency (`flutter analyze`'s `depend_on_referenced_packages`
/// lint would flag importing a transitive one), and `tool/ci/check_assets.dart`
/// already set the precedent of a hand-rolled reader scoped to exactly the
/// one document it needs.
final class DataInventory {
  const DataInventory(this.routes);

  final List<InventoryRoute> routes;

  static DataInventory parseFile(File file) => parse(file.readAsLinesSync());

  static DataInventory parse(List<String> lines) {
    final routes = <InventoryRoute>[];

    String? id, source, routeFile, gate, consentSwitch;
    bool? wired;
    var routeLine = 0;
    var fields = <InventoryField>[];

    String? fieldName, purpose, legalBasis, retention, storage;
    bool? leavesDevice;
    var fieldLine = 0;
    var inField = false;

    void flushField() {
      if (!inField) return;
      fields.add(
        InventoryField(
          name: fieldName ?? '',
          purpose: purpose ?? '',
          legalBasis: legalBasis ?? '',
          retention: retention ?? '',
          storage: storage ?? '',
          leavesDevice: leavesDevice ?? false,
          leavesDeviceDeclared: leavesDevice != null,
          line: fieldLine,
        ),
      );
      fieldName = purpose = legalBasis = retention = storage = null;
      leavesDevice = null;
      inField = false;
    }

    void flushRoute() {
      flushField();
      if (id == null) return;
      routes.add(
        InventoryRoute(
          id: id!,
          source: source ?? '',
          file: routeFile ?? '',
          wired: wired ?? false,
          gate: gate ?? '',
          consentSwitch: consentSwitch ?? '',
          fields: List<InventoryField>.unmodifiable(fields),
          line: routeLine,
        ),
      );
      id = source = routeFile = gate = consentSwitch = null;
      wired = null;
      fields = <InventoryField>[];
    }

    final routeStartPattern = RegExp(r'^  - id:\s*(.*)$');
    final fieldStartPattern = RegExp(r'^      - name:\s*(.*)$');
    final routeKvPattern = RegExp(r'^    (\w+):\s?(.*)$');
    final fieldKvPattern = RegExp(r'^        (\w+):\s?(.*)$');

    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final line = i + 1;
      if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) continue;
      if (raw.trim() == 'routes:') continue;

      final routeStart = routeStartPattern.firstMatch(raw);
      if (routeStart != null) {
        flushRoute();
        id = _unquote(routeStart.group(1)!);
        routeLine = line;
        continue;
      }

      final fieldStart = fieldStartPattern.firstMatch(raw);
      if (fieldStart != null) {
        flushField();
        inField = true;
        fieldName = _unquote(fieldStart.group(1)!);
        fieldLine = line;
        continue;
      }

      final fieldKv = inField ? fieldKvPattern.firstMatch(raw) : null;
      if (fieldKv != null) {
        final key = fieldKv.group(1)!;
        final value = _unquote(fieldKv.group(2)!);
        switch (key) {
          case 'purpose':
            purpose = value;
          case 'legal_basis':
            legalBasis = value;
          case 'retention':
            retention = value;
          case 'storage':
            storage = value;
          case 'leaves_device':
            leavesDevice = value.trim() == 'true';
          default:
            throw FormatException(
              'data-inventory.yaml:$line unknown field key "$key"',
            );
        }
        continue;
      }

      final routeKv = !inField ? routeKvPattern.firstMatch(raw) : null;
      if (routeKv != null) {
        final key = routeKv.group(1)!;
        final value = _unquote(routeKv.group(2)!);
        switch (key) {
          case 'source':
            source = value;
          case 'file':
            routeFile = value;
          case 'wired':
            wired = value.trim() == 'true';
          case 'gate':
            gate = value;
          case 'consent_switch':
            consentSwitch = value;
          case 'fields':
            break; // nested block starts on the following `- name:` lines.
          default:
            throw FormatException(
              'data-inventory.yaml:$line unknown route key "$key"',
            );
        }
        continue;
      }

      throw FormatException(
        'data-inventory.yaml:$line unrecognized line: $raw',
      );
    }
    flushRoute();

    return DataInventory(List<InventoryRoute>.unmodifiable(routes));
  }
}

String _unquote(String value) {
  final trimmed = value.trim();
  if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

// ---------------------------------------------------------------------------
// Tree-walker — the leltár's completeness is measured by the FA, not
// asserted by the author (ADR 0479 D1). Every one of the three pattern
// classes below is required by the ADR because the real tree exercises all
// three (§0.0.A.2 of the round brief).
// ---------------------------------------------------------------------------

enum EgressPatternKind {
  /// (a) A `DioFactory.create*Client` method — the only production
  /// constructor for a `Dio`-backed client (guarded separately by
  /// `test/tooling/dio_factory_guard_test.dart`).
  dioFactoryMethod,

  /// (b) Any OTHER `lib/**` class that fields/accepts a `Dio` and calls a
  /// request verb on it — the exact blind spot L140 measured: an injected
  /// `Dio` never goes through `Dio(...)`, so the factory guard cannot see it.
  dioConsumingClass,

  /// (c) Direct `dart:io` `HttpClient(` or `package:http` verb usage,
  /// bypassing Dio entirely. None exist in the tree today; the pattern is
  /// still required so a future direct-HTTP egress cannot go unnoticed.
  directHttpClient,
}

/// One egress route the tree actually produces, independent of whether
/// `docs/privacy/data-inventory.yaml` has heard of it yet.
final class DiscoveredEgressRoute {
  const DiscoveredEgressRoute({
    required this.source,
    required this.kind,
    required this.file,
    required this.line,
  });

  /// Cross-check key against [InventoryRoute.source].
  final String source;
  final EgressPatternKind kind;
  final String file;
  final int line;
}

/// Files that are themselves generic transport plumbing, not a distinct
/// egress route in their own right. Excluding a file here is NOT a loophole
/// silently widening what counts as "covered" — every entry carries a
/// written, independently-checkable reason, mirroring the discipline
/// `tool/check_architecture.dart`'s `architectureAllowlist` already uses in
/// this tree. This list may only shrink without an ADR.
const Map<String, String> dioConsumingClassExclusions = {
  'lib/core/network/dio_factory.dart':
      'DioFactory itself — its egress routes are discovered directly as '
      'pattern (a), one per create*Client method; scanning it again as '
      'pattern (b) would double-count the same routes.',
  'lib/core/network/api_client.dart':
      'ApiClient is the generic Dio wrapper DioFactory hands out for BOTH '
      'pattern-(a) routes (createAccountClient / createDiagnosticsClient); '
      'it is never constructed with an injected Dio anywhere else in '
      'lib/**, so counting it separately would demand a third, phantom '
      'inventory entry for routes pattern (a) already requires.',
};

final _dioFactoryMethodPattern = RegExp(r'ApiClient\s+create(\w+)Client\s*\(');

/// Matches a `Dio`-typed field declaration (`final Dio _dio;`) or
/// constructor parameter (`required Dio dio`, `Dio dio)`) — deliberately
/// anchored on the declaration shape (terminated by `;`, `,` or `)`) rather
/// than a bare `\bDio\b` token match, so a comment merely mentioning "Dio"
/// (e.g. "concrete Dio implementations land in...") cannot false-positive.
final _dioTypedMemberPattern = RegExp(
  r'\bfinal\s+Dio\??\s+\w+\s*;|(?:required\s+)?Dio\??\s+\w+\s*[,)]',
);
final _requestVerbCallPattern = RegExp(
  r'\.(post|get|put|delete|request)\s*(<[^>]*>)?\s*\(',
);
final _classNamePattern = RegExp(r'(?:^|\s)(?:final\s+)?class\s+(\w+)');
final _directHttpClientPattern = RegExp(r'\bHttpClient\s*\(');
final _packageHttpVerbPattern = RegExp(
  r'\bhttp\.(get|post|put|delete|patch)\s*\(',
);

/// Walks `lib/**` and returns every egress route the tree measurably
/// produces today, via all three pattern classes.
List<DiscoveredEgressRoute> discoverEgressRoutes(Directory repositoryRoot) {
  final libDir = Directory('${repositoryRoot.path}/lib');
  return List<DiscoveredEgressRoute>.unmodifiable(<DiscoveredEgressRoute>[
    ..._discoverDioFactoryMethods(repositoryRoot),
    ..._discoverDioConsumingClasses(libDir, repositoryRoot),
    ..._discoverDirectHttpUsage(libDir, repositoryRoot),
  ]);
}

List<DiscoveredEgressRoute> _discoverDioFactoryMethods(
  Directory repositoryRoot,
) {
  final file = File('${repositoryRoot.path}/lib/core/network/dio_factory.dart');
  if (!file.existsSync()) return const [];
  final lines = file.readAsLinesSync();
  final results = <DiscoveredEgressRoute>[];
  for (var i = 0; i < lines.length; i++) {
    final match = _dioFactoryMethodPattern.firstMatch(lines[i]);
    if (match == null) continue;
    results.add(
      DiscoveredEgressRoute(
        source: 'DioFactory.create${match.group(1)}Client',
        kind: EgressPatternKind.dioFactoryMethod,
        file: 'lib/core/network/dio_factory.dart',
        line: i + 1,
      ),
    );
  }
  return results;
}

List<DiscoveredEgressRoute> _discoverDioConsumingClasses(
  Directory libDir,
  Directory repositoryRoot,
) {
  final results = <DiscoveredEgressRoute>[];
  if (!libDir.existsSync()) return results;
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final relativePath = _relativePath(repositoryRoot, entity.path);
    if (dioConsumingClassExclusions.containsKey(relativePath)) continue;

    final content = entity.readAsStringSync();
    final classMatches = _classNamePattern.allMatches(content).toList();
    for (var i = 0; i < classMatches.length; i++) {
      final match = classMatches[i];
      final bodyEnd = i + 1 < classMatches.length
          ? classMatches[i + 1].start
          : content.length;
      final body = content.substring(match.end, bodyEnd);
      if (!_dioTypedMemberPattern.hasMatch(body)) continue;
      if (!_requestVerbCallPattern.hasMatch(body)) continue;

      final line =
          '\n'.allMatches(content.substring(0, match.start)).length + 1;
      results.add(
        DiscoveredEgressRoute(
          source: match.group(1)!,
          kind: EgressPatternKind.dioConsumingClass,
          file: relativePath,
          line: line,
        ),
      );
    }
  }
  return results;
}

List<DiscoveredEgressRoute> _discoverDirectHttpUsage(
  Directory libDir,
  Directory repositoryRoot,
) {
  final results = <DiscoveredEgressRoute>[];
  if (!libDir.existsSync()) return results;
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final relativePath = _relativePath(repositoryRoot, entity.path);
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isDirectUsage =
          _directHttpClientPattern.hasMatch(line) ||
          _packageHttpVerbPattern.hasMatch(line);
      if (!isDirectUsage) continue;
      results.add(
        DiscoveredEgressRoute(
          source: 'direct:$relativePath:${i + 1}',
          kind: EgressPatternKind.directHttpClient,
          file: relativePath,
          line: i + 1,
        ),
      );
    }
  }
  return results;
}

String _relativePath(Directory repositoryRoot, String absolutePath) {
  final normalizedRoot = repositoryRoot.absolute.path;
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

// ---------------------------------------------------------------------------
// Report — cross-checks the measured tree against the declared inventory.
// ---------------------------------------------------------------------------

final class DataInventoryViolation {
  const DataInventoryViolation(this.message);
  final String message;
}

final class DataInventoryReport {
  DataInventoryReport({
    required this.discovered,
    required this.inventory,
    required List<DataInventoryViolation> violations,
  }) : violations = List.unmodifiable(violations);

  final List<DiscoveredEgressRoute> discovered;
  final DataInventory inventory;
  final List<DataInventoryViolation> violations;

  bool get isClean => violations.isEmpty;

  String format() {
    if (isClean) {
      return 'Data inventory check OK '
          '(${discovered.length} measured egress route(s), '
          '${inventory.routes.length} inventory route(s)).';
    }
    final buffer = StringBuffer('Data inventory check failed.');
    for (final violation in violations) {
      buffer
        ..writeln()
        ..write('- ${violation.message}');
    }
    return buffer.toString();
  }
}

/// The A1 + A2 acceptance cells in one pass: A2 (every measured route has an
/// inventory entry, and a `wired: true` claim is reproducible by the tree)
/// and A1 (every declared field carries purpose/legal_basis/retention/storage,
/// every route documents its consent_switch).
///
/// **NOT an acceptable weakening:** starting from the inventory's own route
/// list instead of [discovered] — that is exactly the checker shape ADR 0479
/// D1 rejects, because it stays green through the first new, undeclared
/// endpoint.
DataInventoryReport checkDataInventory({
  required List<DiscoveredEgressRoute> discovered,
  required DataInventory inventory,
}) {
  final violations = <DataInventoryViolation>[];
  final bySource = <String, InventoryRoute>{
    for (final route in inventory.routes) route.source: route,
  };

  for (final route in discovered) {
    final entry = bySource[route.source];
    if (entry == null) {
      violations.add(
        DataInventoryViolation(
          'measured egress route "${route.source}" '
          '(${route.file}:${route.line}) has no '
          'docs/privacy/data-inventory.yaml entry',
        ),
      );
      continue;
    }
    if (entry.fields.isEmpty) {
      violations.add(
        DataInventoryViolation(
          'inventory route "${entry.id}" (${route.source}) has no fields',
        ),
      );
    }
  }

  final discoveredSources = discovered.map((r) => r.source).toSet();
  for (final route in inventory.routes) {
    if (route.wired && !discoveredSources.contains(route.source)) {
      violations.add(
        DataInventoryViolation(
          'inventory route "${route.id}" (${route.source}) is marked '
          'wired: true but the tree does not currently produce that route '
          '— the code moved/was removed, or the entry is stale',
        ),
      );
    }
  }

  for (final route in inventory.routes) {
    if (route.consentSwitch.trim().isEmpty) {
      violations.add(
        DataInventoryViolation(
          'inventory route "${route.id}" has no consent_switch documented',
        ),
      );
    }
    for (final field in route.fields) {
      final missing = field.missingAttributes();
      if (missing.isNotEmpty) {
        violations.add(
          DataInventoryViolation(
            'inventory route "${route.id}" field "${field.name}" is '
            'missing: ${missing.join(', ')}',
          ),
        );
      }
    }
  }

  return DataInventoryReport(
    discovered: discovered,
    inventory: inventory,
    violations: violations,
  );
}

void main(List<String> arguments) {
  final repositoryRoot = Directory.current;
  final inventoryFile = File(
    '${repositoryRoot.path}/docs/privacy/data-inventory.yaml',
  );
  if (!inventoryFile.existsSync()) {
    stderr.writeln('docs/privacy/data-inventory.yaml not found');
    exitCode = 1;
    return;
  }
  try {
    final inventory = DataInventory.parseFile(inventoryFile);
    final discovered = discoverEgressRoutes(repositoryRoot);
    final report = checkDataInventory(
      discovered: discovered,
      inventory: inventory,
    );
    if (report.isClean) {
      stdout.writeln(report.format());
    } else {
      stderr.writeln(report.format());
      exitCode = 1;
    }
  } on FormatException catch (error) {
    stderr.writeln('Data inventory check could not run: $error');
    exitCode = 2;
  }
}
