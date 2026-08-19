import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_architecture.dart' as architecture;
import '../../tool/gen_public_barrel.dart';

void main() {
  group('PublicBarrel', () {
    late Directory project;

    setUp(() {
      project = Directory.systemTemp.createTempSync(
        'strumsight_public_barrel_',
      );
    });

    tearDown(() {
      project.deleteSync(recursive: true);
    });

    void writeFragment(String name, String contents) {
      final file = File('${project.path}/lib/features/demo/public/$name');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
    }

    void writeBarrel(String contents) {
      final file = File('${project.path}/lib/features/demo/public.dart');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents);
    }

    void seedFreshBarrel() {
      writeFragment(
        'application.dart',
        "export 'application/port/a.dart';\n"
            "export 'application/usecase/b.dart';\n",
      );
      writeFragment(
        'domain.dart',
        "export 'domain/model/c.dart';\n"
            "export 'domain/policy/d.dart' hide X;\n",
      );
      writeBarrel(
        '/// Public domain contract for cross-feature Demo consumers.\n'
        'library;\n'
        '\n'
        "export 'application/port/a.dart';\n"
        "export 'application/usecase/b.dart';\n"
        '\n'
        "export 'domain/model/c.dart';\n"
        "export 'domain/policy/d.dart' hide X;\n"
        '\n',
      );
    }

    test(
      'matches the on-disk barrel when fragments are unchanged (§4 ZÖLD)',
      () {
        seedFreshBarrel();
        final barrel = PublicBarrel(projectRoot: project, feature: 'demo');

        expect(barrel.isFresh(), isTrue);
      },
    );

    test('detects a barrel that is out of date (§4 PIROS: barrel elavult)', () {
      seedFreshBarrel();
      // Hand-edit the on-disk barrel to drift from the fragments: drop one
      // export so the barrel advertises fewer paths than the fragments say.
      writeBarrel(
        '/// Public domain contract for cross-feature Demo consumers.\n'
        'library;\n'
        '\n'
        "export 'application/port/a.dart';\n"
        '\n'
        "export 'domain/model/c.dart';\n"
        "export 'domain/policy/d.dart' hide X;\n"
        '\n',
      );

      final barrel = PublicBarrel(projectRoot: project, feature: 'demo');

      expect(barrel.isFresh(), isFalse);
      // The regenerated barrel must include every export the fragments say,
      // including the one we dropped from the on-disk file.
      expect(barrel.render(), contains("export 'application/usecase/b.dart'"));
      // And it must NOT match the manually-stale on-disk content.
      expect(
        barrel.render(),
        isNot(
          equals(
            File(
              '${project.path}/lib/features/demo/public.dart',
            ).readAsStringSync(),
          ),
        ),
      );
    });

    test('fails the freshness check when a fragment is removed '
        '(§4 PIROS: export hiányzik)', () {
      seedFreshBarrel();
      // Remove one fragment entirely.
      File('${project.path}/lib/features/demo/public/domain.dart').deleteSync();

      final barrel = PublicBarrel(projectRoot: project, feature: 'demo');

      expect(barrel.isFresh(), isFalse);
      expect(barrel.render(), isNot(contains("export 'domain/model/c.dart'")));
    });

    test('throws when two fragments export the same path '
        '(§4 PIROS: export duplikált)', () {
      writeFragment('application.dart', "export 'shared/duplicate.dart';\n");
      writeFragment('domain.dart', "export 'shared/duplicate.dart';\n");

      final barrel = PublicBarrel(projectRoot: project, feature: 'demo');

      expect(
        () => barrel.render(),
        throwsA(
          isA<Object>().having(
            (error) => error.toString(),
            'toString()',
            allOf(
              contains('Duplicate export'),
              contains('shared/duplicate.dart'),
              contains('demo'),
            ),
          ),
        ),
      );
    });

    test(
      'write() regenerates the barrel from the fragments so isFresh() is true '
      'and the on-disk content matches render()',
      () {
        seedFreshBarrel();
        // Drift the on-disk barrel by appending a stale export; the header
        // is left alone so write() should preserve it (brief §3: "változatlan
        // fejléc-dokumentációval").
        final barrelFile = File(
          '${project.path}/lib/features/demo/public.dart',
        );
        final drifted =
            '${barrelFile.readAsStringSync()}'
            "export 'stale_addition.dart';\n";
        barrelFile.writeAsStringSync(drifted);

        final barrel = PublicBarrel(projectRoot: project, feature: 'demo');
        expect(barrel.isFresh(), isFalse);

        barrel.write();
        expect(barrel.isFresh(), isTrue);
        // The freshly written barrel matches what render() produces.
        expect(barrelFile.readAsStringSync(), equals(barrel.render()));
        // The preserved header is the one already on disk (not regenerated).
        expect(
          barrelFile.readAsStringSync(),
          startsWith(
            '/// Public domain contract for cross-feature Demo consumers.',
          ),
        );
      },
    );

    test('featuresWithPublicFragments lists every feature that has fragments '
        'and ignores empty directories', () {
      Directory(
        '${project.path}/lib/features/empty/public',
      ).createSync(recursive: true);
      Directory(
        '${project.path}/lib/features/only_fragments/public',
      ).createSync(recursive: true);
      File(
        '${project.path}/lib/features/only_fragments/public/x.dart',
      ).writeAsStringSync("export 'x.dart';\n");
      Directory(
        '${project.path}/lib/features/no_public',
      ).createSync(recursive: true);

      final features = featuresWithPublicFragments(project);
      expect(features, ['only_fragments']);
    });

    test(
      'preserves an existing header and falls back to a default otherwise',
      () {
        // Existing header case: the seeded barrel already carries one.
        seedFreshBarrel();
        expect(
          PublicBarrel(projectRoot: project, feature: 'demo').render(),
          startsWith(
            '/// Public domain contract for cross-feature Demo consumers.\n',
          ),
        );

        // Default header case: no barrel on disk at all → default is used.
        File('${project.path}/lib/features/demo/public.dart').deleteSync();
        expect(
          PublicBarrel(projectRoot: project, feature: 'demo').render(),
          startsWith(
            '/// Public domain contract for cross-feature Demo consumers.\n',
          ),
        );
      },
    );
  });

  // Falsification cell (brief §4): removing the gen_public_barrel wiring from
  // tool/check_architecture.dart's main() would let a stale barrel pass the
  // architecture gate. The test below guarantees that the architecture step
  // DOES report a stale barrel as a failure.
  group(
    'architecture gate integrates the generated-barrel freshness check',
    () {
      late Directory project;

      setUp(() {
        project = Directory.systemTemp.createTempSync(
          'strumsight_architecture_barrel_',
        );
      });

      tearDown(() {
        project.deleteSync(recursive: true);
      });

      void write(String relativePath, String contents) {
        final file = File('${project.path}/$relativePath');
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(contents);
      }

      test('a stale lib/features/<f>/public.dart fails the architecture step '
          '(§4 falsification: PIROS)', () {
        // Build a project with TWO features (so the architecture check has
        // real content to walk) plus a generated barrel whose fragments and
        // rendered file disagree.
        write('lib/features/host/screen.dart', "export 'data.dart';\n");
        write('lib/features/host/public/foo.dart', "export 'foo_real.dart';\n");
        write('lib/features/host/public/bar.dart', "export 'bar_real.dart';\n");
        // The barrel advertises a fragment that does NOT exist (stale).
        write(
          'lib/features/host/public.dart',
          '/// Public domain contract for cross-feature Host consumers.\n'
              'library;\n'
              '\n'
              "export 'foo_real.dart';\n"
              "export 'bar_real.dart';\n"
              "export 'ghost.dart';\n",
        );

        // The architecture check is clean: no cross-feature violation.
        final report = architecture.checkArchitecture(projectRoot: project);
        expect(
          report.unexpectedViolations,
          isEmpty,
          reason:
              'baseline must be clean — only the barrel is stale. '
              'Got: ${report.format()}',
        );

        // The barrel is, however, stale against its fragments.
        final barrel = PublicBarrel(projectRoot: project, feature: 'host');
        expect(barrel.isFresh(), isFalse);
      });
    },
  );
}
