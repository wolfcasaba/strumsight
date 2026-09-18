// Path/locale portability of the repo's own tooling (round C3).
//
// Four separate defects are guarded here. The first two groups exercise the
// normalisation RULES directly against both `package:path` contexts, so every
// cell is red against the pre-fix raw-string comparison on ANY host — the
// Windows-only arms of the defects are no longer invisible to Linux CI. The
// third group then runs the real tools end to end on this host's separator,
// and the fourth covers the Python release tools' link refusal.
//
//  1. `build_tutor_knowledge_manifest` compared a hand-joined output path
//     against the path `Directory.listSync` reports. A non-canonical
//     `--output` (one carrying a `.` segment) missed the exclusion on every
//     platform; a `/`-joined `manifest.json` additionally missed it on
//     Windows, where `listSync` reports `\`; and a differently-cased
//     `--output` missed it on Windows, where case does not distinguish files.
//  2. `check_data_inventory`'s `_relativePath` threw "outside repository" for
//     every file on Windows, for the same `/` vs `\` reason, and could not
//     see through a differently-cased repository root.
//  3. The two Python release tools refused a symlinked `--output` through the
//     POSIX-only `O_NOFOLLOW` flag, so on Windows there was no refusal at
//     all. The refusal is now stated explicitly and covers symlinks and
//     directory junctions — and ONLY those, so an ordinary output file on a
//     OneDrive-synced (reparse-point) path is still writable.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:path/path.dart' as p;
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_codec.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_document.dart';

import '../../tool/build_tutor_knowledge_manifest.dart';
import '../../tool/check_data_inventory.dart';

const _codec = KnowledgeCodec();
final _separator = Platform.pathSeparator;

void main() {
  late Directory temporaryDirectory;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'strumsight-tooling-portability-',
    );
  });

  tearDown(() {
    temporaryDirectory.deleteSync(recursive: true);
  });

  group('isExcludedManifestPath applies the platform file-identity rule', () {
    bool excludedOnWindows(String candidate) => isExcludedManifestPath(
      candidate,
      outputPath: r'C:\root\generated_manifest.json',
      manifestPath: r'C:\root\manifest.json',
      context: p.windows,
    );

    bool excludedOnPosix(String candidate) => isExcludedManifestPath(
      candidate,
      outputPath: '/root/generated_manifest.json',
      manifestPath: '/root/manifest.json',
      context: p.posix,
    );

    test('a "/"-joined manifest path matches the "\\"-spelled listing entry '
        '(windows context)', () {
      // The Windows-only arm of the defect: the tool joined the manifest name
      // with `/` while `listSync` reports `\`, so the raw `!=` never excluded
      // a stale manifest.json.
      expect(excludedOnWindows('C:/root/manifest.json'), isTrue);
    });

    test('a "." segment does not hide the output file (both contexts)', () {
      expect(excludedOnWindows(r'C:\root\.\generated_manifest.json'), isTrue);
      expect(excludedOnPosix('/root/./generated_manifest.json'), isTrue);
    });

    test('a ".." segment does not hide the output file (both contexts)', () {
      expect(
        excludedOnWindows(r'C:\root\en\..\generated_manifest.json'),
        isTrue,
      );
      expect(excludedOnPosix('/root/en/../generated_manifest.json'), isTrue);
    });

    test('case does not distinguish files in the windows context, and does '
        'in the posix context', () {
      expect(excludedOnWindows(r'C:\Root\Manifest.JSON'), isTrue);
      // The Linux behaviour is unchanged: two spellings, two files.
      expect(excludedOnPosix('/root/Manifest.json'), isFalse);
    });

    test('an ordinary content document is NOT excluded (non-vacuity)', () {
      expect(excludedOnWindows(r'C:\root\en\steady-pulse.json'), isFalse);
      expect(excludedOnPosix('/root/en/steady-pulse.json'), isFalse);
    });
  });

  group('repositoryRelativePath subtracts the root the platform way', () {
    test('a "/"-spelled file under a "\\"-spelled root still resolves '
        '(windows context)', () {
      expect(
        repositoryRelativePath(
          r'C:\a\repo',
          'C:/a/repo/lib/net/raw_client.dart',
          context: p.windows,
        ),
        'lib/net/raw_client.dart',
      );
    });

    test(
      'a trailing separator on the root changes nothing (both contexts)',
      () {
        expect(
          repositoryRelativePath(
            r'C:\a\repo\',
            r'C:\a\repo\lib\raw_client.dart',
            context: p.windows,
          ),
          'lib/raw_client.dart',
        );
        expect(
          repositoryRelativePath(
            '/a/repo/',
            '/a/repo/lib/raw_client.dart',
            context: p.posix,
          ),
          'lib/raw_client.dart',
        );
      },
    );

    test('a differently-cased root still contains the file in the windows '
        'context', () {
      expect(
        repositoryRelativePath(
          r'c:\A\Repo',
          r'C:\a\repo\lib\raw_client.dart',
          context: p.windows,
        ),
        'lib/raw_client.dart',
      );
    });

    test('a literal backslash inside a POSIX file name keeps its historical '
        '"/" rewrite', () {
      expect(
        repositoryRelativePath(
          '/a/repo',
          '/a/repo/lib/weird\\name.dart',
          context: p.posix,
        ),
        'lib/weird/name.dart',
      );
    });

    test('a file outside the root is still refused (both contexts)', () {
      expect(
        () => repositoryRelativePath(
          r'C:\a\repo',
          r'C:\a\repo2\lib\x.dart',
          context: p.windows,
        ),
        throwsArgumentError,
      );
      expect(
        () => repositoryRelativePath(
          '/a/repo',
          '/a/repo2/lib/x.dart',
          context: p.posix,
        ),
        throwsArgumentError,
      );
      // The root itself is not "inside" the root — unchanged from HEAD.
      expect(
        () => repositoryRelativePath('/a/repo', '/a/repo', context: p.posix),
        throwsArgumentError,
      );
    });
  });

  group('build_tutor_knowledge_manifest never scans its own output file', () {
    test('a non-canonical --output path inside the content root is still '
        'excluded from the scan (platform-independent)', () {
      final contentRoot = Directory(
        '${temporaryDirectory.path}${_separator}tutor_knowledge',
      )..createSync();
      _writeDocument(contentRoot, _document(id: 'steady-pulse', locale: 'en'));
      // A previous run's output, under a name other than `manifest.json`, so
      // only the output-path comparison can exclude it.
      File(
        '${contentRoot.path}${_separator}generated_manifest.json',
      ).writeAsStringSync('not a knowledge document at all');

      // The `.` segment is what the raw string comparison could not see
      // through: `listSync` reports the canonical path, so the two strings
      // differed and the stale output was decoded as content (corruptContent)
      // on every platform.
      final outputFile = File(
        '${contentRoot.path}$_separator.${_separator}generated_manifest.json',
      );
      buildTutorKnowledgeManifest(
        contentRoot: contentRoot,
        outputFile: outputFile,
      );

      final manifest =
          jsonDecode(outputFile.readAsStringSync()) as Map<String, Object?>;
      final documents = manifest['documents']! as List<Object?>;
      expect(documents, hasLength(1));
      expect((documents.single as Map<String, Object?>)['id'], 'steady-pulse');
    });

    test('a stale manifest.json already sitting in the content root is not '
        'read back as a knowledge document', () {
      // Windows-specific arm of the same defect: the tool appended
      // `/manifest.json` to a `\`-separated root and compared that mixed
      // string against the `\`-only path `listSync` reports.
      final contentRoot = Directory(
        '${temporaryDirectory.path}${_separator}tutor_knowledge',
      )..createSync();
      _writeDocument(contentRoot, _document(id: 'steady-pulse', locale: 'en'));
      File(
        '${contentRoot.path}${_separator}manifest.json',
      ).writeAsStringSync('{"schemaVersion":1,"documents":[]}');

      final outputFile = File('${contentRoot.path}/manifest.json');
      buildTutorKnowledgeManifest(
        contentRoot: contentRoot,
        outputFile: outputFile,
      );

      final manifest =
          jsonDecode(outputFile.readAsStringSync()) as Map<String, Object?>;
      final documents = manifest['documents']! as List<Object?>;
      expect(documents, hasLength(1));
      expect((documents.single as Map<String, Object?>)['id'], 'steady-pulse');
    });
  });

  group(
    'check_data_inventory reports repository-relative, "/"-joined paths',
    () {
      test('a repository root carrying the platform separator still yields '
          '"lib/..." routes, not an "outside repository" throw', () {
        // `discoverEgressRoutes` builds its scan directory as
        // `"${root.path}/lib"`, so on Windows the listed paths mix `/` and `\`
        // and the pre-fix prefix test matched nothing at all.
        final repositoryRoot = Directory(
          '${temporaryDirectory.path}${_separator}repo',
        )..createSync();
        final sourceFile = File(
          '${repositoryRoot.path}${_separator}lib${_separator}net'
          '${_separator}raw_client.dart',
        );
        sourceFile.parent.createSync(recursive: true);
        sourceFile.writeAsStringSync(
          'class RawClient {\n'
          '  void send() {\n'
          '    HttpClient();\n'
          '  }\n'
          '}\n',
        );

        final routes = discoverEgressRoutes(repositoryRoot);

        expect(
          routes.map((route) => route.file),
          contains('lib/net/raw_client.dart'),
        );
      });

      test('a repository root handed in with a trailing separator yields the '
          'same relative paths', () {
        final repositoryRoot = Directory(
          '${temporaryDirectory.path}${_separator}repo$_separator',
        )..createSync();
        final sourceFile = File(
          '${temporaryDirectory.path}${_separator}repo${_separator}lib'
          '${_separator}raw_client.dart',
        );
        sourceFile.parent.createSync(recursive: true);
        sourceFile.writeAsStringSync('void send() => HttpClient();\n');

        final routes = discoverEgressRoutes(repositoryRoot);

        expect(
          routes.map((route) => route.file),
          contains('lib/raw_client.dart'),
        );
      });
    },
  );

  group('the Python release tools refuse a linked --output on every '
      'platform', () {
    test('_is_redirecting_link refuses symlinks and junctions and ONLY those '
        '(both tools, platform-independent)', () {
      // A reparse tag is not by itself a redirection: a OneDrive/Cloud-Files
      // placeholder or a dedup stub is an ordinary file the filter driver
      // hydrates in place, and refusing those would reject a perfectly normal
      // `--output` on a synced folder. This cell pins both directions of the
      // rule without needing any privilege on any host.
      for (final tool in const <String>[
        'tool/release/build_diagnostics_bundle.py',
        'tool/release/generate_beta_notes.py',
      ]) {
        final result = Process.runSync('python3', [
          '-c',
          _reparseTagProbe,
          tool,
        ]);
        expect(
          result.exitCode,
          0,
          reason: '$tool: ${result.stdout}${result.stderr}',
        );
        expect(result.stdout.toString(), contains('ALL-OK'));
      }
    });

    test('build_diagnostics_bundle.py refuses to write through a symlink to '
        'a FILE, leaving the target untouched', () {
      final victim = File('${temporaryDirectory.path}${_separator}victim.txt')
        ..writeAsStringSync('untouched');
      final linkPath = '${temporaryDirectory.path}${_separator}bundle.json';
      if (!_plantFileLink(linkPath, victim.path)) {
        markTestSkipped(
          'creating a file symlink needs SeCreateSymbolicLinkPrivilege '
          '(Windows Developer Mode); the junction cells below cover the same '
          'refusal without it',
        );
        return;
      }

      final sessionFile = File(
        '${temporaryDirectory.path}${_separator}session.json',
      )..writeAsStringSync('{"schemaVersion":1,"sessionId":"s","events":[]}');

      final result = Process.runSync('python3', [
        'tool/release/build_diagnostics_bundle.py',
        '--session-file',
        sessionFile.path,
        '--output',
        linkPath,
        '--consent-diagnostics',
      ]);

      expect(result.exitCode, isNot(0), reason: result.stdout.toString());
      expect(
        result.stderr.toString(),
        contains('refusing to write through it'),
      );
      expect(victim.readAsStringSync(), 'untouched');
    });

    test('generate_beta_notes.py refuses to write through a symlink to a '
        'FILE, leaving the target untouched', () {
      final victim = File('${temporaryDirectory.path}${_separator}victim.md')
        ..writeAsStringSync('untouched');
      final linkPath = '${temporaryDirectory.path}${_separator}notes.md';
      if (!_plantFileLink(linkPath, victim.path)) {
        markTestSkipped(
          'creating a file symlink needs SeCreateSymbolicLinkPrivilege '
          '(Windows Developer Mode); the junction cells below cover the same '
          'refusal without it',
        );
        return;
      }

      final manifestFile = File(
        '${temporaryDirectory.path}${_separator}manifest.json',
      )..writeAsStringSync(jsonEncode(_releaseManifest()));

      final result = Process.runSync('python3', [
        'tool/release/generate_beta_notes.py',
        '--manifest',
        manifestFile.path,
        '--output',
        linkPath,
      ]);

      expect(result.exitCode, isNot(0), reason: result.stdout.toString());
      expect(
        result.stderr.toString(),
        contains('refusing to write through it'),
      );
      expect(victim.readAsStringSync(), 'untouched');
    });

    test('build_diagnostics_bundle.py refuses to write through a directory '
        'junction', () {
      final victim = Directory('${temporaryDirectory.path}${_separator}victim')
        ..createSync();
      final linkPath = '${temporaryDirectory.path}${_separator}bundle.json';
      _plantDirectoryLink(linkPath, victim.path);

      final sessionFile = File(
        '${temporaryDirectory.path}${_separator}session.json',
      )..writeAsStringSync('{"schemaVersion":1,"sessionId":"s","events":[]}');

      final result = Process.runSync('python3', [
        'tool/release/build_diagnostics_bundle.py',
        '--session-file',
        sessionFile.path,
        '--output',
        linkPath,
        '--consent-diagnostics',
      ]);

      expect(result.exitCode, isNot(0), reason: result.stdout.toString());
      // Only this assertion discriminates: opening a directory for writing
      // fails on every platform, so the exit code alone proves nothing.
      expect(
        result.stderr.toString(),
        contains('refusing to write through it'),
      );
      expect(victim.listSync(), isEmpty);
    });

    test('generate_beta_notes.py refuses to write through a directory '
        'junction', () {
      final victim = Directory('${temporaryDirectory.path}${_separator}victim')
        ..createSync();
      final linkPath = '${temporaryDirectory.path}${_separator}notes.md';
      _plantDirectoryLink(linkPath, victim.path);

      final manifestFile = File(
        '${temporaryDirectory.path}${_separator}manifest.json',
      )..writeAsStringSync(jsonEncode(_releaseManifest()));

      final result = Process.runSync('python3', [
        'tool/release/generate_beta_notes.py',
        '--manifest',
        manifestFile.path,
        '--output',
        linkPath,
      ]);

      expect(result.exitCode, isNot(0), reason: result.stdout.toString());
      expect(
        result.stderr.toString(),
        contains('refusing to write through it'),
      );
      expect(victim.listSync(), isEmpty);
    });

    test('an ordinary --output on a plain path is still written (the refusal '
        'does not over-reject)', () {
      final outputPath = '${temporaryDirectory.path}${_separator}notes.md';
      final manifestFile = File(
        '${temporaryDirectory.path}${_separator}manifest.json',
      )..writeAsStringSync(jsonEncode(_releaseManifest()));

      final result = Process.runSync('python3', [
        'tool/release/generate_beta_notes.py',
        '--manifest',
        manifestFile.path,
        '--output',
        outputPath,
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(File(outputPath).readAsStringSync(), contains('1.2.3'));
    });
  });
}

/// Exercises `_is_redirecting_link` in the release tool named by `argv[1]`
/// against synthetic `os.lstat` results, so both directions of the rule are
/// pinned on a host that can create neither a symlink nor a junction.
const _reparseTagProbe = r'''
import importlib.util, stat, sys

spec = importlib.util.spec_from_file_location("tool_under_test", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class FakeStat:
    def __init__(self, mode, tag):
        self.st_mode = mode
        self.st_reparse_tag = tag


cases = [
    ("plain file", FakeStat(stat.S_IFREG, 0), False),
    ("posix symlink", FakeStat(stat.S_IFLNK, 0), True),
    ("windows symlink tag", FakeStat(stat.S_IFREG, 0xA000000C), True),
    ("directory junction tag", FakeStat(stat.S_IFDIR, 0xA0000003), True),
    ("onedrive placeholder tag", FakeStat(stat.S_IFREG, 0x9000001A), False),
    ("dedup stub tag", FakeStat(stat.S_IFREG, 0x80000013), False),
]
failures = []
for name, status, expected in cases:
    actual = module._is_redirecting_link(status)
    if actual != expected:
        failures.append("%s: expected %s, got %s" % (name, expected, actual))
if failures:
    print("FAILED: " + "; ".join(failures))
    sys.exit(1)
print("ALL-OK")
''';

/// Plants a symlink at [linkPath] pointing at the file [targetPath].
///
/// Returns false when the host refuses to create one at all — a Windows
/// account without `SeCreateSymbolicLinkPrivilege` (Developer Mode off)
/// cannot, and the caller then skips with that reason.
bool _plantFileLink(String linkPath, String targetPath) {
  try {
    Link(linkPath).createSync(targetPath);
    return true;
  } on FileSystemException {
    if (!Platform.isWindows) rethrow;
    return false;
  }
}

/// Plants a link at [linkPath] pointing at the directory [targetPath].
///
/// A directory junction needs no privilege on Windows and is the same class of
/// reparse point as a symlink — which is exactly what the tools must refuse to
/// write through.
void _plantDirectoryLink(String linkPath, String targetPath) {
  try {
    Link(linkPath).createSync(targetPath);
    return;
  } on FileSystemException {
    if (!Platform.isWindows) rethrow;
  }
  final result = Process.runSync('cmd', [
    '/c',
    'mklink',
    '/J',
    linkPath,
    targetPath,
  ]);
  expect(
    result.exitCode,
    0,
    reason: 'could not plant a link to exercise the refusal: ${result.stderr}',
  );
}

Map<String, Object?> _releaseManifest() {
  String repeat(String char) => List.filled(64, char).join();
  return <String, Object?>{
    'schemaVersion': 1,
    'app': <String, Object?>{
      'version': '1.2.3',
      'buildNumber': 42,
      'shortSha': 'abcdef1',
      'channel': 'beta',
    },
    'modelPackage': <String, Object?>{
      'schemaVersion': 1,
      'manifestSha256': repeat('a'),
      'modelCount': 4,
    },
    'knowledgePackage': <String, Object?>{
      'schemaVersion': 1,
      'manifestSha256': repeat('b'),
      'documentCount': 10,
    },
    'artifacts': <Object?>[
      <String, Object?>{
        'name': 'app-release.apk',
        'path': 'dist/app-release.apk',
        'sha256': repeat('c'),
      },
    ],
  };
}

void _writeDocument(Directory contentRoot, KnowledgeDocument document) {
  final file = File(
    '${contentRoot.path}$_separator${document.locale}'
    '$_separator${document.id}.json',
  );
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(utf8.decode(_codec.encodeDocument(document)));
}

KnowledgeDocument _document({required String id, required String locale}) {
  const title = 'Keep a steady pulse';
  const body =
      'Count four even beats before playing.\n\nKeep the motion small and relaxed.';
  return KnowledgeDocument(
    schemaVersion: KnowledgeDocument.currentSchemaVersion,
    id: id,
    locale: locale,
    skill: KnowledgeSkill.rhythm,
    difficulty: KnowledgeDifficulty.beginner,
    license: 'CC0-1.0',
    version: 1,
    status: KnowledgeApprovalStatus.approved,
    title: title,
    body: body,
    contentHash: KnowledgeCodec.contentHashForDocument(
      title: title,
      body: body,
    ),
  );
}
