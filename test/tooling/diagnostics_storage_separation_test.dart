import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/diagnostics/data/diagnostics_uploader.dart';

/// E01-R07 §7.5 — the diagnostics payload stays OUT of the user-content store.
///
/// Lab-mode diagnostics carry recorded audio (a base64 WAV, up to
/// [DiagnosticsUploader.maxWavBytes]). The local documents this round moved —
/// songs, library, practice log, streak — are small, unbounded-lifetime user
/// content read on every boot. Mixing the two would put megabytes of audio in
/// the boot path and, far worse, persist raw audio on the device by default.
///
/// The separation is structural (diagnostics posts, it never stores), so this
/// guard exists to keep it that way.
void main() {
  test('no diagnostics file touches the key-value storage layer', () {
    final offenders = <String>[];
    for (final entity in Directory(
      'lib/features/diagnostics',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('core/storage/') ||
          source.contains('KeyValueStore') ||
          source.contains('StorageKeys')) {
        offenders.add(entity.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'a diagnostics payload is uploaded, never persisted next to the '
          "user's songs — raw audio must not land in local storage",
    );
  });

  test('no persisted key is a diagnostics/audio payload', () {
    for (final key in StorageKeys.all) {
      expect(
        key,
        isNot(anyOf(contains('diag'), contains('pcm'), contains('wav'))),
        reason: 'the key catalogue holds user content and preferences only',
      );
    }
  });

  test('the upload payload keeps its own, much larger bound', () {
    // Documented next to the document caps so the two are never confused: the
    // upload cap is per-request, in memory, and opt-in behind Lab mode.
    expect(DiagnosticsUploader.maxWavBytes, 5 * 1024 * 1024);
  });
}
