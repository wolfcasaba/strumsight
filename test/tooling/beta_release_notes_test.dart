// Beta distribution gate (E12-R22, ADR 0486).
//
// Follows the `test/tooling/ai_release_report_test.dart` (E12-R16) and
// `release_manifest_test.dart` (E12-R06) pattern: `python3` on a fixture
// tree written to `Directory.systemTemp` at test run time, torn down in
// `tearDown` — the round's allowed-files list does not include
// `test/fixtures/**`, so no fixture is committed. `python3` is the ONLY
// external binary this file is allowed to invoke; there is no `skip:`
// branch anywhere in it.
//
// This is the round's ONLY Dart test file (round brief §0.0.A R4) — it
// carries the acceptance cells for BOTH Python tools
// (`build_diagnostics_bundle.py`, `generate_beta_notes.py`) plus the A6
// document-crosscheck cell, which is why it is organized into two big
// halves rather than split across files.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_data_inventory.dart';

void main() {
  late Directory fixtureRoot;

  setUp(() {
    fixtureRoot = Directory.systemTemp.createTempSync(
      'strumsight_beta_release_notes_',
    );
  });
  tearDown(() => fixtureRoot.deleteSync(recursive: true));

  String fixturePath(String name) => '${fixtureRoot.path}/$name';

  String writeFile(String name, String content) {
    final file = File(fixturePath(name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file.path;
  }

  String writeBytes(String name, List<int> bytes) {
    final file = File(fixturePath(name));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return file.path;
  }

  // ---------------------------------------------------------------------
  // build_diagnostics_bundle.py fixtures
  // ---------------------------------------------------------------------

  // Deterministic xorshift32 PRNG, NOT `Uint8List(n)` (all-zero bytes) —
  // a zero-filled clip base64-encodes to a run of "A"/"=" containing no "/"
  // at all, which is exactly the one input the M1 regression (the absolute
  // -path pattern mistaking base64 "/" for a path separator and silently
  // mangling a consented audio clip, ADR 0486 D2.1) cannot reproduce on.
  // Fixed seed, no external RNG dependency ⇒ byte-for-byte reproducible.
  Uint8List deterministicPcm(int byteCount, {int seed = 0xc0ffee}) {
    final bytes = Uint8List(byteCount);
    var state = seed;
    for (var i = 0; i < byteCount; i++) {
      state ^= (state << 13) & 0xffffffff;
      state ^= state >> 17;
      state ^= (state << 5) & 0xffffffff;
      bytes[i] = state & 0xff;
    }
    return bytes;
  }

  Map<String, Object?> audioClip(int rawByteCount, {double tSec = 0}) => {
    'tSec': tSec,
    'wavBase64': base64Encode(deterministicPcm(rawByteCount)),
  };

  String sessionJson({
    String appVersion = '1.9.0',
    String device = 'Pixel 9 (Android 15)',
    String diagToken = 'fixture-super-secret-token-value',
    List<Map<String, Object?>> events = const [],
    List<Map<String, Object?>> audioClips = const [],
  }) => jsonEncode({
    'sessionId': 'fixture-session',
    'appVersion': appVersion,
    'device': device,
    'startedAt': '2026-01-01T00:00:00Z',
    'surface': 'analyze',
    'diagToken': diagToken,
    'events': events,
    'audioClips': audioClips,
  });

  String writeSessionFile(String name, String json) => writeFile(name, json);

  ProcessResult runBundle({
    required String sessionFile,
    required String output,
    bool consentDiagnostics = false,
    bool consentRawAudio = false,
  }) => Process.runSync('python3', [
    'tool/release/build_diagnostics_bundle.py',
    '--session-file',
    sessionFile,
    '--output',
    output,
    if (consentDiagnostics) '--consent-diagnostics',
    if (consentRawAudio) '--consent-raw-audio',
  ]);

  Map<String, Object?> decodeBundle(String outputPath) =>
      jsonDecode(File(outputPath).readAsStringSync()) as Map<String, Object?>;

  group('A1 — the bundle default (diagnostics consent only) never carries '
      'raw audio (ADR 0486 D1)', () {
    test('a session with an audio clip produces a bundle with no '
        'audioClips key at all when only --consent-diagnostics is given', () {
      final sessionFile = writeSessionFile(
        'session.json',
        sessionJson(
          events: [
            {'tSec': 0.0, 'mlChord': 'C', 'dspChord': 'C'},
          ],
          audioClips: [audioClip(1024)],
        ),
      );
      final output = fixturePath('bundle.json');

      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final bundle = decodeBundle(output);
      final session = bundle['session']! as Map<String, Object?>;
      expect(session.containsKey('audioClips'), isFalse);
      // Belt-and-braces: the wav payload itself must not survive anywhere
      // in the output text, not just be absent from a specific key.
      expect(File(output).readAsStringSync(), isNot(contains('wavBase64')));
    });
  });

  group('A2 — token, e-mail, absolute path and device-id are all masked, '
      'recursively, everywhere in the session tree (ADR 0486 D2)', () {
    test(
      'a token-shaped key is masked regardless of nesting depth or case',
      () {
        final sessionFile = writeSessionFile(
          'session.json',
          sessionJson(
            diagToken: 'top-level-secret-token',
            events: [
              {
                'tSec': 0.0,
                'nested': {'X-Diag-Token': 'nested-secret-Token-Value'},
              },
            ],
          ),
        );
        final output = fixturePath('bundle.json');

        final result = runBundle(
          sessionFile: sessionFile,
          output: output,
          consentDiagnostics: true,
        );

        expect(result.exitCode, 0, reason: result.stderr.toString());
        final text = File(output).readAsStringSync();
        expect(text, isNot(contains('top-level-secret-token')));
        expect(text, isNot(contains('nested-secret-Token-Value')));
        expect('[REDACTED:token]'.allMatches(text).length, 2);
      },
    );

    test('an e-mail address anywhere inside a free-text field is masked, '
        'not just a field literally named "email"', () {
      final sessionFile = writeSessionFile(
        'session.json',
        sessionJson(
          events: [
            {
              'tSec': 0.0,
              'note': 'reported by fixture-tester@example.test, please help',
            },
          ],
        ),
      );
      final output = fixturePath('bundle.json');

      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final text = File(output).readAsStringSync();
      expect(text, isNot(contains('fixture-tester@example.test')));
      expect(text, contains('[REDACTED:email]'));
      expect(text, contains('reported by'));
    });

    test('an absolute POSIX path anywhere in a free-text field is masked', () {
      final sessionFile = writeSessionFile(
        'session.json',
        sessionJson(
          events: [
            {
              'tSec': 0.0,
              'note': 'crash log at /data/local/tmp/fixture/session.log',
            },
          ],
        ),
      );
      final output = fixturePath('bundle.json');

      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final text = File(output).readAsStringSync();
      expect(text, isNot(contains('/data/local/tmp/fixture/session.log')));
      expect(text, contains('[REDACTED:path]'));
    });

    test(
      'an absolute Windows path anywhere in a free-text field is masked',
      () {
        final sessionFile = writeSessionFile(
          'session.json',
          sessionJson(
            events: [
              {
                'tSec': 0.0,
                'note': r'saved at C:\Users\fixture\AppData\log.txt',
              },
            ],
          ),
        );
        final output = fixturePath('bundle.json');

        final result = runBundle(
          sessionFile: sessionFile,
          output: output,
          consentDiagnostics: true,
        );

        expect(result.exitCode, 0, reason: result.stderr.toString());
        final text = File(output).readAsStringSync();
        expect(text, isNot(contains(r'C:\Users\fixture\AppData\log.txt')));
        expect(text, contains('[REDACTED:path]'));
      },
    );

    test('a slash-bass chord label ("C/E") is NOT mistaken for an absolute '
        'path — the two-segment floor exists exactly to protect this '
        "app's own domain data", () {
      final sessionFile = writeSessionFile(
        'session.json',
        sessionJson(
          events: [
            {'tSec': 0.0, 'mlChord': 'C/E', 'dspChord': 'Am7/G'},
          ],
        ),
      );
      final output = fixturePath('bundle.json');

      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final text = File(output).readAsStringSync();
      expect(text, contains('C/E'));
      expect(text, contains('Am7/G'));
      expect(text, isNot(contains('[REDACTED:path]')));
    });

    for (final key in [
      'deviceId',
      'device_id',
      'androidId',
      'installId',
      'udid',
    ]) {
      test('the exact device-id key "$key" is masked', () {
        final sessionFile = writeSessionFile(
          'session.json',
          sessionJson(
            events: [
              {'tSec': 0.0, key: 'fixture-device-identifier-0001'},
            ],
          ),
        );
        final output = fixturePath('bundle.json');

        final result = runBundle(
          sessionFile: sessionFile,
          output: output,
          consentDiagnostics: true,
        );

        expect(result.exitCode, 0, reason: result.stderr.toString());
        final text = File(output).readAsStringSync();
        expect(text, isNot(contains('fixture-device-identifier-0001')));
        expect(text, contains('[REDACTED:device-id]'));
      });
    }

    test('a similarly-named but non-matching key ("deviceName") is left '
        'untouched — the device-id class is an exact list, not a substring '
        'match (no over-redaction)', () {
      final sessionFile = writeSessionFile(
        'session.json',
        sessionJson(
          events: [
            {'tSec': 0.0, 'deviceName': 'Pixel 9 Pro'},
          ],
        ),
      );
      final output = fixturePath('bundle.json');

      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final text = File(output).readAsStringSync();
      expect(text, contains('Pixel 9 Pro'));
    });

    test('device_metadata platform strings (appVersion, device) are NOT '
        'redacted — the leltár says their purpose is build/platform '
        'correlation, not device identification', () {
      final sessionFile = writeSessionFile(
        'session.json',
        sessionJson(
          appVersion: '1.9.0-fixture',
          device: 'Pixel 9 (Android 15)',
        ),
      );
      final output = fixturePath('bundle.json');

      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final text = File(output).readAsStringSync();
      expect(text, contains('1.9.0-fixture'));
      expect(text, contains('Pixel 9 (Android 15)'));
    });

    // The exact mérce-mátrix regression: "the redaction only runs at the
    // top level, the nested event stays raw".
    test('a secret nested two levels inside events[0] is redacted, proving '
        'the walk is recursive rather than top-level only', () {
      final sessionFile = writeSessionFile(
        'session.json',
        sessionJson(
          events: [
            {
              'tSec': 0.0,
              'context': {
                'reporter': {'contactEmail': 'deep-fixture@example.test'},
              },
            },
          ],
        ),
      );
      final output = fixturePath('bundle.json');

      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final text = File(output).readAsStringSync();
      expect(text, isNot(contains('deep-fixture@example.test')));
      expect(text, contains('[REDACTED:email]'));
    });
  });

  group('Threshold cell triple — the raw audio cap is the MEASURED '
      'DiagnosticsUploader.maxWavBytes = 5,242,880 bytes, INCLUSIVE (ADR '
      '0486 D3)', () {
    test('5,242,879 decoded bytes (one under the cap) is accepted, and the '
        'clip survives whole — not truncated', () {
      final sessionFile = writeSessionFile(
        'session.json',
        sessionJson(audioClips: [audioClip(5242879)]),
      );
      final output = fixturePath('bundle.json');

      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
        consentRawAudio: true,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final session = decodeBundle(output)['session']! as Map<String, Object?>;
      final clips = session['audioClips']! as List;
      final wav = base64Decode((clips.single as Map)['wavBase64'] as String);
      expect(wav.length, 5242879);
    });

    test('5,242,880 decoded bytes (exactly on the cap) is accepted — the '
        'boundary is inclusive', () {
      final sessionFile = writeSessionFile(
        'session.json',
        sessionJson(audioClips: [audioClip(5242880)]),
      );
      final output = fixturePath('bundle.json');

      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
        consentRawAudio: true,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final session = decodeBundle(output)['session']! as Map<String, Object?>;
      final clips = session['audioClips']! as List;
      final wav = base64Decode((clips.single as Map)['wavBase64'] as String);
      expect(wav.length, 5242880);
    });

    test('5,242,881 decoded bytes (one over the cap) is REJECTED — a '
        'non-zero exit and NO output file, never a silent truncation', () {
      final sessionFile = writeSessionFile(
        'session.json',
        sessionJson(audioClips: [audioClip(5242881)]),
      );
      final output = fixturePath('bundle.json');

      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
        consentRawAudio: true,
      );

      expect(result.exitCode, isNot(0));
      expect(File(output).existsSync(), isFalse);
    });
  });

  group('M1 — a realistic (slash-bearing) audio clip survives redaction '
      'byte-for-byte: base64 "/" characters must not be mistaken for an '
      'absolute-path separator (ADR 0486 D2.1)', () {
    test('a clip whose base64 contains many "/" characters comes out of '
        'the bundle bit-for-bit identical to the input', () {
      final rawClip = deterministicPcm(1024 * 1024);
      final inputB64 = base64Encode(rawClip);
      expect(
        inputB64.contains('/'),
        isTrue,
        reason:
            'the fixture must be non-degenerate for this cell to mean '
            'anything',
      );
      final sessionFile = writeSessionFile(
        'session.json',
        sessionJson(
          audioClips: [
            {'tSec': 0.0, 'wavBase64': inputB64},
          ],
        ),
      );
      final output = fixturePath('bundle.json');

      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
        consentRawAudio: true,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final session = decodeBundle(output)['session']! as Map<String, Object?>;
      final clips = session['audioClips']! as List;
      final outputB64 = (clips.single as Map)['wavBase64'] as String;
      expect(outputB64, inputB64);
      expect(base64Decode(outputB64), rawClip);
    });
  });

  group('M2 — the raw-audio gate and size cap are CONTENT-based, not tied '
      'to the top-level "audioClips" key name (ADR 0486 D3.1)', () {
    test('a wavBase64 field nested inside "events" (not audioClips) is '
        'stripped entirely when only --consent-diagnostics is given', () {
      final clip = base64Encode(deterministicPcm(1024));
      final sessionFile = writeSessionFile(
        'session.json',
        jsonEncode({
          'sessionId': 'fixture-session',
          'events': [
            {'tSec': 0.0, 'wavBase64': clip},
          ],
          'audioClips': [],
        }),
      );
      final output = fixturePath('bundle.json');

      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(File(output).readAsStringSync(), isNot(contains('wavBase64')));
    });

    test('a wavBase64 field nested outside "audioClips" still counts '
        'toward the size cap when --consent-raw-audio is given', () {
      final oversizedClip = base64Encode(deterministicPcm(5242880 + 1));
      final sessionFile = writeSessionFile(
        'session.json',
        jsonEncode({
          'sessionId': 'fixture-session',
          'events': [
            {'tSec': 0.0, 'wavBase64': oversizedClip},
          ],
          'audioClips': [],
        }),
      );
      final output = fixturePath('bundle.json');

      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
        consentRawAudio: true,
      );

      expect(result.exitCode, isNot(0));
      expect(File(output).existsSync(), isFalse);
    });
  });

  group('B1 — a malformed audio clip error never puts the surrounding '
      'session content on stderr', () {
    test('a clip missing "wavBase64", alongside all four D2 secret '
        'classes elsewhere in that same clip, fails with an index-only '
        'message — none of the secrets leak onto stderr', () {
      final sessionFile = writeSessionFile(
        'session.json',
        jsonEncode({
          'sessionId': 'fixture-session',
          'events': [],
          'audioClips': [
            {
              'tSec': 0.0,
              'diagToken': 'tok-fixture-should-not-leak',
              'contact': 'fixture-leak-probe@example.test',
              'file': '/home/fixture/Music/should-not-leak.wav',
              'deviceId': 'fixture-device-should-not-leak',
            },
          ],
        }),
      );
      final output = fixturePath('bundle.json');

      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
        consentRawAudio: true,
      );

      expect(result.exitCode, isNot(0));
      expect(File(output).existsSync(), isFalse);
      final stderr = result.stderr.toString();
      expect(stderr, isNot(contains('tok-fixture-should-not-leak')));
      expect(stderr, isNot(contains('fixture-leak-probe@example.test')));
      expect(
        stderr,
        isNot(contains('/home/fixture/Music/should-not-leak.wav')),
      );
      expect(stderr, isNot(contains('fixture-device-should-not-leak')));
      expect(stderr, contains('audioClips[0]'));
    });
  });

  group('M3 — gzip decompression is bounded (ADR 0486 D3.1): a small, '
      'highly-compressible upload that would decompress far past the '
      'session budget is rejected outright, not decompressed in full', () {
    test('a gzip payload that decompresses to well over the session cap '
        'is a non-zero exit, no output file, and no raw traceback on '
        'stderr', () {
      final oversized = utf8.encode('{"pad":"${'A' * (20 * 1024 * 1024)}"}');
      final sessionFile = writeBytes('bomb.json.gz', gzip.encode(oversized));
      final output = fixturePath('bundle.json');

      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
      );

      expect(result.exitCode, isNot(0));
      expect(File(output).existsSync(), isFalse);
      expect(result.stderr.toString(), isNot(contains('Traceback')));
    });
  });

  group('N1 — object KEYS go through the same email/path redaction as '
      'values, after token/device-id key classification (ADR 0486 D2.1)', () {
    test('an e-mail-shaped and a path-shaped map KEY are both masked, and '
        'the token-key classification still applies unchanged', () {
      final sessionFile = writeSessionFile(
        'session.json',
        jsonEncode({
          'sessionId': 'fixture-session',
          'events': [],
          'audioClips': [],
          'byKey': {
            '/home/fixture/Music/secret.wav': 'value-under-path-key',
            'fixture.tester@example.test': 'value-under-email-key',
            'authToken': 'value-under-token-key',
          },
        }),
      );
      final output = fixturePath('bundle.json');

      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final session = decodeBundle(output)['session']! as Map<String, Object?>;
      final byKey = session['byKey']! as Map<String, Object?>;
      expect(byKey.containsKey('[REDACTED:path]'), isTrue);
      expect(byKey.containsKey('[REDACTED:email]'), isTrue);
      expect(byKey['authToken'], '[REDACTED:token]');
      expect(byKey.keys, isNot(contains('/home/fixture/Music/secret.wav')));
      expect(byKey.keys, isNot(contains('fixture.tester@example.test')));
    });

    test('two distinct e-mail-shaped keys colliding onto the same '
        'redacted key is a non-zero exit, not a silently dropped entry', () {
      final sessionFile = writeSessionFile(
        'session.json',
        jsonEncode({
          'sessionId': 'fixture-session',
          'events': [],
          'audioClips': [],
          'byKey': {
            'fixture-a@example.test': 'v1',
            'fixture-b@example.test': 'v2',
          },
        }),
      );
      final output = fixturePath('bundle.json');

      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
      );

      expect(result.exitCode, isNot(0));
      expect(File(output).existsSync(), isFalse);
    });
  });

  group('N2 — the output file is written 0600 and refuses to follow a '
      'symlink at --output', () {
    test('the bundle file mode is 0600', () {
      final sessionFile = writeSessionFile('session.json', sessionJson());
      final output = fixturePath('bundle.json');
      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final mode = File(output).statSync().mode & 0x1ff;
      expect(mode, 0x180); // 0600 in octal.
    });

    test('a symlinked --output is refused — the link target is left '
        'untouched, never overwritten', () {
      final sessionFile = writeSessionFile('session.json', sessionJson());
      final victim = File(fixturePath('victim.txt'))
        ..writeAsStringSync('PRE-EXISTING');
      final link = Link(fixturePath('link.json'))..createSync(victim.path);

      final result = runBundle(
        sessionFile: sessionFile,
        output: link.path,
        consentDiagnostics: true,
      );

      expect(result.exitCode, isNot(0));
      expect(victim.readAsStringSync(), 'PRE-EXISTING');
    });
  });

  group('A4 — the four --consent-* input/output pairs, exactly as measured '
      '(round brief §0.0.A R5 / ADR 0486 D1)', () {
    late String sessionFile;
    setUp(() {
      sessionFile = writeSessionFile(
        'session.json',
        sessionJson(
          events: [
            {'tSec': 0.0, 'mlChord': 'C'},
          ],
          audioClips: [audioClip(16)],
        ),
      );
    });

    test('neither flag: non-zero exit, no output file at all', () {
      final output = fixturePath('bundle_neither.json');
      final result = runBundle(sessionFile: sessionFile, output: output);
      expect(result.exitCode, isNot(0));
      expect(File(output).existsSync(), isFalse);
    });

    test('only --consent-diagnostics: zero exit, bundle WITHOUT audio', () {
      final output = fixturePath('bundle_diag_only.json');
      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final session = decodeBundle(output)['session']! as Map<String, Object?>;
      expect(session.containsKey('audioClips'), isFalse);
    });

    // The exact mérce-mátrix regression: "audio consent alone still
    // assembles a bundle".
    test('only --consent-raw-audio (no --consent-diagnostics): non-zero '
        'exit, no output file — audio consent alone grants nothing', () {
      final output = fixturePath('bundle_audio_only.json');
      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentRawAudio: true,
      );
      expect(result.exitCode, isNot(0));
      expect(File(output).existsSync(), isFalse);
    });

    test('both flags: zero exit, bundle WITH audio', () {
      final output = fixturePath('bundle_both.json');
      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
        consentRawAudio: true,
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final session = decodeBundle(output)['session']! as Map<String, Object?>;
      expect(session.containsKey('audioClips'), isTrue);
    });
  });

  group('Input-shape coverage — the stored session payload is gzipped OR '
      'raw JSON, and the tool must handle both (round brief §0.0.A R2, the '
      'router stores whatever bytes it received verbatim)', () {
    test('a gzip-compressed session payload (the client\'s normal upload '
        'shape) is decompressed and redacted the same as raw JSON', () {
      final json = sessionJson(diagToken: 'gzip-fixture-secret-token');
      final sessionFile = writeBytes(
        'session.bin',
        gzip.encode(utf8.encode(json)),
      );
      final output = fixturePath('bundle.json');

      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final text = File(output).readAsStringSync();
      expect(text, isNot(contains('gzip-fixture-secret-token')));
      expect(text, contains('[REDACTED:token]'));
    });
  });

  group('A8 — the bundle JSON is canonical: keys sorted ascending at every '
      'nesting level, UTF-8, a single trailing newline, and two runs on the '
      'same input are byte-identical (ADR 0486 D4)', () {
    test('a session whose own JSON text writes keys out of alphabetical '
        'order still produces a bundle with keys sorted ascending — proof '
        'the tool actively sorts rather than passively preserving input '
        'order (mérce-mátrix: "keys land in traversal order")', () {
      // Hand-built, deliberately NOT alphabetically ordered.
      final unordered =
          '{"zField":"z","sessionId":"s1","appVersion":"1.0","device":"d",'
          '"startedAt":"t","surface":"analyze","aField":"a","events":[],'
          '"audioClips":[]}';
      final sessionFile = writeSessionFile('session.json', unordered);
      final output = fixturePath('bundle.json');

      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
      );

      expect(result.exitCode, 0, reason: result.stderr.toString());
      final decoded = decodeBundle(output);
      _expectSortedKeysRecursive(decoded);
    });

    test('the raw output bytes end in exactly one trailing newline and no '
        'other whitespace', () {
      final sessionFile = writeSessionFile('session.json', sessionJson());
      final output = fixturePath('bundle.json');
      runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
      );

      final bytes = File(output).readAsBytesSync();
      expect(bytes.last, 0x0a); // '\n'
      expect(bytes[bytes.length - 2], isNot(0x0a));
    });

    test('two runs against the identical session input are byte-identical', () {
      final sessionFile = writeSessionFile(
        'session.json',
        sessionJson(
          events: [
            {'tSec': 0.0, 'mlChord': 'C'},
          ],
        ),
      );
      final firstOutput = fixturePath('bundle_first.json');
      final secondOutput = fixturePath('bundle_second.json');

      final first = runBundle(
        sessionFile: sessionFile,
        output: firstOutput,
        consentDiagnostics: true,
      );
      final second = runBundle(
        sessionFile: sessionFile,
        output: secondOutput,
        consentDiagnostics: true,
      );

      expect(first.exitCode, 0, reason: first.stderr.toString());
      expect(second.exitCode, 0, reason: second.stderr.toString());
      expect(
        File(firstOutput).readAsBytesSync(),
        File(secondOutput).readAsBytesSync(),
      );
    });

    test('the bundle text has no ISO-8601-shaped timestamp anywhere', () {
      final sessionFile = writeSessionFile('session.json', sessionJson());
      final output = fixturePath('bundle.json');
      final result = runBundle(
        sessionFile: sessionFile,
        output: output,
        consentDiagnostics: true,
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());
      // startedAt is an intentional, INPUT-carried field — everything else
      // in the bundle must be free of a generation timestamp.
      final decoded = decodeBundle(output);
      final session = decoded['session']! as Map<String, Object?>;
      session.remove('startedAt');
      final text = jsonEncode(decoded);
      expect(
        text,
        isNot(matches(RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'))),
      );
    });
  });

  // -------------------------------------------------------------------
  // generate_beta_notes.py
  // -------------------------------------------------------------------

  String repeat(String char, int times) => List.filled(times, char).join();

  Map<String, Object?> manifestFixture({
    String? version = '1.2.3',
    int? buildNumber = 42,
    String? shortSha = 'abcdef1',
    String? channel = 'beta',
    bool includeApp = true,
  }) {
    final app = <String, Object?>{};
    if (version != null) app['version'] = version;
    if (buildNumber != null) app['buildNumber'] = buildNumber;
    if (shortSha != null) app['shortSha'] = shortSha;
    if (channel != null) app['channel'] = channel;

    return <String, Object?>{
      'schemaVersion': 1,
      if (includeApp) 'app': app,
      'modelPackage': <String, Object?>{
        'schemaVersion': 1,
        'manifestSha256': repeat('a', 64),
        'modelCount': 4,
      },
      'knowledgePackage': <String, Object?>{
        'schemaVersion': 1,
        'manifestSha256': repeat('b', 64),
        'documentCount': 10,
      },
      'artifacts': <Object?>[
        {
          'name': 'app-release.apk',
          'path': 'dist/app-release.apk',
          'sha256': repeat('c', 64),
        },
      ],
    };
  }

  ProcessResult runBetaNotes(String manifestPath) => Process.runSync(
    'python3',
    ['tool/release/generate_beta_notes.py', '--manifest', manifestPath],
  );

  group('A5 — the beta note is deterministic, carries the full build '
      'identifier + channel, and fails closed on a missing/malformed '
      'required manifest key (ADR 0486 D5)', () {
    test('the note contains app.version, app.buildNumber, app.shortSha and '
        'app.channel', () {
      final manifestPath = writeFile(
        'manifest.json',
        jsonEncode(manifestFixture()),
      );
      final result = runBetaNotes(manifestPath);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      final text = result.stdout as String;
      expect(text, contains('1.2.3'));
      expect(text, contains('42'));
      expect(text, contains('abcdef1'));
      expect(text, contains('beta'));
    });

    test('two runs against the identical manifest are byte-identical', () {
      final manifestPath = writeFile(
        'manifest.json',
        jsonEncode(manifestFixture()),
      );
      final first = runBetaNotes(manifestPath);
      final second = runBetaNotes(manifestPath);
      expect(first.exitCode, 0, reason: first.stderr.toString());
      expect(second.exitCode, 0, reason: second.stderr.toString());
      expect(first.stdout, second.stdout);
    });

    test('the note has no ISO-8601-shaped timestamp anywhere', () {
      final manifestPath = writeFile(
        'manifest.json',
        jsonEncode(manifestFixture()),
      );
      final result = runBetaNotes(manifestPath);
      expect(result.exitCode, 0, reason: result.stderr.toString());
      expect(
        result.stdout as String,
        isNot(matches(RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'))),
      );
    });

    // The exact mérce-mátrix regression: "missing app.shortSha continues
    // with an empty field" instead of failing closed.
    test('a manifest missing "app.shortSha" is a non-zero exit — not an '
        'empty/"unknown" field', () {
      final manifestPath = writeFile(
        'manifest.json',
        jsonEncode(manifestFixture(shortSha: null)),
      );
      final result = runBetaNotes(manifestPath);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('shortSha'));
      expect(result.stdout.toString(), isEmpty);
    });

    for (final field in ['version', 'buildNumber', 'shortSha', 'channel']) {
      test('a manifest missing "app.$field" is a non-zero exit naming it', () {
        final overrides = <String, Object?>{
          'version': '1.2.3',
          'buildNumber': 42,
          'shortSha': 'abcdef1',
          'channel': 'beta',
        }..[field] = null;
        final manifestPath = writeFile(
          'manifest.json',
          jsonEncode(
            manifestFixture(
              version: overrides['version'] as String?,
              buildNumber: overrides['buildNumber'] as int?,
              shortSha: overrides['shortSha'] as String?,
              channel: overrides['channel'] as String?,
            ),
          ),
        );
        final result = runBetaNotes(manifestPath);
        expect(result.exitCode, isNot(0));
        expect(result.stderr.toString(), contains(field));
      });
    }

    test('app.buildNumber given as a string (wrong type) is a non-zero '
        'exit, not a silently coerced value', () {
      final manifest = manifestFixture();
      (manifest['app']! as Map<String, Object?>)['buildNumber'] = '42';
      final manifestPath = writeFile('manifest.json', jsonEncode(manifest));
      final result = runBetaNotes(manifestPath);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('buildNumber'));
    });

    test('a missing "modelPackage" object is a non-zero exit', () {
      final manifest = manifestFixture();
      manifest.remove('modelPackage');
      final manifestPath = writeFile('manifest.json', jsonEncode(manifest));
      final result = runBetaNotes(manifestPath);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('modelPackage'));
    });

    test('a missing "knowledgePackage" object is a non-zero exit', () {
      final manifest = manifestFixture();
      manifest.remove('knowledgePackage');
      final manifestPath = writeFile('manifest.json', jsonEncode(manifest));
      final result = runBetaNotes(manifestPath);
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains('knowledgePackage'));
    });
  });

  // -------------------------------------------------------------------
  // A6 — docs/beta/tester-consent.md machine crosscheck against the Kör 17
  // data-inventory, both directions (ADR 0486 D6).
  // -------------------------------------------------------------------

  group('A6 — docs/beta/tester-consent.md\'s machine block matches '
      'docs/privacy/data-inventory.yaml\'s leaves_device: true fields, '
      'bidirectionally (ADR 0486 D6)', () {
    DataInventory realInventory() =>
        DataInventory.parseFile(File('docs/privacy/data-inventory.yaml'));

    Set<String> leavesDevicePairs(DataInventory inventory) {
      final pairs = <String>{};
      for (final route in inventory.routes) {
        for (final field in route.fields) {
          if (field.leavesDevice) {
            pairs.add('${route.id}\u0000${field.name}');
          }
        }
      }
      return pairs;
    }

    Set<String> docPairs(String markdown) => _parseCrosscheckBlock(
      markdown,
    ).map((row) => '${row[0]}\u0000${row[1]}').toSet();

    test('the real tester-consent.md block matches the real inventory in '
        'both directions', () {
      final expected = leavesDevicePairs(realInventory());
      final markdown = File('docs/beta/tester-consent.md').readAsStringSync();
      final actual = docPairs(markdown);

      final missing = expected.difference(actual);
      final extra = actual.difference(expected);
      expect(
        missing,
        isEmpty,
        reason: 'doc is missing leaves_device:true rows: $missing',
      );
      expect(
        extra,
        isEmpty,
        reason: 'doc lists rows the inventory does not declare: $extra',
      );
    });

    test('the measured route/field counts are exactly account_api (6), '
        'diagnostics_upload (3), share_export (3) — 12 pairs total (round '
        'brief §0.0.A R2)', () {
      final expected = leavesDevicePairs(realInventory());
      expect(
        expected.where((p) => p.startsWith('account_api\u0000')).length,
        6,
      );
      expect(
        expected.where((p) => p.startsWith('diagnostics_upload\u0000')).length,
        3,
      );
      expect(
        expected.where((p) => p.startsWith('share_export\u0000')).length,
        3,
      );
      expect(expected.length, 12);
    });

    test('a synthetic doc block missing one real row is caught (the '
        '"missing" direction)', () {
      final expected = leavesDevicePairs(realInventory()).toList();
      final droppedOne = expected
          .skip(1)
          .map((p) => p.split('\u0000'))
          .toList();
      final markdown = _crosscheckMarkdown(droppedOne);

      final missing = leavesDevicePairs(
        realInventory(),
      ).difference(docPairs(markdown));
      expect(missing, isNotEmpty);
    });

    // The exact mérce-mátrix regression: "the document block lists a field
    // name the inventory does not have".
    test('a synthetic doc block with an invented field name is caught (the '
        '"extra" / reverse direction — mérce-mátrix row)', () {
      final rows =
          leavesDevicePairs(
              realInventory(),
            ).map((p) => p.split('\u0000')).toList()
            ..add(['account_api', 'totally_invented_field_name']);
      final markdown = _crosscheckMarkdown(rows);

      final extra = docPairs(
        markdown,
      ).difference(leavesDevicePairs(realInventory()));
      expect(extra, contains('account_api\u0000totally_invented_field_name'));
    });

    test('a synthetic doc block pointing a real field at the wrong route '
        'id is caught by the reverse direction too', () {
      final rows =
          leavesDevicePairs(realInventory())
              .where((p) => !p.startsWith('account_api\u0000email'))
              .map((p) => p.split('\u0000'))
              .toList()
            ..add(['diagnostics_upload', 'email']); // real field, wrong route
      final markdown = _crosscheckMarkdown(rows);

      final report = leavesDevicePairs(realInventory());
      expect(docPairs(markdown).difference(report), isNotEmpty);
      expect(report.difference(docPairs(markdown)), isNotEmpty);
    });
  });

  group('This gate never relies on an unguaranteed or forbidden binary '
      '(benchmark_budget_test.dart L110 pattern)', () {
    test('every external process this file spawns targets python3 only — '
        'never rg/grep/jq/gh/git', () {
      final source = File(
        'test/tooling/beta_release_notes_test.dart',
      ).readAsStringSync();
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

/// Recursively asserts every object in [value] has ascending-sorted keys —
/// mirrors `release_manifest_test.dart`'s `_expectSortedKeys`.
void _expectSortedKeysRecursive(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList();
    final sortedKeys = [...keys]..sort();
    expect(keys, sortedKeys, reason: 'object keys must be sorted ascending');
    for (final nested in value.values) {
      _expectSortedKeysRecursive(nested);
    }
  } else if (value is List) {
    for (final item in value) {
      _expectSortedKeysRecursive(item);
    }
  }
}

/// Parses the `<!-- data-inventory-crosscheck:begin/end -->` markdown table
/// block into `[route, field]` row pairs — the same fenced-table-marker
/// pattern `ai_release_report_test.dart`'s pinned-coverage group already
/// uses for `docs/release/ai-quality-gates.md`.
List<List<String>> _parseCrosscheckBlock(String markdown) {
  const beginMarker = '<!-- data-inventory-crosscheck:begin -->';
  const endMarker = '<!-- data-inventory-crosscheck:end -->';
  if (!markdown.contains(beginMarker) || !markdown.contains(endMarker)) {
    fail(
      'docs/beta/tester-consent.md is missing its machine-readable '
      'data-inventory-crosscheck markers',
    );
  }
  final block = markdown.split(beginMarker)[1].split(endMarker)[0];
  final rows = block
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.startsWith('|'))
      .skip(2); // header row, then the "|---|---|" separator row
  return rows.map((line) {
    final cells = line.split('|').map((cell) => cell.trim()).toList();
    // cells[0] is '' (before the leading "|"); cells[1]=route, cells[2]=field.
    return [cells[1], cells[2]];
  }).toList();
}

/// Builds a synthetic `data-inventory-crosscheck` markdown fragment from
/// `[route, field]` row pairs, for the negative (missing/invented-row)
/// probes above — the real file is asserted against separately.
String _crosscheckMarkdown(List<List<String>> rows) {
  final buffer = StringBuffer()
    ..writeln('<!-- data-inventory-crosscheck:begin -->')
    ..writeln('| route | field |')
    ..writeln('|---|---|');
  for (final row in rows) {
    buffer.writeln('| ${row[0]} | ${row[1]} |');
  }
  buffer.writeln('<!-- data-inventory-crosscheck:end -->');
  return buffer.toString();
}

// Built via adjacent string-literal concatenation so this constant's own
// definition text never spells out the executable-call pattern it searches
// for as one contiguous run of characters (the same construction
// `ai_release_report_test.dart`/`release_manifest_test.dart` use, for the
// same reason — otherwise the self-check group above would match its own
// regex source).
final _processCallExecutable = RegExp(
  'Process'
  r'''\.(?:run|runSync|start)\(\s*['"]([^'"\n]+)['"]''',
);
