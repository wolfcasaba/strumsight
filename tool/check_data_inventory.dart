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
/// route, or the bare class name for any other pattern (ADR 0479 D1).
final class InventoryRoute {
  const InventoryRoute({
    required this.id,
    required this.source,
    required this.file,
    required this.wired,
    required this.gate,
    required this.consentSwitch,
    required this.rides,
    required this.fields,
    required this.line,
  });

  final String id;
  final String source;
  final String file;
  final bool wired;
  final String gate;
  final String consentSwitch;

  /// Non-empty only for a THIN "rides" entry (E12-R17 javító kör #1,
  /// MAJOR-2): a measured egress-producing class that shares another
  /// route's transport/consent gate one-for-one (e.g. every ApiClient-
  /// consuming repository riding the same `accountApiClientProvider` as
  /// `account_api`) and therefore does not carry its own `fields` list.
  /// Names the `id` of the route it rides; [checkDataInventory] verifies
  /// that id resolves to a route with at least one field of its own.
  final String rides;

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

    String? id, source, routeFile, gate, consentSwitch, rides;
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
          rides: rides ?? '',
          fields: List<InventoryField>.unmodifiable(fields),
          line: routeLine,
        ),
      );
      id = source = routeFile = gate = consentSwitch = rides = null;
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
            leavesDevice = _parseStrictBool(
              value,
              line: line,
              key: 'leaves_device',
            );
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
            wired = _parseStrictBool(value, line: line, key: 'wired');
          case 'gate':
            gate = value;
          case 'consent_switch':
            consentSwitch = value;
          case 'rides':
            rides = value;
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

/// MINOR-3 (E12-R17 javító kör #1): the previous reader accepted ANY value
/// as `false` unless it was the exact lowercase literal `true` — so
/// `leaves_device: True` (valid YAML boolean, common typo/case slip) was
/// silently read as `leavesDevice=false`, `declared=true`, producing a
/// clean `missingAttributes()` on the inventory's single most safety-
/// critical field with no warning at all (fail-open). Only the two
/// lowercase literals this file itself always writes are accepted; every
/// other spelling is a hard parse failure.
bool _parseStrictBool(String value, {required int line, required String key}) {
  final trimmed = value.trim();
  if (trimmed == 'true') return true;
  if (trimmed == 'false') return false;
  throw FormatException(
    'data-inventory.yaml:$line "$key" must be exactly "true" or "false", '
    'got "$trimmed"',
  );
}

// ---------------------------------------------------------------------------
// Tree-walker — the leltár's completeness is measured by the FA, not
// asserted by the author (ADR 0479 D1). The pattern classes below are
// required because the real tree exercises each of them (§0.0.A.2 of the
// round brief; (d)/(e) added by the E12-R17 javító kör #1 to close MAJOR-1
// and MAJOR-2 — a checker that only understood raw Dio was blind to the
// tree's most common outbound shape, an `ApiClient`-typed field, and to its
// strongest single "leaves the device" event, a user-initiated share).
// ---------------------------------------------------------------------------

enum EgressPatternKind {
  /// (a) A `create*Client` factory method on `DioFactory` — the only
  /// production constructor for a `Dio`-backed client (guarded separately
  /// by `test/tooling/dio_factory_guard_test.dart`).
  dioFactoryMethod,

  /// (b) Any OTHER `lib/**` class that fields/accepts a `Dio` and calls a
  /// request verb on it — the exact blind spot L140 measured: an injected
  /// `Dio` never goes through `Dio(...)`, so the factory guard cannot see
  /// it. Also covers the MINOR-1 file-level fallback for shapes that are
  /// not a `class Foo { ... }` at all (mixin/extension/typedef/top-level
  /// function around an injected `Dio`).
  dioConsumingClass,

  /// (c) Any `lib/**` class that fields/accepts an `ApiClient` (the
  /// project's own Dio wrapper) and calls a request-verb method on it —
  /// MAJOR-2: the tree's most common sender shape, six measured classes as
  /// of this round, none of which construct a `Dio` directly.
  apiClientConsumingClass,

  /// (d) A `lib/**` class that calls `SharePlus.instance.share`/
  /// `shareXFiles`/`shareUri` — MAJOR-1: a user-initiated hand-off of a
  /// redacted export / card PNG / caption to an arbitrary OS-chosen
  /// destination app, the strongest "leaves the device" event on the tree.
  userInitiatedShare,

  /// (e) Direct `dart:io` `HttpClient(` or `package:http` verb usage,
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
/// this tree. This list may only shrink without an ADR. MINOR-2 (E12-R17
/// javító kör #1): a blanket exclusion is not a blanket blind spot — see
/// [dioConsumingClassExclusionCallSiteCounts] below, which pins each
/// file's own known call-site count so a NEW one is still noticed.
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

/// MINOR-2: the pinned Dio request-verb call-site count for each file in
/// [dioConsumingClassExclusions] — measured, not assumed. A file's count
/// drifting from its pin (e.g. a hardcoded `_dio.post('/exfil', …)` slipped
/// into `api_client.dart`) is exactly the blind spot the blanket exclusion
/// would otherwise hide; [checkExclusionCallSiteDrift] re-measures both
/// files on every run and fails if either count has moved.
const Map<String, int> dioConsumingClassExclusionCallSiteCounts = {
  'lib/core/network/dio_factory.dart': 0,
  'lib/core/network/api_client.dart': 3,
};

/// MINOR-2: loosened off the `ApiClient` return type — the previous pattern
/// required `ApiClient create(\w+)Client(`, so a hypothetical
/// `Dio createTutorStreamClient() => Dio();` (wrong return type, still a
/// production Dio-backed client factory) was invisible to BOTH pattern (a)
/// (wrong return type) and pattern (b) (the whole file is excluded, see
/// [dioConsumingClassExclusions]). Scoped to `dio_factory.dart` only, so
/// loosening the return-type binding cannot pick up unrelated methods
/// elsewhere in the tree.
final _dioFactoryMethodPattern = RegExp(r'\b\w+\s+create(\w+)Client\s*\(');

/// Matches a `Dio`-typed field declaration (`final Dio _dio;`) or
/// constructor parameter (`required Dio dio`, `Dio dio)`) — deliberately
/// anchored on the declaration shape (terminated by `;`, `,` or `)`) rather
/// than a bare `\bDio\b` token match, so a comment merely mentioning "Dio"
/// (e.g. "concrete Dio implementations land in...") cannot false-positive.
final _dioTypedMemberPattern = RegExp(
  r'\bfinal\s+Dio\??\s+\w+\s*;|(?:required\s+)?Dio\??\s+\w+\s*[,)]',
);

/// MINOR-1: the verb list is widened from the original four (`post`/`get`/
/// `put`/`delete`) to also catch `.patch(` (a real backend endpoint shape —
/// `backend/app/community/routers/posts.py:291` already serves PATCH),
/// `.head(`, `.download(`, `.fetch(`, and the `*Uri` request-builder
/// variants Dio also exposes (`.postUri(`, `.getUri(`, …).
final _requestVerbCallPattern = RegExp(
  r'\.(post|get|put|delete|patch|head|download|fetch|request)(Uri)?'
  r'\s*(<[^>]*>)?\s*\(',
);

/// Matches an `ApiClient`-typed field/parameter, mirroring
/// [_dioTypedMemberPattern] — MAJOR-2's pattern (c): the project's own
/// `Dio` wrapper is a far more common sender shape in this tree than a raw
/// injected `Dio`.
final _apiClientTypedMemberPattern = RegExp(
  r'\bfinal\s+ApiClient\??\s+\w+\s*;|(?:required\s+)?ApiClient\??\s+\w+\s*[,)]',
);

/// `ApiClient`'s own request-verb surface (`lib/core/network/api_client.dart`)
/// — deliberately its own list, not [_requestVerbCallPattern]'s Dio verbs,
/// since `ApiClient` exposes typed wrappers (`getJson`/`postJson`/`putJson`)
/// plus the two body-less `post`/`delete` methods, not Dio's raw verbs.
final _apiClientRequestVerbCallPattern = RegExp(
  r'\.(getJson|postJson|putJson|post|delete)\s*(<[^>]*>)?\s*\(',
);

/// MAJOR-1's pattern (d): a `share_plus` share-sheet call. `SharePlus` is a
/// static singleton (`SharePlus.instance`), so unlike the Dio/ApiClient
/// patterns above there is no typed-member declaration to additionally
/// require — the call site itself is the whole signal.
final _sharePlusCallPattern = RegExp(
  r'SharePlus\.instance\.(share|shareXFiles|shareUri)\s*\(',
);

final _classNamePattern = RegExp(r'(?:^|\s)(?:final\s+)?class\s+(\w+)');
final _directHttpClientPattern = RegExp(r'\bHttpClient\s*\(');
final _packageHttpVerbPattern = RegExp(
  r'\bhttp\.(get|post|put|delete|patch)\s*\(',
);

/// A bare Dart identifier — the shape [InventoryRoute.source] takes for
/// every pattern EXCEPT (a) (`DioFactory.create*Client`) and (e)
/// (`direct:file:line`). [checkWiredFalseConstructionSites] only applies to
/// this shape: a construction-site search for `DioFactory.createXClient(`
/// or `direct:lib/foo.dart:12(` would be nonsensical.
final _bareIdentifierPattern = RegExp(r'^[A-Za-z_]\w*$');

/// Walks `lib/**` and returns every egress route the tree measurably
/// produces today, via all the mandated pattern classes.
List<DiscoveredEgressRoute> discoverEgressRoutes(Directory repositoryRoot) {
  final libDir = Directory('${repositoryRoot.path}/lib');
  return List<DiscoveredEgressRoute>.unmodifiable(<DiscoveredEgressRoute>[
    ..._discoverDioFactoryMethods(repositoryRoot),
    ..._discoverDioConsumingClasses(libDir, repositoryRoot),
    ..._discoverApiClientConsumingClasses(libDir, repositoryRoot),
    ..._discoverShareInitiatedClasses(libDir, repositoryRoot),
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

/// Blanks `//` and `/* */` comments and string-literal contents to
/// whitespace (preserving line breaks, so line-number computation on the
/// result stays correct) — mirrors `tool/check_architecture.dart`'s
/// `_codeWithoutTrivia`. MINOR-1's P10: without this, a doc-comment that
/// merely CONTAINS the word "class" (e.g. "// this class is not
/// thread-safe") is itself matched by [_classNamePattern] and silently
/// splits a real class's body in two, so neither half carries both the
/// typed-member declaration and the verb call — the real sender vanishes
/// from the inventory with no error.
String _codeWithoutTrivia(String source) {
  const lineFeed = 0x0a;
  const slash = 0x2f;
  const asterisk = 0x2a;
  const backslash = 0x5c;
  const singleQuote = 0x27;
  const doubleQuote = 0x22;
  const lowercaseR = 0x72;
  const uppercaseR = 0x52;
  bool isQuote(int c) => c == singleQuote || c == doubleQuote;

  final output = StringBuffer();
  var index = 0;
  while (index < source.length) {
    final character = source.codeUnitAt(index);
    if (character == slash && index + 1 < source.length) {
      final next = source.codeUnitAt(index + 1);
      if (next == slash) {
        while (index < source.length && source.codeUnitAt(index) != lineFeed) {
          output.write(' ');
          index++;
        }
        continue;
      }
      if (next == asterisk) {
        var depth = 1;
        output.write('  ');
        index += 2;
        while (index < source.length && depth > 0) {
          if (index + 1 < source.length &&
              source.codeUnitAt(index) == slash &&
              source.codeUnitAt(index + 1) == asterisk) {
            depth++;
            output.write('  ');
            index += 2;
          } else if (index + 1 < source.length &&
              source.codeUnitAt(index) == asterisk &&
              source.codeUnitAt(index + 1) == slash) {
            depth--;
            output.write('  ');
            index += 2;
          } else {
            output.write(source.codeUnitAt(index) == lineFeed ? '\n' : ' ');
            index++;
          }
        }
        continue;
      }
    }
    final rawPrefix =
        (character == lowercaseR || character == uppercaseR) &&
        index + 1 < source.length &&
        isQuote(source.codeUnitAt(index + 1));
    if (isQuote(character) || rawPrefix) {
      if (rawPrefix) {
        output.write(' ');
        index++;
      }
      final quote = source.codeUnitAt(index);
      final triple =
          index + 2 < source.length &&
          source.codeUnitAt(index + 1) == quote &&
          source.codeUnitAt(index + 2) == quote;
      final delimiterLength = triple ? 3 : 1;
      output.write(' ' * delimiterLength);
      index += delimiterLength;
      while (index < source.length) {
        final c = source.codeUnitAt(index);
        if (!rawPrefix && c == backslash && index + 1 < source.length) {
          output.write('  ');
          index += 2;
          continue;
        }
        if (c == quote &&
            (!triple ||
                (index + 2 < source.length &&
                    source.codeUnitAt(index + 1) == quote &&
                    source.codeUnitAt(index + 2) == quote))) {
          output.write(' ' * delimiterLength);
          index += delimiterLength;
          break;
        }
        output.write(c == lineFeed ? '\n' : ' ');
        index++;
      }
      continue;
    }
    output.writeCharCode(character);
    index++;
  }
  return output.toString();
}

/// Splits [content] into class bodies (by [_classNamePattern], applied to
/// trivia-stripped text — MINOR-1/P10) and returns one [DiscoveredEgressRoute]
/// per body for which [bodyMatches] is true. Shared by the Dio-consuming,
/// ApiClient-consuming and share-initiated walks below — they differ only in
/// what counts as a match inside a body.
List<DiscoveredEgressRoute> _discoverClassesInSource({
  required String content,
  required String relativePath,
  required EgressPatternKind kind,
  required bool Function(String body) bodyMatches,
}) {
  final results = <DiscoveredEgressRoute>[];
  final stripped = _codeWithoutTrivia(content);
  final classMatches = _classNamePattern.allMatches(stripped).toList();
  for (var i = 0; i < classMatches.length; i++) {
    final match = classMatches[i];
    final bodyEnd = i + 1 < classMatches.length
        ? classMatches[i + 1].start
        : stripped.length;
    final body = stripped.substring(match.end, bodyEnd);
    if (!bodyMatches(body)) continue;
    final line = '\n'.allMatches(stripped.substring(0, match.start)).length + 1;
    results.add(
      DiscoveredEgressRoute(
        source: match.group(1)!,
        kind: kind,
        file: relativePath,
        line: line,
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
    final classLevelMatches = _discoverClassesInSource(
      content: content,
      relativePath: relativePath,
      kind: EgressPatternKind.dioConsumingClass,
      bodyMatches: (body) =>
          _dioTypedMemberPattern.hasMatch(body) &&
          _requestVerbCallPattern.hasMatch(body),
    );
    if (classLevelMatches.isNotEmpty) {
      results.addAll(classLevelMatches);
      continue;
    }

    // MINOR-1 file-level fallback: none of the shapes below are a
    // `class Foo { ... }` the walk above can slice — a `mixin`, an
    // `extension on Dio`, a `typedef HttpTransport = Dio`, a top-level
    // function closing over an injected `Dio`, or a `dynamic`-typed
    // client — so require only the two things that are true regardless of
    // shape: the file imports Dio, and it calls a request verb somewhere.
    if (!content.contains("package:dio/dio.dart")) continue;
    final stripped = _codeWithoutTrivia(content);
    if (!_requestVerbCallPattern.hasMatch(stripped)) continue;
    results.add(
      DiscoveredEgressRoute(
        source: 'file:$relativePath',
        kind: EgressPatternKind.dioConsumingClass,
        file: relativePath,
        line: 1,
      ),
    );
  }
  return results;
}

List<DiscoveredEgressRoute> _discoverApiClientConsumingClasses(
  Directory libDir,
  Directory repositoryRoot,
) {
  final results = <DiscoveredEgressRoute>[];
  if (!libDir.existsSync()) return results;
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final relativePath = _relativePath(repositoryRoot, entity.path);
    if (relativePath == 'lib/core/network/api_client.dart') {
      // ApiClient itself — it fields a Dio, not an ApiClient; excluded on
      // principle (it cannot match its own member pattern) and to keep the
      // exclusion symmetric with dioConsumingClassExclusions.
      continue;
    }
    final content = entity.readAsStringSync();
    results.addAll(
      _discoverClassesInSource(
        content: content,
        relativePath: relativePath,
        kind: EgressPatternKind.apiClientConsumingClass,
        bodyMatches: (body) =>
            _apiClientTypedMemberPattern.hasMatch(body) &&
            _apiClientRequestVerbCallPattern.hasMatch(body),
      ),
    );
  }
  return results;
}

List<DiscoveredEgressRoute> _discoverShareInitiatedClasses(
  Directory libDir,
  Directory repositoryRoot,
) {
  final results = <DiscoveredEgressRoute>[];
  if (!libDir.existsSync()) return results;
  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final content = entity.readAsStringSync();
    if (!content.contains('package:share_plus/share_plus.dart')) continue;
    final relativePath = _relativePath(repositoryRoot, entity.path);
    results.addAll(
      _discoverClassesInSource(
        content: content,
        relativePath: relativePath,
        kind: EgressPatternKind.userInitiatedShare,
        bodyMatches: (body) => _sharePlusCallPattern.hasMatch(body),
      ),
    );
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

String _stripLineSuffix(String file) => file.replaceFirst(RegExp(r':\d+$'), '');

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
  final byId = <String, InventoryRoute>{
    for (final route in inventory.routes) route.id: route,
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
    if (entry.fields.isEmpty && entry.rides.trim().isEmpty) {
      violations.add(
        DataInventoryViolation(
          'inventory route "${entry.id}" (${route.source}) has no fields '
          'and no rides target',
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

  // MAJOR-2 — a `rides:` pointer is a machine-checked reference, not a free
  // text field: it must resolve to a real route id, and that route must
  // itself carry at least one field (riding a route that has nothing of its
  // own would just move the "no fields" problem one hop sideways).
  for (final route in inventory.routes) {
    final target = route.rides.trim();
    if (target.isEmpty) continue;
    final targetRoute = byId[target];
    if (targetRoute == null) {
      violations.add(
        DataInventoryViolation(
          'inventory route "${route.id}" has rides: "$target", which is not '
          'a declared route id',
        ),
      );
    } else if (targetRoute.fields.isEmpty) {
      violations.add(
        DataInventoryViolation(
          'inventory route "${route.id}" rides "$target", but "$target" '
          'itself has no fields',
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

/// MINOR-2: re-measures the two files [dioConsumingClassExclusions] blankets
/// out of the class walk, and fails if either file's Dio request-verb
/// call-site count has drifted from [dioConsumingClassExclusionCallSiteCounts]
/// — the "own, narrower check" the exclusion comment promises instead of
/// leaving those two files fully unchecked.
List<DataInventoryViolation> checkExclusionCallSiteDrift(
  Directory repositoryRoot,
) {
  final violations = <DataInventoryViolation>[];
  for (final entry in dioConsumingClassExclusionCallSiteCounts.entries) {
    final file = File('${repositoryRoot.path}/${entry.key}');
    if (!file.existsSync()) continue;
    final stripped = _codeWithoutTrivia(file.readAsStringSync());
    final actual = _requestVerbCallPattern.allMatches(stripped).length;
    if (actual != entry.value) {
      violations.add(
        DataInventoryViolation(
          'excluded file "${entry.key}" now has $actual Dio request-verb '
          'call site(s), but dioConsumingClassExclusionCallSiteCounts pins '
          '${entry.value} — re-measure: either update the pin (if the new '
          'call site is a legitimate, already-covered pass-through) or give '
          'it a proper inventory route',
        ),
      );
    }
  }
  return violations;
}

/// MINOR-4: [InventoryRoute.wired] `false` was previously checked in only
/// ONE direction (above: a `wired: true` claim must be reproducible by the
/// tree). This is the missing other half — if some file OTHER than the
/// route's own declaring file now constructs the route's class, a
/// `wired: false` (and the `leaves_device: false` fields that ride on it)
/// is stale and must flip. Applies only to bare-identifier sources (b/c/d);
/// pattern (a)/(e) sources never carry `wired: false` in this inventory.
List<DataInventoryViolation> checkWiredFalseConstructionSites({
  required Directory repositoryRoot,
  required DataInventory inventory,
}) {
  final violations = <DataInventoryViolation>[];
  final libDir = Directory('${repositoryRoot.path}/lib');
  if (!libDir.existsSync()) return violations;

  final dartFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  for (final route in inventory.routes) {
    if (route.wired) continue;
    if (!_bareIdentifierPattern.hasMatch(route.source)) continue;
    final declaringFile = _stripLineSuffix(route.file);
    final constructionPattern = RegExp(
      '\\b${RegExp.escape(route.source)}\\s*\\(',
    );
    for (final file in dartFiles) {
      final relativePath = _relativePath(repositoryRoot, file.path);
      if (relativePath == declaringFile) continue;
      final stripped = _codeWithoutTrivia(file.readAsStringSync());
      if (!constructionPattern.hasMatch(stripped)) continue;
      violations.add(
        DataInventoryViolation(
          'inventory route "${route.id}" (${route.source}) is marked '
          'wired: false, but $relativePath now constructs '
          '${route.source}(...) outside its declaring file '
          '($declaringFile) — the tree produces this route now; mark '
          'wired: true and re-measure leaves_device',
        ),
      );
      break;
    }
  }
  return violations;
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
    final crossCheck = checkDataInventory(
      discovered: discovered,
      inventory: inventory,
    );
    final violations = <DataInventoryViolation>[
      ...crossCheck.violations,
      ...checkExclusionCallSiteDrift(repositoryRoot),
      ...checkWiredFalseConstructionSites(
        repositoryRoot: repositoryRoot,
        inventory: inventory,
      ),
    ];
    if (violations.isEmpty) {
      stdout.writeln(
        'Data inventory check OK '
        '(${discovered.length} measured egress route(s), '
        '${inventory.routes.length} inventory route(s)).',
      );
    } else {
      final buffer = StringBuffer('Data inventory check failed.');
      for (final violation in violations) {
        buffer
          ..writeln()
          ..write('- ${violation.message}');
      }
      stderr.writeln(buffer.toString());
      exitCode = 1;
    }
  } on FormatException catch (error) {
    stderr.writeln('Data inventory check could not run: $error');
    exitCode = 2;
  }
}
