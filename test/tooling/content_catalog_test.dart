// Content-catalog inventory gate (E12-R21, ADR 0485).
//
// Follows the `test/tooling/security_scan_test.dart` / `device_matrix_test.dart`
// pattern: a Dart gate test that shells out to `python3 tool/validate_
// content_catalog.py` against BOTH temporary, fully-isolated fixtures (so a
// weak implementation is provably caught turning RED, not just "the real
// tree happens to be green today" — the E12-R18/R19/R20 MAJOR class,
// docs/LESSONS.md L566) and the real tree (so the shipped
// `docs/content/catalog-inventory.yaml` is proven to mirror the real
// sources). `--practice-catalog`/`--knowledge-manifest`/etc. let a test
// override exactly one source file while every other flag defaults to the
// real repo path — the fixture-isolated tests below instead override every
// flag, so each fixture's `python3` run measures ONLY the fixture content,
// never real-tree noise.
//
// A4's four R5 invariants are measured directly against the REAL `Lessons`/
// `SkillTaxonomy` Dart objects (ADR 0485 D5) — not through the Python
// validator, which has no hibakód for a skill-graph mismatch (brief §3.3's
// code list is closed at ten entries, none of them skill-graph shaped).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/domain/models/skill_node.dart';
import 'package:strumsight/features/learn/model/lesson.dart';
import 'package:strumsight/features/learn/providers/lesson_progress_provider.dart';

import '../support/preference_store.dart';

const _tool = 'tool/validate_content_catalog.py';
const _thisFile = 'test/tooling/content_catalog_test.dart';
const _todayIso = '2026-09-01';
const _realInventory = 'docs/content/catalog-inventory.yaml';

class _Result {
  _Result(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}

_Result _run(List<String> args) {
  final result = Process.runSync('python3', [_tool, ...args]);
  return _Result(
    result.exitCode,
    result.stdout.toString(),
    result.stderr.toString(),
  );
}

/// A fully-isolated fixture root: every source file the validator reads is
/// a fixture under [root], never a real repo file — so a fixture test's
/// findings are exactly and only what that test's mutation introduces.
class _Fixture {
  _Fixture(this.root)
    : practiceCatalog = File('${root.path}/practice_catalog.dart'),
      knowledgeManifest = File('${root.path}/manifest.json'),
      knowledgeAssetsRoot = Directory('${root.path}/knowledge_assets'),
      lessonSource = File('${root.path}/lesson.dart'),
      legacyMappingSource = File('${root.path}/legacy_mapping_table.dart'),
      knowledgeSkillEnumSource = File('${root.path}/knowledge_document.dart'),
      arbEn = File('${root.path}/app_en.arb'),
      arbHu = File('${root.path}/app_hu.arb'),
      inventory = File('${root.path}/catalog-inventory.yaml');

  final Directory root;
  final File practiceCatalog;
  final File knowledgeManifest;
  final Directory knowledgeAssetsRoot;
  final File lessonSource;
  final File legacyMappingSource;
  final File knowledgeSkillEnumSource;
  final File arbEn;
  final File arbHu;
  final File inventory;

  List<String> args({String? inventoryOverride}) => [
    '--inventory',
    inventoryOverride ?? inventory.path,
    '--today',
    _todayIso,
    '--practice-catalog',
    practiceCatalog.path,
    '--knowledge-manifest',
    knowledgeManifest.path,
    '--knowledge-assets-root',
    knowledgeAssetsRoot.path,
    '--lesson-source',
    lessonSource.path,
    '--legacy-mapping-source',
    legacyMappingSource.path,
    '--knowledge-skill-enum-source',
    knowledgeSkillEnumSource.path,
    '--arb-en',
    arbEn.path,
    '--arb-hu',
    arbHu.path,
  ];
}

const _baselinePracticeCatalog = '''
final List<PracticeDefinition> _fixtureDefinitions = [
  PracticeDefinition(
    id: 'fixture.alpha.v1',
    schemaVersion: 1,
    titleKey: 'fixtureAlphaTitle',
    descriptionKey: 'fixtureAlphaDescription',
    mode: PracticeMode.strumPattern,
    source: PracticeSource.builtin,
    skillTags: const ['tagA', 'tagShared'],
  ),
  PracticeDefinition(
    id: 'fixture.beta.v1',
    schemaVersion: 1,
    titleKey: 'fixtureBetaTitle',
    descriptionKey: 'fixtureBetaDescription',
    mode: PracticeMode.strumPattern,
    source: PracticeSource.builtin,
    difficulty: PracticeDifficulty.intermediate,
    skillTags: const ['tagB', 'tagShared'],
  ),
];
''';

const _extraGammaDefinition = '''
  PracticeDefinition(
    id: 'fixture.gamma.v1',
    schemaVersion: 1,
    titleKey: 'fixtureGammaTitle',
    descriptionKey: 'fixtureGammaDescription',
    mode: PracticeMode.strumPattern,
    source: PracticeSource.builtin,
    skillTags: const ['tagGamma'],
  ),
];
''';

const _baselineManifest = '''
{
  "schemaVersion": 1,
  "documents": [
    {"id": "sample-en", "locale": "en", "skill": "rhythm", "difficulty": "beginner", "license": "CC0-1.0", "version": 1, "contentHash": "deadbeef", "sourcePath": "en/sample-en.json"},
    {"id": "sample-hu", "locale": "hu", "skill": "rhythm", "difficulty": "beginner", "license": "CC0-1.0", "version": 1, "contentHash": "deadbeef", "sourcePath": "hu/sample-hu.json"}
  ]
}
''';

const _baselineLessonSource = '''
class Lessons {
  static Lesson get firstWin => Lesson(
    id: 'fixture-first-win',
    name: 'Fixture First Win',
    bpm: 70,
  );

  static Lesson get lessonAlpha => Lesson(
    id: 'lesson-alpha',
    name: 'Lesson Alpha',
    bpm: 70,
  );

  static Lesson get lessonBeta => Lesson(
    id: 'lesson-beta',
    name: 'Lesson Beta',
    bpm: 80,
    difficulty: Difficulty.intermediate,
  );

  static List<Lesson> get all => [
    lessonAlpha,
    lessonBeta,
  ];
}
''';

const _baselineLegacyMapping = '''
final legacyMapping = [
  LegacySkillMapping(lessonId: 'lesson-alpha', skillId: 'legacy.tagX'),
];
''';

const _baselineKnowledgeEnum = 'enum KnowledgeSkill { rhythm, chord }\n';

const _extendedKnowledgeEnum =
    'enum KnowledgeSkill { rhythm, chord, technique }\n';

const _baselineArb = '''
{
  "fixtureAlphaTitle": "Alpha",
  "fixtureAlphaDescription": "Alpha description",
  "fixtureBetaTitle": "Beta",
  "fixtureBetaDescription": "Beta description"
}
''';

String _baselineInventory({String expiry = '2026-12-31'}) =>
    '''
schema_version: 1
content_package_version: "fixture-1"

items:
  - id: fixture.alpha.v1
    source: practice_engine
    difficulty: beginner
    skill_tags: [tagA, tagShared]
    locales: [en, hu]
    version: 1
  - id: fixture.beta.v1
    source: practice_engine
    difficulty: intermediate
    skill_tags: [tagB, tagShared]
    locales: [en, hu]
    version: 1
  - id: sample-en
    source: tutor_knowledge
    difficulty: beginner
    skill_tags: [rhythm]
    locales: [en]
    version: 1
  - id: sample-hu
    source: tutor_knowledge
    difficulty: beginner
    skill_tags: [rhythm]
    locales: [hu]
    version: 1
  - id: fixture-first-win
    source: learn_lessons
    difficulty: beginner
    skill_tags: []
    locales: [en]
    version: 1
  - id: lesson-alpha
    source: learn_lessons
    difficulty: beginner
    skill_tags: []
    locales: [en]
    version: 1
  - id: lesson-beta
    source: learn_lessons
    difficulty: intermediate
    skill_tags: []
    locales: [en]
    version: 1

skill_vocabularies:
  practice_engine: [tagA, tagB, tagShared]
  tutor_knowledge: [chord, rhythm]
  legacy_mapping_table: [legacy.tagX]

skill_graph:

known_exceptions:
  - id: fixture-learn-lessons-name-locale
    reason: Fixture lessons have no hu name surface, mirroring the real R4 gap.
    owner: fixture-owner
    expiry: $expiry
    suppresses: locale:learn_lessons:name
''';

_Fixture _writeBaseline(Directory root, {String expiry = '2026-12-31'}) {
  final fixture = _Fixture(root);
  fixture.practiceCatalog.writeAsStringSync(_baselinePracticeCatalog);
  fixture.knowledgeManifest.writeAsStringSync(_baselineManifest);
  File(
    '${fixture.knowledgeAssetsRoot.path}/en/sample-en.json',
  ).createSync(recursive: true);
  File(
    '${fixture.knowledgeAssetsRoot.path}/hu/sample-hu.json',
  ).createSync(recursive: true);
  fixture.lessonSource.writeAsStringSync(_baselineLessonSource);
  fixture.legacyMappingSource.writeAsStringSync(_baselineLegacyMapping);
  fixture.knowledgeSkillEnumSource.writeAsStringSync(_baselineKnowledgeEnum);
  fixture.arbEn.writeAsStringSync(_baselineArb);
  fixture.arbHu.writeAsStringSync(_baselineArb);
  fixture.inventory.writeAsStringSync(_baselineInventory(expiry: expiry));
  return fixture;
}

void main() {
  late Directory fixtureRoot;

  setUp(() {
    fixtureRoot = Directory.systemTemp.createTempSync(
      'strumsight_content_catalog_',
    );
  });
  tearDown(() => fixtureRoot.deleteSync(recursive: true));

  group('baseline fixture is self-consistent', () {
    test('a fully-isolated fixture with nothing mutated is exit 0', () {
      final fixture = _writeBaseline(fixtureRoot);
      final result = _run(fixture.args());
      expect(result.exitCode, 0, reason: result.stdout);
      expect(result.stdout.trim(), isEmpty);
    });
  });

  group('A1 — the validator starts from the SOURCE (D1 missing direction)', () {
    test('the real tree: all three measured sources are exit 0 (10 practice + '
        '10 knowledge + 16 lessons + first-win all mirrored)', () {
      final result = _run([
        '--inventory',
        _realInventory,
        '--today',
        _todayIso,
      ]);
      expect(result.exitCode, 0, reason: result.stdout);
      expect(result.stdout.trim(), isEmpty);
    });

    test('fixture: a practice-engine definition that exists in the source but '
        'not the inventory → missing_inventory_entry, non-zero exit', () {
      final fixture = _writeBaseline(fixtureRoot);
      final mutated = File('${fixtureRoot.path}/practice_catalog_gamma.dart')
        ..writeAsStringSync(
          _baselinePracticeCatalog.replaceFirst('];\n', _extraGammaDefinition),
        );
      final args = fixture.args();
      args[args.indexOf(fixture.practiceCatalog.path)] = mutated.path;
      final result = _run(args);
      expect(result.exitCode, isNot(0));
      expect(
        result.stdout,
        contains('missing_inventory_entry: practice_engine:fixture.gamma.v1'),
      );
    });

    test('fixture: an inventory line whose source element no longer exists → '
        'stale_inventory_entry, non-zero exit', () {
      final fixture = _writeBaseline(fixtureRoot);
      fixture.inventory.writeAsStringSync(
        _baselineInventory().replaceFirst(
          '  - id: fixture.beta.v1\n',
          '  - id: fixture.beta.v1\n'
              '  - id: fixture.ghost.v1\n'
              '    source: practice_engine\n'
              '    difficulty: beginner\n'
              '    skill_tags: []\n'
              '    locales: [en]\n'
              '    version: 1\n',
        ),
      );
      final result = _run(fixture.args());
      expect(result.exitCode, isNot(0));
      expect(
        result.stdout,
        contains('stale_inventory_entry: practice_engine:fixture.ghost.v1'),
      );
    });
  });

  group('A2 — a broken reference BLOCKS (D2)', () {
    test('the real tree: every LegacyMappingTable.builtIn lessonId and every '
        'tutor-knowledge sourcePath resolve — no broken_reference', () {
      final result = _run([
        '--inventory',
        _realInventory,
        '--today',
        _todayIso,
      ]);
      expect(result.stdout, isNot(contains('broken_reference')));
    });

    test('fixture: a LegacyMappingTable lessonId absent from Lessons.all → '
        'broken_reference, non-zero exit', () {
      final fixture = _writeBaseline(fixtureRoot);
      final mutated = File('${fixtureRoot.path}/legacy_mapping_bad.dart')
        ..writeAsStringSync(
          _baselineLegacyMapping.replaceFirst(
            "lessonId: 'lesson-alpha'",
            "lessonId: 'does-not-exist'",
          ),
        );
      final args = fixture.args();
      args[args.indexOf(fixture.legacyMappingSource.path)] = mutated.path;
      final result = _run(args);
      expect(result.exitCode, isNot(0));
      expect(
        result.stdout,
        contains('broken_reference: legacy_mapping_table:does-not-exist'),
      );
    });

    test('fixture: a tutor-knowledge manifest sourcePath pointing at a '
        'non-existent file → broken_reference, non-zero exit', () {
      final fixture = _writeBaseline(fixtureRoot);
      final mutated = File('${fixtureRoot.path}/manifest_bad_path.json')
        ..writeAsStringSync(
          _baselineManifest.replaceFirst(
            'en/sample-en.json',
            'en/does-not-exist.json',
          ),
        );
      final args = fixture.args();
      args[args.indexOf(fixture.knowledgeManifest.path)] = mutated.path;
      final result = _run(args);
      expect(result.exitCode, isNot(0));
      expect(
        result.stdout,
        contains('broken_reference: tutor_knowledge:sample-en:'),
      );
    });
  });

  group('A3 — locale coverage is en AND hu; only known_exceptions lets a '
      'gap through (D3)', () {
    test('fixture: a topic missing its hu document → missing_locale (hu '
        'direction), non-zero exit', () {
      final fixture = _writeBaseline(fixtureRoot);
      final manifestNoHu = File('${fixtureRoot.path}/manifest_no_hu.json')
        ..writeAsStringSync(
          jsonEncode({
            'schemaVersion': 1,
            'documents': (jsonDecode(_baselineManifest)['documents'] as List)
                .where((d) => d['id'] != 'sample-hu')
                .toList(),
          }),
        );
      final invNoHu = File('${fixtureRoot.path}/inventory_no_hu.yaml')
        ..writeAsStringSync(
          _baselineInventory().replaceFirst(
            '  - id: sample-hu\n'
                '    source: tutor_knowledge\n'
                '    difficulty: beginner\n'
                '    skill_tags: [rhythm]\n'
                '    locales: [hu]\n'
                '    version: 1\n',
            '',
          ),
        );
      final args = fixture.args(inventoryOverride: invNoHu.path);
      args[args.indexOf(fixture.knowledgeManifest.path)] = manifestNoHu.path;
      final result = _run(args);
      expect(result.exitCode, isNot(0));
      expect(
        result.stdout,
        contains('missing_locale: tutor_knowledge:sample:hu'),
      );
    });

    test('fixture: a topic missing its en document → missing_locale (en '
        'direction), non-zero exit', () {
      final fixture = _writeBaseline(fixtureRoot);
      final manifestNoEn = File('${fixtureRoot.path}/manifest_no_en.json')
        ..writeAsStringSync(
          jsonEncode({
            'schemaVersion': 1,
            'documents': (jsonDecode(_baselineManifest)['documents'] as List)
                .where((d) => d['id'] != 'sample-en')
                .toList(),
          }),
        );
      final invNoEn = File('${fixtureRoot.path}/inventory_no_en.yaml')
        ..writeAsStringSync(
          _baselineInventory().replaceFirst(
            '  - id: sample-en\n'
                '    source: tutor_knowledge\n'
                '    difficulty: beginner\n'
                '    skill_tags: [rhythm]\n'
                '    locales: [en]\n'
                '    version: 1\n',
            '',
          ),
        );
      final args = fixture.args(inventoryOverride: invNoEn.path);
      args[args.indexOf(fixture.knowledgeManifest.path)] = manifestNoEn.path;
      final result = _run(args);
      expect(result.exitCode, isNot(0));
      expect(
        result.stdout,
        contains('missing_locale: tutor_knowledge:sample:en'),
      );
    });

    test(
      'the real tree R4 gap (10 practiceCatalog*Description ARB keys missing '
      'both locales, Lesson.name hardcoded English) is let through EXCLUSIVELY '
      'by the known_exceptions entries — no other missing_locale on the real '
      'tree',
      () {
        final result = _run([
          '--inventory',
          _realInventory,
          '--today',
          _todayIso,
        ]);
        expect(result.stdout, isNot(contains('missing_locale')));
      },
    );
  });

  group('A4 — the pedagogical path is measured on the SHIPPED structures '
      '(D5), not a new path file', () {
    test('(1) Lessons.all difficulty order is monotonic non-decreasing '
        '(beginner → intermediate → advanced)', () {
      final all = Lessons.all;
      for (var i = 1; i < all.length; i++) {
        expect(
          all[i].difficulty.index,
          greaterThanOrEqualTo(all[i - 1].difficulty.index),
          reason:
              '${all[i - 1].id} (${all[i - 1].difficulty}) → '
              '${all[i].id} (${all[i].difficulty}) steps backward',
        );
      }
    });

    test('(2) every lesson in the beginner tier is reachable from the '
        "tier's first element via the isUnlocked chain", () async {
      final store = InMemoryKeyValueStore();
      final container = ProviderContainer(
        overrides: [preferenceStoreOverride(store)],
      );
      addTearDown(container.dispose);
      final controller = container.read(lessonProgressProvider.notifier);
      final tier = Lessons.byDifficulty(Difficulty.beginner);

      expect(tier, isNotEmpty);
      for (var i = 0; i < tier.length; i++) {
        expect(
          controller.isUnlocked(tier[i]),
          isTrue,
          reason: '${tier[i].id} (index $i) is not reachable',
        );
        if (i < tier.length - 1) {
          await controller.record(tier[i].id, 0.9); // pass it, unlock next
        }
      }
    });

    test('(3) nextAfter(first-win) enters the curriculum; every non-last '
        'lesson has a successor; the last has none', () {
      expect(Lessons.nextAfter('first-win')?.id, Lessons.all.first.id);
      final all = Lessons.all;
      for (var i = 0; i < all.length - 1; i++) {
        expect(
          Lessons.nextAfter(all[i].id),
          isNotNull,
          reason: '${all[i].id} has no successor but is not the last lesson',
        );
      }
      expect(Lessons.nextAfter(all.last.id), isNull);
    });

    test('(4) the real inventory skill_graph block lists every '
        'SkillTaxonomy.initial node and every prerequisite', () {
      final text = File(_realInventory).readAsStringSync();
      final sectionStart = text.indexOf('\nskill_graph:');
      expect(sectionStart, greaterThan(-1));
      final afterHeader = text.substring(
        sectionStart + '\nskill_graph:'.length,
      );
      final sectionEnd = afterHeader.indexOf('\nknown_exceptions:');
      expect(sectionEnd, greaterThan(-1));
      final section = afterHeader.substring(0, sectionEnd);

      final nodePattern = RegExp(r'  - id: (.+)\n    prerequisites: \[(.*)\]');
      final declared = <String, Set<String>>{
        for (final m in nodePattern.allMatches(section))
          m.group(1)!: {
            for (final p in m.group(2)!.split(','))
              if (p.trim().isNotEmpty) p.trim(),
          },
      };
      expect(declared, isNotEmpty);

      final measured = <String, Set<String>>{
        for (final node in SkillTaxonomy.initial.nodes)
          node.id.value: {for (final p in node.prerequisiteIds) p.value},
      };

      expect(declared.keys.toSet(), measured.keys.toSet());
      for (final id in measured.keys) {
        expect(
          declared[id],
          measured[id],
          reason: 'node $id prerequisites diverge',
        );
      }
    });
  });

  group('A5 — skill vocabularies are declared PER SOURCE and measured '
      'bidirectionally (D4)', () {
    test('fixture: a tag used in the practice-engine source but not declared '
        'in skill_vocabularies → unknown_skill_tag, non-zero exit', () {
      final fixture = _writeBaseline(fixtureRoot);
      final mutated = File('${fixtureRoot.path}/practice_rogue.dart')
        ..writeAsStringSync(
          _baselinePracticeCatalog.replaceFirst(
            "'tagA', 'tagShared'",
            "'tagA', 'tagShared', 'tagRogue'",
          ),
        );
      final args = fixture.args();
      args[args.indexOf(fixture.practiceCatalog.path)] = mutated.path;
      final result = _run(args);
      expect(result.exitCode, isNot(0));
      expect(
        result.stdout,
        contains('unknown_skill_tag: practice_engine:tagRogue'),
      );
    });

    test('fixture: a declared tag never used by any practice-engine item → '
        'unused_skill_tag, non-zero exit', () {
      final fixture = _writeBaseline(fixtureRoot);
      fixture.inventory.writeAsStringSync(
        _baselineInventory().replaceFirst(
          '  practice_engine: [tagA, tagB, tagShared]',
          '  practice_engine: [tagA, tagB, tagShared, tagGhost]',
        ),
      );
      final result = _run(fixture.args());
      expect(result.exitCode, isNot(0));
      expect(
        result.stdout,
        contains('unused_skill_tag: practice_engine:tagGhost'),
      );
    });

    test('fixture: extending the KnowledgeSkill enum with a value the '
        'inventory does not declare → unknown_skill_tag, non-zero exit', () {
      final fixture = _writeBaseline(fixtureRoot);
      final mutated = File('${fixtureRoot.path}/knowledge_document_ext.dart')
        ..writeAsStringSync(_extendedKnowledgeEnum);
      final args = fixture.args();
      args[args.indexOf(fixture.knowledgeSkillEnumSource.path)] = mutated.path;
      final result = _run(args);
      expect(result.exitCode, isNot(0));
      expect(
        result.stdout,
        contains('unknown_skill_tag: tutor_knowledge:technique'),
      );
    });
  });

  group('A6 — every known_exceptions entry needs an owner and an ISO '
      'expiry; the boundary is inclusive', () {
    test('fixture: an exception with no owner → exception_missing_owner, '
        'non-zero exit', () {
      final fixture = _writeBaseline(fixtureRoot);
      fixture.inventory.writeAsStringSync(
        _baselineInventory().replaceFirst('    owner: fixture-owner\n', ''),
      );
      final result = _run(fixture.args());
      expect(result.exitCode, isNot(0));
      expect(
        result.stdout,
        contains('exception_missing_owner: fixture-learn-lessons-name-locale'),
      );
    });

    test(
      "fixture: expiry: unscheduled → exception_missing_expiry, non-zero exit",
      () {
        final fixture = _writeBaseline(fixtureRoot);
        fixture.inventory.writeAsStringSync(
          _baselineInventory().replaceFirst(
            'expiry: 2026-12-31',
            'expiry: unscheduled',
          ),
        );
        final result = _run(fixture.args());
        expect(result.exitCode, isNot(0));
        expect(
          result.stdout,
          contains(
            'exception_missing_expiry: fixture-learn-lessons-name-locale',
          ),
        );
      },
    );

    test(
      'threshold triple (--today 2026-09-01): expiry one day BELOW the '
      'threshold (2026-08-31) is expired → expired_exception, non-zero exit',
      () {
        final fixture = _writeBaseline(fixtureRoot, expiry: '2026-08-31');
        final result = _run(fixture.args());
        expect(result.exitCode, isNot(0));
        expect(
          result.stdout,
          contains('expired_exception: fixture-learn-lessons-name-locale'),
        );
      },
    );

    test('threshold triple: expiry EXACTLY on the threshold (2026-09-01) is '
        'still valid (inclusive boundary) — exit 0', () {
      final fixture = _writeBaseline(fixtureRoot, expiry: '2026-09-01');
      final result = _run(fixture.args());
      expect(result.exitCode, 0, reason: result.stdout);
    });

    test('threshold triple: expiry one day ABOVE the threshold (2026-09-02) is '
        'valid — exit 0', () {
      final fixture = _writeBaseline(fixtureRoot, expiry: '2026-09-02');
      final result = _run(fixture.args());
      expect(result.exitCode, 0, reason: result.stdout);
    });
  });

  group('A7 — the fail-closed parser: an unrecognized line is a finding, '
      'never a silent skip (L566)', () {
    test('fixture: a 4-space-indented, pattern-mismatched line appended after '
        'known_exceptions → unparsable_line, non-zero exit', () {
      final fixture = _writeBaseline(fixtureRoot);
      fixture.inventory.writeAsStringSync(
        '${_baselineInventory()}    - id: extra_unguarded_item\n',
      );
      final result = _run(fixture.args());
      expect(result.exitCode, isNot(0));
      expect(result.stdout, contains('unparsable_line:'));
    });
  });

  // No skip path anywhere in this file: if python3 is missing, every `_run`
  // call above throws `ProcessException` the first time it runs, which
  // fails that test — exactly the "PIROS, not skip" contract the self-check
  // below measures directly (L110, L527/A8 pattern from device_matrix_test.dart).
  group('A8 — this gate never relies on an unguaranteed or forbidden '
      'binary', () {
    test('this file does not import the transitive-only yaml package', () {
      final source = File(_thisFile).readAsStringSync();
      expect(
        RegExp(r"^import\s+'package:yaml", multiLine: true).hasMatch(source),
        isFalse,
      );
    });

    test('every external process this file spawns — through any dart:io '
        'Process.run/.runSync/.start entry point — targets python3 only, '
        'never rg/grep/jq/gh/git', () {
      final source = File(_thisFile).readAsStringSync();
      final executables = _processCallExecutable
          .allMatches(source)
          .map((match) => match.group(1)!)
          .toSet();
      expect(executables, isNotEmpty, reason: 'this file must call python3');
      expect(executables, {'python3'});
    });

    test('self-check: python3 is on PATH in this environment — if it is '
        'not, the calls above throw ProcessException and this whole file '
        'turns red, never a silent skip', () {
      final result = Process.runSync('python3', ['--version']);
      expect(result.exitCode, 0);
    });
  });
}

// Built via adjacent string-literal concatenation so this constant's own
// definition text never spells out the executable-call pattern it searches
// for as one contiguous run of characters — otherwise the A8 self-scan
// above would match its own regex source (device_matrix_test.dart pattern).
final _processCallExecutable = RegExp(
  'Process'
  r'''\.(?:run|runSync|start)\(\s*['"]([^'"\n]+)['"]''',
);
