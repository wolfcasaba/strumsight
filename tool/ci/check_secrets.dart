import 'dart:convert';
import 'dart:io';

/// The kinds of credential leak enforced by the CI gate.
enum SecretIssueKind {
  privateKey,
  providerToken,
  jsonWebToken,
  credentialAssignment,
  credentialInUrl,
}

/// One suspected credential, identified by location only.
///
/// The matched text is deliberately never carried: a gate that prints the
/// secret it found leaks that secret into CI logs, which is the very thing the
/// gate exists to prevent (AGENTS.md §5).
final class SecretIssue {
  const SecretIssue({
    required this.path,
    required this.line,
    required this.kind,
    required this.rule,
  });

  final String path;
  final int line;
  final SecretIssueKind kind;
  final String rule;
}

/// Complete result of scanning a working tree for committed credentials.
final class SecretCheckReport {
  SecretCheckReport({
    required this.scannedFiles,
    required List<SecretIssue> issues,
  }) : issues = List.unmodifiable(issues);

  final int scannedFiles;
  final List<SecretIssue> issues;

  bool get isClean => issues.isEmpty;

  /// Human-readable CLI output containing locations, never matched values.
  String format() {
    if (isClean) {
      return 'Secret scan OK ($scannedFiles file(s) scanned, 0 finding(s)).';
    }
    final output = StringBuffer(
      'Secret scan failed ($scannedFiles file(s) scanned, '
      '${issues.length} finding(s)).',
    );
    for (final issue in issues) {
      output
        ..writeln()
        ..write('- ${issue.path}:${issue.line}: ${issue.rule}');
    }
    output
      ..writeln()
      ..writeln()
      ..write(
        'A találat HELYE szerepel, az ÉRTÉKE soha. Ha bizonyítottan nem titok '
        '(teszt-fixture, dokumentált minta), tedd a sor végére: // $allowMarker <indok>',
      );
    return output.toString();
  }
}

/// Inline escape for a proven non-secret (test fixture, documented example).
const String allowMarker = 'strumsight:allow-secret';

/// Directories that never contain reviewable source.
const Set<String> _skippedDirectories = {
  '.git',
  '.dart_tool',
  'build',
  'coverage',
  '__pycache__',
  '.pipeline',
  'node_modules',
  '.ai',
  '.gradle',
};

/// Extensions whose contents are binary or generated beyond review value.
const Set<String> _skippedExtensions = {
  '.png', '.jpg', '.jpeg', '.gif', '.webp', '.ico', '.svg', //
  '.wav', '.mp3', '.ogg', '.m4a', '.mid', '.midi',
  '.ttf', '.otf', '.woff', '.woff2',
  '.zip', '.gz', '.tar', '.jar', '.apk', '.aab', '.so', '.a', '.dylib',
  '.bin', '.tflite', '.onnx', '.pt', '.pth', '.npy', '.lock',
  '.pyc', '.class', '.pdf', '.mxl', '.gp5',
};

/// Files larger than this are treated as data, not source.
const int _maxScannedBytes = 1024 * 1024;

final class _SecretRule {
  const _SecretRule({
    required this.kind,
    required this.rule,
    required this.pattern,
    this.valueGroup,
  });

  final SecretIssueKind kind;
  final String rule;
  final RegExp pattern;

  /// When set, the capture group holding the candidate value, so obvious
  /// placeholders can be excluded without the value ever being stored.
  final int? valueGroup;
}

final List<_SecretRule> _rules = <_SecretRule>[
  _SecretRule(
    kind: SecretIssueKind.privateKey,
    rule: 'private key block',
    pattern: RegExp(r'-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----'),
  ),
  _SecretRule(
    kind: SecretIssueKind.providerToken,
    rule: 'provider token literal',
    // A szolgáltatók SAJÁT, felismerhető előtagjai: ezek önmagukban
    // azonosítják a titkot, ezért nem kell hozzájuk kontextus.
    pattern: RegExp(
      r'(?:^|[^A-Za-z0-9_-])(?:'
      r'sk-[A-Za-z0-9_-]{20,}'
      r'|ghp_[A-Za-z0-9]{30,}'
      r'|github_pat_[A-Za-z0-9_]{30,}'
      r'|gho_[A-Za-z0-9]{30,}'
      r'|xox[baprs]-[A-Za-z0-9-]{10,}'
      r'|AKIA[0-9A-Z]{16}'
      r'|AIza[0-9A-Za-z_-]{35}'
      r')',
    ),
  ),
  _SecretRule(
    kind: SecretIssueKind.jsonWebToken,
    rule: 'JSON Web Token literal',
    pattern: RegExp(
      r'(?:^|[^A-Za-z0-9_-])eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}',
    ),
  ),
  _SecretRule(
    kind: SecretIssueKind.credentialAssignment,
    rule: 'credential assigned a long literal',
    pattern: RegExp(
      r'''(?:api[_-]?key|secret[_-]?key|client[_-]?secret|auth[_-]?token'''
      r'''|access[_-]?token|password|passwd|private[_-]?key)'''
      r'''\s*[:=]\s*["'`]([^"'`\s]{16,})["'`]''',
      caseSensitive: false,
    ),
    valueGroup: 1,
  ),
  _SecretRule(
    kind: SecretIssueKind.credentialInUrl,
    rule: 'credential in a URL query parameter',
    pattern: RegExp(
      r'''[?&](?:token|api[_-]?key|access[_-]?token|secret)=([^&#\s"'`<>]{16,})''',
      caseSensitive: false,
    ),
    valueGroup: 1,
  ),
];

/// Values that look like credentials but provably are not.
final RegExp _placeholder = RegExp(
  r'^(?:'
  r'.*(?:example|sample|dummy|fake|placeholder|redacted|changeme|your[_-]|test[_-]?only|xxx|\.\.\.).*'
  r'|[<${].*' // <YOUR_KEY>, ${ENV}, $interpoláció
  r'|[A-Z][A-Z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD)' // csupa nagybetűs env-név
  r'|[*x]{4,}'
  r')$',
  caseSensitive: false,
);

/// Scans the repository's TRACKED files for committed credentials.
///
/// Tracked files, not the working tree: the gate's question is "did a secret
/// get committed", so a vendored `backend/.venv` or a stale agent worktree —
/// both gitignored — are noise, not findings.  Measured 2026-08-05: the first
/// version walked the filesystem and produced 29 findings, 15 of which came
/// from exactly those two gitignored trees.
///
/// The scan is deliberately conservative: provider-prefixed tokens, private
/// key blocks and JWTs match on their own shape, while generic assignments
/// require both a credential-looking name and a long, non-placeholder literal.
/// False negatives are preferred to a noisy gate nobody trusts — the semantic
/// judgement stays with the `security-reviewer` agent (ADR 0138).
SecretCheckReport checkSecrets({required Directory projectRoot}) {
  final root = projectRoot.absolute.path;
  final issues = <SecretIssue>[];
  var scannedFiles = 0;

  for (final relative in _trackedFiles(projectRoot)) {
    if (_isSkipped(relative)) continue;
    final entity = File('$root/$relative');
    if (!entity.existsSync()) continue; // törölt, de még indexelt
    if (entity.lengthSync() > _maxScannedBytes) continue;

    final String contents;
    try {
      contents = entity.readAsStringSync();
    } on FileSystemException {
      continue; // nem olvasható — nem elemezhető
    } on FormatException {
      continue; // nem UTF-8 — bináris, nem elemezhető
    }
    scannedFiles++;

    final lines = contents.split('\n');
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line.contains(allowMarker)) continue;
      for (final rule in _rules) {
        final match = rule.pattern.firstMatch(line);
        if (match == null) continue;
        final group = rule.valueGroup;
        if (group != null && _placeholder.hasMatch(match.group(group) ?? '')) {
          continue;
        }
        issues.add(
          SecretIssue(
            path: relative,
            line: index + 1,
            kind: rule.kind,
            rule: rule.rule,
          ),
        );
      }
    }
  }

  issues.sort((a, b) {
    final byPath = a.path.compareTo(b.path);
    return byPath != 0 ? byPath : a.line.compareTo(b.line);
  });
  return SecretCheckReport(scannedFiles: scannedFiles, issues: issues);
}

/// Repository-relative paths of every file Git tracks under [projectRoot].
///
/// Fail-closed: if Git cannot enumerate them, the gate errors rather than
/// silently scanning nothing and reporting a clean tree.
List<String> _trackedFiles(Directory projectRoot) {
  final result = Process.runSync(
    'git',
    const ['ls-files', '-z'],
    workingDirectory: projectRoot.absolute.path,
    stdoutEncoding: const Utf8Codec(),
  );
  if (result.exitCode != 0) {
    throw StateError(
      'check_secrets: `git ls-files` failed in ${projectRoot.path} '
      '(exit ${result.exitCode}) — a kapu nem tud bizonyítani, ezért piros.',
    );
  }
  return (result.stdout as String)
      .split('\u0000')
      .where((path) => path.isNotEmpty)
      .toList();
}

bool _isSkipped(String relativePath) {
  for (final segment in relativePath.split('/')) {
    if (_skippedDirectories.contains(segment)) return true;
  }
  final dot = relativePath.lastIndexOf('.');
  if (dot <= 0) return false;
  return _skippedExtensions.contains(relativePath.substring(dot).toLowerCase());
}

void main() {
  final report = checkSecrets(projectRoot: Directory.current);
  stdout.writeln(report.format());
  if (!report.isClean) exitCode = 1;
}
