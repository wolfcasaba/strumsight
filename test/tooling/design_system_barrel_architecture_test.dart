// Regression guard for the E15-R09 / H5 self-heal (ADR 0112, 2026-09-03).
//
// MEASURED ROOT CAUSE. The E13-R02 contract — "real production source reaches
// the design system only via public.dart" — was pinned by exactly one cell,
// `test/core/architecture_dependency_test.dart:754`, which no migration
// round's targeted gate ran. The gate's own `architecture` step
// (`dart run tool/check_architecture.dart`) did not know the rule either.
// So the E15-R09 branch went green on its targeted gate over 24 deep design
// system imports across five migrated Tutor screens, and the breach surfaced
// only in the full CI suite — twice (runs 33707997183, 33711465885), which is
// an H5 halt of the whole round pipeline.
//
// This file feeds the checker the REAL import lines from that failed run (not
// an invented fixture) and asserts the architecture gate now names every one
// of them. It is red without the `designSystemImportsMustUsePublicBarrel`
// rule and green with it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_architecture.dart';

/// The exact deep imports measured on
/// `sonnet-impl/e15-r09-ai-tutor-migration @ 78fd3a64`, grouped by the screen
/// that carried them. Reproduced with:
///
/// ```
/// git show <sha>:lib/features/ai_tutor/presentation/screens/<screen>.dart \
///   | grep design_system
/// ```
const _measuredDeepImports = <String, List<String>>{
  'tutor_home_screen.dart': [
    '../../../../core/design_system/components/actions/ss_button.dart',
    '../../../../core/design_system/components/ai/ss_model_status_card.dart',
    '../../../../core/design_system/components/ai/ss_provenance_badge.dart',
    '../../../../core/design_system/foundations/ss_spacing.dart',
  ],
  'tutor_chat_screen.dart': [
    '../../../../core/design_system/components/ai/ss_provenance_badge.dart',
    '../../../../core/design_system/components/feedback/ss_skeleton.dart',
    '../../../../core/design_system/foundations/ss_colors.dart',
    '../../../../core/design_system/foundations/ss_radius.dart',
    '../../../../core/design_system/foundations/ss_spacing.dart',
    '../../../../core/design_system/foundations/ss_typography.dart',
  ],
  'tutor_data_screen.dart': [
    '../../../../core/design_system/components/actions/ss_button.dart',
    '../../../../core/design_system/components/feedback/failure_presentation.dart',
    '../../../../core/design_system/components/feedback/ss_failure_state.dart',
    '../../../../core/design_system/components/feedback/ss_skeleton.dart',
    '../../../../core/design_system/components/surfaces/ss_card.dart',
    '../../../../core/design_system/foundations/ss_colors.dart',
    '../../../../core/design_system/foundations/ss_spacing.dart',
    '../../../../core/design_system/foundations/ss_typography.dart',
  ],
  'tutor_profile_screen.dart': [
    '../../../../core/design_system/components/actions/ss_button.dart',
    '../../../../core/design_system/components/inputs/ss_validation_summary.dart',
    '../../../../core/design_system/components/surfaces/ss_section.dart',
    '../../../../core/design_system/foundations/ss_spacing.dart',
  ],
  'tutor_privacy_screen.dart': [
    '../../../../core/design_system/components/surfaces/ss_section.dart',
    '../../../../core/design_system/foundations/ss_spacing.dart',
  ],
};

const _screenDirectory = 'lib/features/ai_tutor/presentation/screens';

Directory _fixtureProject(Map<String, List<String>> screens) {
  final root = Directory.systemTemp.createTempSync('ds_barrel_arch_');
  addTearDown(() => root.deleteSync(recursive: true));
  Directory('${root.path}/$_screenDirectory').createSync(recursive: true);
  Directory(
    '${root.path}/lib/core/design_system/foundations',
  ).createSync(recursive: true);
  // The barrel and one internal file have to exist: the checker only reports a
  // dependency it can resolve to a real project-relative path.
  File('${root.path}/lib/core/design_system/public.dart').writeAsStringSync('');
  for (final imports in screens.values) {
    for (final import in imports) {
      final target = File(
        '${root.path}/lib/core/design_system/'
        '${import.split('core/design_system/').last}',
      );
      target.parent.createSync(recursive: true);
      target.writeAsStringSync('');
    }
  }
  screens.forEach((screen, imports) {
    File(
      '${root.path}/$_screenDirectory/$screen',
    ).writeAsStringSync(imports.map((uri) => "import '$uri';").join('\n'));
  });
  return root;
}

List<ArchitectureViolation> _barrelViolations(ArchitectureReport report) =>
    report.violations
        .where(
          (item) =>
              item.rule ==
              ArchitectureRule.designSystemImportsMustUsePublicBarrel,
        )
        .toList();

void main() {
  group('design-system barrel boundary is measured by the architecture gate', () {
    test('every measured E15-R09 deep import is reported as a violation', () {
      final report = checkArchitecture(
        projectRoot: _fixtureProject(_measuredDeepImports),
        allowlist: const <String>{},
      );
      final violations = _barrelViolations(report);

      final expected = <String>[
        for (final entry in _measuredDeepImports.entries)
          for (final uri in entry.value)
            '$_screenDirectory/${entry.key} -> '
                'lib/core/design_system/${uri.split('core/design_system/').last}',
      ];
      expect(violations.map((item) => item.key).toSet(), expected.toSet());
      // 24 measured imports; the count is part of the evidence, not decoration.
      expect(violations, hasLength(24));
      expect(report.unexpectedViolations, isNotEmpty);
      expect(report.isClean, isFalse);
    });

    test('the same screens are clean once they import only public.dart', () {
      final migrated = {
        for (final screen in _measuredDeepImports.keys)
          screen: <String>['../../../../core/design_system/public.dart'],
      };
      final report = checkArchitecture(
        projectRoot: _fixtureProject(migrated),
        allowlist: const <String>{},
      );

      expect(_barrelViolations(report), isEmpty);
      expect(report.isClean, isTrue);
    });

    test('the design system may still reach its own internals', () {
      final root = Directory.systemTemp.createTempSync('ds_barrel_arch_self_');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory(
        '${root.path}/lib/core/design_system/foundations',
      ).createSync(recursive: true);
      File(
        '${root.path}/lib/core/design_system/foundations/ss_spacing.dart',
      ).writeAsStringSync('');
      File(
        '${root.path}/lib/core/design_system/public.dart',
      ).writeAsStringSync("export 'foundations/ss_spacing.dart';");

      expect(
        _barrelViolations(
          checkArchitecture(projectRoot: root, allowlist: const <String>{}),
        ),
        isEmpty,
      );
    });

    test(
      'the real tree is clean — the rule can be enabled without an allowlist',
      () {
        final report = checkArchitecture(projectRoot: Directory.current);

        expect(
          _barrelViolations(report).map((item) => item.key).toList(),
          isEmpty,
        );
      },
    );
  });
}
