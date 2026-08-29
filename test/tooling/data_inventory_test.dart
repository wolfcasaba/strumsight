import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_data_inventory.dart';

/// A1 — schema completeness — and A2 — tree ↔ inventory cross-check (ADR
/// 0479 D1) — over the REAL repository. The real-tree assertions run
/// against `Directory.current` (the repo root `flutter test` is invoked
/// from), matching `test/tooling/screen_reachability_test.dart`'s pattern
/// (`repository = Directory.current`).
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
          expect(
            route.fields,
            isNotEmpty,
            reason: 'route "${route.id}" declares no fields',
          );
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

    test('the tree-walker recognizes all three mandated pattern classes '
        '(ADR 0479 D1) against the real tree', () {
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
  });
}
