import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_data_inventory.dart';

/// A1 — schema completeness — and A2 — tree ↔ inventory cross-check (ADR
/// 0479 D1) — over the REAL repository. The real-tree assertions run
/// against `Directory.current` (the repo root `flutter test` is invoked
/// from), matching `test/tooling/screen_reachability_test.dart`'s pattern
/// (`repository = Directory.current`).
///
/// E12-R17 javító kör #1 additions (MAJOR-1/2, MINOR-1..4) use SYNTHETIC
/// temp-directory repos (`_writeTempRepo`) where a cell needs to prove a
/// discovery/check function turns red on a fabricated bad input — the real
/// tree cannot be mutated to manufacture that input (`lib/**` is out of
/// scope for this round), so a throwaway `lib/` under a temp dir stands in
/// for it, mirroring how `DataInventory.parse` is already fed synthetic
/// YAML lines elsewhere in this file for the same reason.
void main() {
  final repository = Directory.current;

  DataInventory realInventory() => DataInventory.parseFile(
    File('${repository.path}/docs/privacy/data-inventory.yaml'),
  );

  group('A1 — every declared field carries purpose, legal_basis, retention, '
      'storage and an explicit leaves_device verdict', () {
    test(
      'the real docs/privacy/data-inventory.yaml has no incomplete field',
      () {
        final inventory = realInventory();
        expect(inventory.routes, isNotEmpty);

        final incomplete = <String>[];
        for (final route in inventory.routes) {
          expect(
            route.consentSwitch.trim(),
            isNotEmpty,
            reason: 'route "${route.id}" has no consent_switch',
          );
          if (route.rides.trim().isEmpty) {
            expect(
              route.fields,
              isNotEmpty,
              reason: 'route "${route.id}" declares no fields and no rides',
            );
          }
          for (final field in route.fields) {
            final missing = field.missingAttributes();
            if (missing.isNotEmpty) {
              incomplete.add(
                '${route.id}/${field.name}: ${missing.join(', ')}',
              );
            }
          }
        }
        expect(incomplete, isEmpty, reason: incomplete.join('\n'));
      },
    );

    // The KÖTELEZŐ real-violation probe (brief §6.1/§7): drop one required
    // attribute out of a copy of a real field and prove the SAME assertion
    // this cell runs turns red — proving A1 actually inspects the
    // attributes instead of trivially passing on any input.
    test('a field missing purpose is reported as incomplete', () {
      final broken = DataInventory.parse(const <String>[
        'routes:',
        '  - id: fixture_route',
        '    source: "FixtureRoute"',
        '    file: "lib/fixture.dart:1"',
        '    wired: false',
        '    gate: "none"',
        '    consent_switch: "none"',
        '    fields:',
        '      - name: "fixture_field"',
        '        purpose: ""',
        '        legal_basis: "consent"',
        '        retention: "n/a"',
        '        storage: "device"',
        '        leaves_device: false',
      ]);

      final field = broken.routes.single.fields.single;
      expect(field.missingAttributes(), ['purpose']);
    });

    test(
      'a field missing the leaves_device line is reported as incomplete',
      () {
        final broken = DataInventory.parse(const <String>[
          'routes:',
          '  - id: fixture_route',
          '    source: "FixtureRoute"',
          '    file: "lib/fixture.dart:1"',
          '    wired: false',
          '    gate: "none"',
          '    consent_switch: "none"',
          '    fields:',
          '      - name: "fixture_field"',
          '        purpose: "fixture purpose"',
          '        legal_basis: "consent"',
          '        retention: "n/a"',
          '        storage: "device"',
        ]);

        final field = broken.routes.single.fields.single;
        expect(field.missingAttributes(), ['leaves_device']);
      },
    );
  });

  group('MINOR-3 — leaves_device / wired accept ONLY the literals "true" or '
      '"false" (fail-open guard)', () {
    test('leaves_device: True (capitalized) is a hard parse failure, not a '
        'silent false', () {
      expect(
        () => DataInventory.parse(const <String>[
          'routes:',
          '  - id: fixture_route',
          '    source: "FixtureRoute"',
          '    file: "lib/fixture.dart:1"',
          '    wired: false',
          '    gate: "none"',
          '    consent_switch: "none"',
          '    fields:',
          '      - name: "fixture_field"',
          '        purpose: "p"',
          '        legal_basis: "consent"',
          '        retention: "n/a"',
          '        storage: "device"',
          '        leaves_device: True',
        ]),
        throwsFormatException,
      );
    });

    test('wired: True (capitalized) is a hard parse failure', () {
      expect(
        () => DataInventory.parse(const <String>[
          'routes:',
          '  - id: fixture_route',
          '    source: "FixtureRoute"',
          '    file: "lib/fixture.dart:1"',
          '    wired: True',
          '    gate: "none"',
          '    consent_switch: "none"',
          '    fields:',
          '      - name: "fixture_field"',
          '        purpose: "p"',
          '        legal_basis: "consent"',
          '        retention: "n/a"',
          '        storage: "device"',
          '        leaves_device: false',
        ]),
        throwsFormatException,
      );
    });

    test('the lowercase literals still parse cleanly (no regression)', () {
      final inventory = DataInventory.parse(const <String>[
        'routes:',
        '  - id: fixture_route',
        '    source: "FixtureRoute"',
        '    file: "lib/fixture.dart:1"',
        '    wired: true',
        '    gate: "none"',
        '    consent_switch: "none"',
        '    fields:',
        '      - name: "fixture_field"',
        '        purpose: "p"',
        '        legal_basis: "consent"',
        '        retention: "n/a"',
        '        storage: "device"',
        '        leaves_device: false',
      ]);
      expect(inventory.routes.single.wired, isTrue);
      expect(inventory.routes.single.fields.single.leavesDevice, isFalse);
    });
  });

  group('A2 — every egress route the FA measures has a leltár entry (ADR '
      '0479 D1)', () {
    test('the real lib/** tree is fully covered by the real inventory', () {
      final discovered = discoverEgressRoutes(repository);
      final inventory = realInventory();
      final report = checkDataInventory(
        discovered: discovered,
        inventory: inventory,
      );

      expect(
        report.isClean,
        isTrue,
        reason: report.violations.map((v) => v.message).join('\n'),
      );
    });

    test('the tree-walker recognizes all five mandated pattern classes '
        '(ADR 0479 D1 + E12-R17 javító kör #1 MAJOR-1/2) against the real '
        'tree', () {
      final discovered = discoverEgressRoutes(repository);
      final kinds = discovered.map((r) => r.kind).toSet();

      // Pattern (a): DioFactory.create*Client.
      expect(kinds, contains(EgressPatternKind.dioFactoryMethod));
      expect(
        discovered.map((r) => r.source),
        containsAll(<String>[
          'DioFactory.createAccountClient',
          'DioFactory.createDiagnosticsClient',
        ]),
      );

      // Pattern (b): the L140 blind spot — an injected Dio, never
      // constructed via `Dio(`, that DioFactory never sees.
      expect(kinds, contains(EgressPatternKind.dioConsumingClass));
      expect(
        discovered.map((r) => r.source),
        containsAll(<String>[
          'HttpTutorStreamTransport',
          'CommunityMediaUploader',
        ]),
      );

      // Pattern (c), MAJOR-2: an ApiClient-typed field/param + a
      // request-verb call — the tree's most common sender shape.
      expect(kinds, contains(EgressPatternKind.apiClientConsumingClass));
      expect(
        discovered
            .where((r) => r.kind == EgressPatternKind.apiClientConsumingClass)
            .map((r) => r.source),
        unorderedEquals(<String>[
          'HttpAuthRepository',
          'HttpSettingsRepository',
          'HttpCommunityProfileRepository',
          'HttpSocialGraphRepository',
          'HttpCommunityChallengeRepository',
          'DiagnosticsUploader',
        ]),
      );

      // Pattern (d), MAJOR-1: a share_plus share-sheet call.
      expect(kinds, contains(EgressPatternKind.userInitiatedShare));
      expect(
        discovered
            .where((r) => r.kind == EgressPatternKind.userInitiatedShare)
            .map((r) => r.source),
        contains('ShareService'),
      );
    });

    // The KÖTELEZŐ real-violation probe for A2: take the REAL measured
    // routes, drop one from a COPY of the real inventory, and prove the
    // SAME check function the cell above runs turns red — showing the
    // checker starts from the tree, not from the inventory (ADR 0479 D1's
    // explicitly forbidden weakening).
    test('dropping one real, wired route out of a copy of the inventory turns '
        'this cell red', () {
      final discovered = discoverEgressRoutes(repository);
      final inventory = realInventory();
      final target = inventory.routes.firstWhere((r) => r.wired);
      final withoutTarget = DataInventory(
        inventory.routes.where((r) => r.id != target.id).toList(),
      );

      final report = checkDataInventory(
        discovered: discovered,
        inventory: withoutTarget,
      );

      expect(report.isClean, isFalse);
      expect(
        report.violations.map((v) => v.message).join('\n'),
        contains(target.source),
      );
    });

    // A checker that only validated the inventory's OWN route list (never
    // consulting the tree) would stay green forever, including after a new,
    // completely undeclared HTTP-touching class appears. Prove the checker
    // does NOT have that shape by handing it a discovered route the real
    // inventory has never heard of.
    test('a discovered route absent from the inventory turns the check red '
        'even though every existing inventory route is complete', () {
      final inventory = realInventory();
      final phantom = DiscoveredEgressRoute(
        source: 'SomeNewUploader',
        kind: EgressPatternKind.dioConsumingClass,
        file: 'lib/features/fixture/some_new_uploader.dart',
        line: 10,
      );

      // Every REAL route stays satisfied (so no `wired: true` stale-entry
      // noise) — only the phantom, undeclared route is unmatched.
      final report = checkDataInventory(
        discovered: [...discoverEgressRoutes(repository), phantom],
        inventory: inventory,
      );

      expect(report.isClean, isFalse);
      expect(
        report.violations.map((v) => v.message).join('\n'),
        contains('SomeNewUploader'),
      );
    });

    test('a wired:true inventory route the tree no longer produces turns the '
        'check red (stale-entry protection)', () {
      final stale = DataInventory.parse(const <String>[
        'routes:',
        '  - id: ghost_route',
        '    source: "GhostRoute"',
        '    file: "lib/ghost.dart:1"',
        '    wired: true',
        '    gate: "none"',
        '    consent_switch: "none"',
        '    fields:',
        '      - name: "ghost_field"',
        '        purpose: "p"',
        '        legal_basis: "consent"',
        '        retention: "n/a"',
        '        storage: "device"',
        '        leaves_device: false',
      ]);

      final report = checkDataInventory(discovered: const [], inventory: stale);

      expect(report.isClean, isFalse);
      expect(report.violations.single.message, contains('GhostRoute'));
    });
  });

  group('MAJOR-2 — a `rides:` route is a machine-checked reference, not '
      'free text', () {
    test('every real rides: target resolves to a route id with fields', () {
      final inventory = realInventory();
      final byId = {for (final r in inventory.routes) r.id: r};
      final riders = inventory.routes.where((r) => r.rides.trim().isNotEmpty);
      expect(riders, isNotEmpty);
      for (final rider in riders) {
        final target = byId[rider.rides];
        expect(
          target,
          isNotNull,
          reason: '"${rider.id}" rides unknown id "${rider.rides}"',
        );
        expect(
          target!.fields,
          isNotEmpty,
          reason:
              '"${rider.id}" rides "${rider.rides}", which has no '
              'fields of its own',
        );
      }
    });

    test('a rides: pointer to an unknown route id turns the check red', () {
      final inventory = DataInventory.parse(const <String>[
        'routes:',
        '  - id: rider_route',
        '    source: "RiderRoute"',
        '    file: "lib/fixture.dart:1"',
        '    wired: true',
        '    gate: "none"',
        '    consent_switch: "rides nonexistent_target"',
        '    rides: nonexistent_target',
        '    fields:',
      ]);
      final discovered = [
        const DiscoveredEgressRoute(
          source: 'RiderRoute',
          kind: EgressPatternKind.apiClientConsumingClass,
          file: 'lib/fixture.dart',
          line: 1,
        ),
      ];
      final report = checkDataInventory(
        discovered: discovered,
        inventory: inventory,
      );
      expect(report.isClean, isFalse);
      expect(
        report.violations.map((v) => v.message).join('\n'),
        contains('nonexistent_target'),
      );
    });

    test('a rides: pointer to a route that itself has no fields turns the '
        'check red (cannot ride a fieldless rider)', () {
      final inventory = DataInventory.parse(const <String>[
        'routes:',
        '  - id: empty_target',
        '    source: "EmptyTarget"',
        '    file: "lib/fixture.dart:1"',
        '    wired: true',
        '    gate: "none"',
        '    consent_switch: "rides rider_route"',
        '    rides: rider_route',
        '    fields:',
        '  - id: rider_route',
        '    source: "RiderRoute"',
        '    file: "lib/fixture2.dart:1"',
        '    wired: true',
        '    gate: "none"',
        '    consent_switch: "rides empty_target"',
        '    rides: empty_target',
        '    fields:',
      ]);
      final discovered = [
        const DiscoveredEgressRoute(
          source: 'EmptyTarget',
          kind: EgressPatternKind.apiClientConsumingClass,
          file: 'lib/fixture.dart',
          line: 1,
        ),
        const DiscoveredEgressRoute(
          source: 'RiderRoute',
          kind: EgressPatternKind.apiClientConsumingClass,
          file: 'lib/fixture2.dart',
          line: 1,
        ),
      ];
      final report = checkDataInventory(
        discovered: discovered,
        inventory: inventory,
      );
      expect(report.isClean, isFalse);
      expect(
        report.violations.map((v) => v.message).join('\n'),
        contains('no fields'),
      );
    });
  });

  group('DioFactory-centric weakening is rejected by construction '
      '(dioConsumingClassExclusions)', () {
    test('the exclusion list only names the two documented infra files', () {
      expect(
        dioConsumingClassExclusions.keys,
        unorderedEquals(<String>[
          'lib/core/network/dio_factory.dart',
          'lib/core/network/api_client.dart',
        ]),
      );
      for (final reason in dioConsumingClassExclusions.values) {
        expect(reason.trim(), isNotEmpty);
      }
    });

    test('MINOR-2: the call-site-count pin covers exactly the same two '
        'files', () {
      expect(
        dioConsumingClassExclusionCallSiteCounts.keys,
        unorderedEquals(dioConsumingClassExclusions.keys),
      );
    });

    test('MINOR-2: the real two excluded files match their pinned '
        'call-site count today', () {
      final violations = checkExclusionCallSiteDrift(repository);
      expect(
        violations,
        isEmpty,
        reason: violations.map((v) => v.message).join('\n'),
      );
    });

    test('MINOR-2: a NEW Dio call site added to an excluded file turns the '
        'drift check red', () {
      final temp = _writeTempRepo({
        'lib/core/network/api_client.dart': '''
import 'package:dio/dio.dart';

final class ApiClient {
  ApiClient(this._dio);
  final Dio _dio;

  Future<void> post(String path) => _dio.post(path);

  // MINOR-2 regression fixture: a second, hardcoded call site the pin
  // does not expect.
  Future<void> exfil() => _dio.post('/exfil');
}
''',
      });
      addTearDown(() => temp.deleteSync(recursive: true));

      final violations = checkExclusionCallSiteDrift(temp);
      expect(violations, isNotEmpty);
      expect(
        violations.map((v) => v.message).join('\n'),
        contains('api_client.dart'),
      );
    });
  });

  group('MAJOR-2 — the ApiClient-consuming walk is a real discovery, not a '
      'hardcoded list', () {
    test('a synthetic class fielding an ApiClient and calling a request '
        'verb is discovered as apiClientConsumingClass', () {
      final temp = _writeTempRepo({
        'lib/features/fixture/some_new_repository.dart': '''
import '../../core/network/api_client.dart';

class SomeNewRepository {
  SomeNewRepository(this._client);
  final ApiClient _client;

  Future<void> push(Map<String, Object?> body) =>
      _client.postJson('/fixture', data: body, decode: (j) => j);
}
''',
      });
      addTearDown(() => temp.deleteSync(recursive: true));

      final discovered = discoverEgressRoutes(temp);
      expect(
        discovered.where(
          (r) =>
              r.kind == EgressPatternKind.apiClientConsumingClass &&
              r.source == 'SomeNewRepository',
        ),
        isNotEmpty,
      );

      // ...and an inventory that has never heard of it turns the check red —
      // the exact regression MAJOR-2 measured (a brand-new ApiClient
      // consumer producing ZERO new discovered routes).
      final inventory = DataInventory.parse(const <String>[
        'routes:',
        '  - id: unrelated',
        '    source: "Unrelated"',
        '    file: "lib/unrelated.dart:1"',
        '    wired: false',
        '    gate: "none"',
        '    consent_switch: "none"',
        '    fields:',
        '      - name: "f"',
        '        purpose: "p"',
        '        legal_basis: "consent"',
        '        retention: "n/a"',
        '        storage: "device"',
        '        leaves_device: false',
      ]);
      final report = checkDataInventory(
        discovered: discovered,
        inventory: inventory,
      );
      expect(report.isClean, isFalse);
      expect(
        report.violations.map((v) => v.message).join('\n'),
        contains('SomeNewRepository'),
      );
    });

    test('a class fielding an ApiClient but never calling a request verb is '
        'NOT discovered (no false positive)', () {
      final temp = _writeTempRepo({
        'lib/features/fixture/inert.dart': '''
import '../../core/network/api_client.dart';

class InertHolder {
  InertHolder(this._client);
  final ApiClient _client;

  ApiClient get client => _client;
}
''',
      });
      addTearDown(() => temp.deleteSync(recursive: true));

      final discovered = discoverEgressRoutes(temp);
      expect(discovered.map((r) => r.source), isNot(contains('InertHolder')));
    });
  });

  group('MINOR-1 — the Dio-consuming walk is resilient to comment-splitting '
      'and a wider verb surface', () {
    test('a .patch( call on an injected Dio is discovered (verb-list '
        'expansion)', () {
      final temp = _writeTempRepo({
        'lib/features/fixture/patcher.dart': '''
import 'package:dio/dio.dart';

class Patcher {
  Patcher(this._dio);
  final Dio _dio;

  Future<void> patchThing(String id) => _dio.patch('/things/\$id');
}
''',
      });
      addTearDown(() => temp.deleteSync(recursive: true));

      final discovered = discoverEgressRoutes(temp);
      expect(
        discovered
            .where((r) => r.kind == EgressPatternKind.dioConsumingClass)
            .map((r) => r.source),
        contains('Patcher'),
      );
    });

    // P10: a doc-comment mid-body that merely CONTAINS the word "class"
    // (e.g. "// this class is not thread-safe") previously matched
    // _classNamePattern itself, silently splitting the real class's body in
    // two so neither half carried both the Dio member and the verb call —
    // the real sender vanished from the inventory with NO error. This is
    // the exact shape measured in the real tree's
    // community_media_uploader.dart (harmless there only because that class
    // happens to be the last one in its file); this fixture reproduces it
    // where it WOULD have hidden the class.
    test('a mid-body comment containing the word "class" does not split '
        'the real class and hide its Dio member from its verb call (P10)', () {
      final temp = _writeTempRepo({
        'lib/features/fixture/real_sender.dart': '''
import 'package:dio/dio.dart';

/// A new sender instance is created per attempt — the
/// class is NOT thread-safe, callers must not share it.
final class RealSender {
  RealSender(this._dio);

  final Dio _dio;

  Future<void> send() => _dio.post('/x');
}
''',
      });
      addTearDown(() => temp.deleteSync(recursive: true));

      final discovered = discoverEgressRoutes(temp);
      expect(
        discovered
            .where((r) => r.kind == EgressPatternKind.dioConsumingClass)
            .map((r) => r.source),
        contains('RealSender'),
      );
    });

    // MINOR-1 file-level fallback: shapes that are not `class Foo { ... }`
    // at all (here, a top-level function closing over an injected Dio) are
    // invisible to the class-body walk by construction — the fallback nets
    // them by file (Dio import + a verb call anywhere in the file).
    test('a top-level function closing over an injected Dio is caught by '
        'the file-level fallback, not silently dropped', () {
      final temp = _writeTempRepo({
        'lib/features/fixture/top_level_sender.dart': '''
import 'package:dio/dio.dart';

Future<void> sendViaTopLevelFunction(Dio dio, String path) =>
    dio.post(path);
''',
      });
      addTearDown(() => temp.deleteSync(recursive: true));

      final discovered = discoverEgressRoutes(temp);
      expect(
        discovered.where(
          (r) =>
              r.kind == EgressPatternKind.dioConsumingClass &&
              r.source == 'file:lib/features/fixture/top_level_sender.dart',
        ),
        isNotEmpty,
      );
    });

    test('a file that imports Dio but never calls a request verb produces '
        'no fallback route (no false positive)', () {
      final temp = _writeTempRepo({
        'lib/features/fixture/dio_type_only.dart': '''
import 'package:dio/dio.dart';

typedef DioProvider = Dio Function();
''',
      });
      addTearDown(() => temp.deleteSync(recursive: true));

      final discovered = discoverEgressRoutes(temp);
      expect(discovered, isEmpty);
    });
  });

  group('MINOR-4 — wired: false is checked in BOTH directions', () {
    test('the real two wired:false routes (tutor_stream, community_media) '
        'have no construction site anywhere else in lib/** today', () {
      final violations = checkWiredFalseConstructionSites(
        repositoryRoot: repository,
        inventory: realInventory(),
      );
      expect(
        violations,
        isEmpty,
        reason: violations.map((v) => v.message).join('\n'),
      );
    });

    test('a construction site appearing OUTSIDE the declaring file for a '
        'wired:false route turns the check red', () {
      final temp = _writeTempRepo({
        'lib/features/fixture/ghost_gateway.dart': '''
class GhostGateway {
  GhostGateway();
}
''',
        'lib/features/fixture/wires_it_up.dart': '''
import 'ghost_gateway.dart';

void boot() {
  GhostGateway();
}
''',
      });
      addTearDown(() => temp.deleteSync(recursive: true));

      final inventory = DataInventory.parse(const <String>[
        'routes:',
        '  - id: ghost_gateway',
        '    source: "GhostGateway"',
        '    file: "lib/features/fixture/ghost_gateway.dart:1"',
        '    wired: false',
        '    gate: "none"',
        '    consent_switch: "none"',
        '    fields:',
        '      - name: "f"',
        '        purpose: "p"',
        '        legal_basis: "consent"',
        '        retention: "n/a"',
        '        storage: "device"',
        '        leaves_device: false',
      ]);

      final violations = checkWiredFalseConstructionSites(
        repositoryRoot: temp,
        inventory: inventory,
      );
      expect(violations, isNotEmpty);
      expect(
        violations.single.message,
        allOf(contains('ghost_gateway'), contains('wires_it_up.dart')),
      );
    });

    test('a construction site INSIDE the declaring file only (the class '
        "own constructor) does NOT turn the check red", () {
      final temp = _writeTempRepo({
        'lib/features/fixture/ghost_gateway.dart': '''
class GhostGateway {
  GhostGateway();
}
''',
      });
      addTearDown(() => temp.deleteSync(recursive: true));

      final inventory = DataInventory.parse(const <String>[
        'routes:',
        '  - id: ghost_gateway',
        '    source: "GhostGateway"',
        '    file: "lib/features/fixture/ghost_gateway.dart:1"',
        '    wired: false',
        '    gate: "none"',
        '    consent_switch: "none"',
        '    fields:',
        '      - name: "f"',
        '        purpose: "p"',
        '        legal_basis: "consent"',
        '        retention: "n/a"',
        '        storage: "device"',
        '        leaves_device: false',
      ]);

      final violations = checkWiredFalseConstructionSites(
        repositoryRoot: temp,
        inventory: inventory,
      );
      expect(violations, isEmpty);
    });
  });
}

/// Writes [files] (relative path → content) under a fresh temp directory and
/// returns its root, so discovery/check functions that require an actual
/// `Directory` (they walk `lib/**` on disk) can be exercised against a
/// synthetic fixture without touching the real `lib/**` tree — this round's
/// hard constraint (E12-R17 javító kör #1 §2).
Directory _writeTempRepo(Map<String, String> files) {
  final root = Directory.systemTemp.createTempSync('data_inventory_test_');
  for (final entry in files.entries) {
    final file = File('${root.path}/${entry.key}');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }
  return root;
}
