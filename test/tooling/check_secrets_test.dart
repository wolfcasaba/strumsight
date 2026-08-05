// strumsight:allow-secret-file — a titok-scan SAJÁT tesztje: minden itt
// szereplő token szándékosan titok-alakú, hogy a felismerés bizonyítható
// legyen. A fájl kivételek fájlja, nem egy kivételt tartalmazó fájl.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/ci/check_secrets.dart';

void main() {
  late Directory projectRoot;

  setUp(() {
    projectRoot = Directory.systemTemp.createTempSync(
      'strumsight_secret_scan_',
    );
    _initRepository(projectRoot);
  });

  tearDown(() {
    projectRoot.deleteSync(recursive: true);
  });

  test('accepts a tree with no credentials', () {
    _track(projectRoot, 'lib/main.dart', 'void main() {}\n');

    final report = checkSecrets(projectRoot: projectRoot);

    expect(report.isClean, isTrue, reason: report.format());
    expect(report.scannedFiles, 1);
  });

  test('flags provider token literals by their own prefix', () {
    _track(
      projectRoot,
      'lib/config.dart',
      "const key = 'sk-abcdefghijklmnopqrstuvwxyz0123';\n",
    );

    final report = checkSecrets(projectRoot: projectRoot);

    expect(report.isClean, isFalse);
    expect(report.issues.single.kind, SecretIssueKind.providerToken);
    expect(report.issues.single.line, 1);
  });

  test('flags a private key block and a JSON Web Token', () {
    _track(projectRoot, 'deploy/key.pem', '-----BEGIN RSA PRIVATE KEY-----\n');
    _track(
      projectRoot,
      'lib/session.dart',
      "const t = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijk';\n",
    );

    final report = checkSecrets(projectRoot: projectRoot);

    expect(
      report.issues.map((issue) => issue.kind),
      containsAll(<SecretIssueKind>[
        SecretIssueKind.privateKey,
        SecretIssueKind.jsonWebToken,
      ]),
    );
  });

  test('flags a credential assigned a long literal', () {
    _track(
      projectRoot,
      'lib/api.dart',
      "const apiKey = 'Zx9Qw3Rt7Yu1Iop2As';\n",
    );

    final report = checkSecrets(projectRoot: projectRoot);

    expect(report.issues.single.kind, SecretIssueKind.credentialAssignment);
  });

  test('accepts placeholders, env-var names and interpolation', () {
    _track(projectRoot, 'lib/api.dart', '''
const a = 'YOUR_API_KEY_GOES_HERE';
const b = "\${ANTHROPIC_API_KEY}";
const c = 'example-value-not-a-secret';
const d = 'MINIMAX_API_KEY';
const e = '****************';
''');

    final report = checkSecrets(projectRoot: projectRoot);

    expect(report.isClean, isTrue, reason: report.format());
  });

  test('honours the inline allow marker for a proven fixture', () {
    _track(
      projectRoot,
      'test/redaction_test.dart',
      "const t = 'sk-abcdefghijklmnopqrstuvwxyz0123'; // $allowMarker fixture\n",
    );

    final report = checkSecrets(projectRoot: projectRoot);

    expect(report.isClean, isTrue, reason: report.format());
  });

  test('honours the file-level allow marker for a redaction test', () {
    // MÉRT eset (2026-08-05): a soronkénti jelölés törékeny a formázókkal
    // szemben — a `ruff format` újratördelte a sort, és a jelölés elvált a
    // fixture-től. Egy redakciós teszt nem egy kivételt tartalmazó fájl,
    // hanem kivételek fájlja: egyszer, a tetején mondja ki.
    _track(projectRoot, 'test/redaction_test.dart', '''
// $allowFileMarker a redakció tesztje
const a = 'sk-abcdefghijklmnopqrstuvwxyz0123';
const b = 'ghp_abcdefghijklmnopqrstuvwxyz01234567';
''');

    final report = checkSecrets(projectRoot: projectRoot);

    expect(report.isClean, isTrue, reason: report.format());
  });

  test('the file-level marker does not leak to other files', () {
    _track(projectRoot, 'test/redaction_test.dart', "// $allowFileMarker\n");
    _track(
      projectRoot,
      'lib/config.dart',
      "const key = 'sk-abcdefghijklmnopqrstuvwxyz0123';\n",
    );

    final report = checkSecrets(projectRoot: projectRoot);

    expect(report.isClean, isFalse);
    expect(report.issues.single.path, 'lib/config.dart');
  });

  test('ignores untracked and gitignored trees', () {
    // MÉRT eset (2026-08-05): a fájlrendszer-bejárás 29 leletet adott, ebből
    // 15 a gitignore-olt backend/.venv-ből és egy elárvult agent-worktree-ből
    // jött. A kapu kérdése az, hogy COMMITOLTUNK-e titkot.
    _track(projectRoot, '.gitignore', '.venv/\n');
    _write(projectRoot, '.venv/leaked.py', "api_key = 'Zx9Qw3Rt7Yu1Iop2As'\n");
    _write(
      projectRoot,
      'scratch.dart',
      "const k = 'sk-abcdefghijklmnopqrstuvwxyz0123';\n",
    );

    final report = checkSecrets(projectRoot: projectRoot);

    expect(report.isClean, isTrue, reason: report.format());
  });

  test('never puts the matched value into the report', () {
    const secret = 'sk-abcdefghijklmnopqrstuvwxyz0123';
    _track(projectRoot, 'lib/config.dart', "const key = '$secret';\n");

    final report = checkSecrets(projectRoot: projectRoot);

    expect(report.isClean, isFalse);
    expect(report.format(), isNot(contains(secret)));
    expect(report.format(), contains('lib/config.dart:1'));
  });

  test('fails loudly when Git cannot enumerate the tree', () {
    final notARepository = Directory.systemTemp.createTempSync(
      'strumsight_not_git_',
    );
    addTearDown(() => notARepository.deleteSync(recursive: true));

    expect(
      () => checkSecrets(projectRoot: notARepository),
      throwsA(isA<StateError>()),
      reason: 'a bizonyíthatatlan kapu piros, nem zöld',
    );
  });

  test('the committed repository tree is free of unmarked secrets', () {
    // Regressziós őr (E04-R15 / H3, 2026-08-05). MÉRT gyökérok: az R14 által
    // bevezetett backend/tests/tutor/test_tutor_proxy.py fake prod-config
    // fixture-jei (`secret_key`/`tutor_api_key`, sorok 596/611/627/631) a
    // GOV-03 secret-scan négy leletét adták, ám a fájl az R15 allowed_paths-án
    // KÍVÜL esett, ezért a build-apk merge-kapu `secrets` lépése nyolc percen
    // át piros maradt, a kört pedig nem lehetett a körön belül zöldre hozni.
    // Ez a teszt UGYANAZT futtatja, amit a kapu — a valódi, committolt fát
    // scanneli —, ezért a jelenség reprodukálhatóan visszatér, ha bárki
    // titok-alakú literált commitol jelölés nélkül.
    final repoRoot = Directory.current;

    final report = checkSecrets(projectRoot: repoRoot);

    expect(report.isClean, isTrue, reason: report.format());
  });
}

void _initRepository(Directory root) {
  Process.runSync('git', const ['init', '-q'], workingDirectory: root.path);
  Process.runSync('git', const [
    'config',
    'user.email',
    'gate@example.invalid',
  ], workingDirectory: root.path);
  Process.runSync('git', const [
    'config',
    'user.name',
    'Gate Test',
  ], workingDirectory: root.path);
}

void _write(Directory root, String relativePath, String contents) {
  final file = File('${root.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

void _track(Directory root, String relativePath, String contents) {
  _write(root, relativePath, contents);
  Process.runSync('git', [
    'add',
    '-f',
    relativePath,
  ], workingDirectory: root.path);
}
