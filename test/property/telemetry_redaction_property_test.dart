// E14-R41 (ADR 0542) — allowlist-redaction property for the opt-in beta
// recognition telemetry, mirroring the E06-R27 pattern in
// `analysis_export_redaction_property_test.dart` (ADR 0247).
//
// The core assertion measures the KEY-SET DIFFERENCE between the encoded
// payload and a fixed, independently-declared allowlist — not a pattern
// match against the implementation. A denylist encoder would still pass a
// pattern-matching test for the field it happens to know about; it fails
// this one because it forwards every key it has NOT heard of, growing the
// observed key set past the allowlist.
//
// Randomization follows the HORIZON gate: `PROPERTY_SEED` from the
// environment, seed 42 when absent (deterministic dev loop), CI re-runs it
// with the run id.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/telemetry/public.dart';

/// Every key the encoder is allowed to emit, at any nesting depth.
/// Declared here INDEPENDENTLY of `RecognitionTelemetryCodec.allowedKeys` —
/// a change to the codec that adds an unreviewed key must fail this test,
/// which it cannot do if the test reads the codec's own list.
const Set<String> _allowedKeys = <String>{
  'schemaVersion',
  'pseudonymId',
  'band',
  'model',
  'qualityBucket',
  'acceptedCountBucket',
  'rejectedCountBucket',
  'verdictLatencyBucket',
  'userCorrected',
  'rolloutStage',
  'sessionSurface',
};

/// Payloads that must never survive encoding, whatever key they arrive
/// under. Every one of them names a category SDD Ch14 §9 / ADR 0484 D1
/// forbids: raw audio, a filename, a device identifier, free user text and
/// an internal diagnostic trace.
const Map<String, String> _forbiddenPayloads = <String, String>{
  'rawPcm': 'RIFF....WAVEfmt sneaky-pcm-payload-bytes',
  'importedFileName': 'private-family-recording-do-not-share.wav',
  'deviceId': 'unique-hardware-serial-9f8e7d',
  'userNote': 'my band rehearsal, Tuesday, at Kate/s place',
  'decoderTrace': 'lab-trace-secret-decoder-residual-0.42',
};

Set<String> _collectKeys(Object? value) {
  final keys = <String>{};
  if (value is Map) {
    for (final entry in value.entries) {
      keys.add(entry.key as String);
      keys.addAll(_collectKeys(entry.value));
    }
  } else if (value is List) {
    for (final item in value) {
      keys.addAll(_collectKeys(item));
    }
  }
  return keys;
}

RecognitionTelemetryEnvelope _envelope(math.Random random) {
  const bands = RecognitionTelemetryBand.values;
  const models = RecognitionTelemetryModel.values;
  const qualities = RecognitionTelemetryQualityBucket.values;
  const counts = RecognitionTelemetryCountBucket.values;
  const latencies = TelemetryDurationBucket.values;
  return RecognitionTelemetryEnvelope(
    event: RecognitionTelemetryEvent(
      band: bands[random.nextInt(bands.length)],
      model: models[random.nextInt(models.length)],
      qualityBucket: qualities[random.nextInt(qualities.length)],
      acceptedCount: counts[random.nextInt(counts.length)],
      rejectedCount: counts[random.nextInt(counts.length)],
      verdictLatencyBucket: latencies[random.nextInt(latencies.length)],
      userCorrected: random.nextBool(),
    ),
    pseudonym: TelemetryPseudonymId.generate(
      random: random,
      nowUtc: DateTime.utc(2026, 9, 9),
    ),
  );
}

void main() {
  final seed = int.tryParse(Platform.environment['PROPERTY_SEED'] ?? '') ?? 42;

  test('allowlist-redaction property: the encoded key set never exceeds the '
      'declared allowlist across randomized aggregates, however much '
      'unreviewed context the caller attaches', () {
    for (var trial = 0; trial < 200; trial += 1) {
      final random = math.Random(seed + trial * 7919);
      final envelope = _envelope(random);
      // A caller that dumps whatever it has: allowlisted keys, unreviewed
      // keys, and the five forbidden payload categories, all at once.
      final context = <String, Object?>{
        'rolloutStage': 'shadow',
        'sessionSurface': 'live',
        'unreviewedField$trial': 'value-$trial',
        ..._forbiddenPayloads,
      };

      final encoded = RecognitionTelemetryCodec.encode(
        envelope,
        diagnosticContext: context,
      );
      final observed = _collectKeys(encoded);
      final unexpected = observed.difference(_allowedKeys);

      expect(
        unexpected,
        isEmpty,
        reason: 'seed=$seed trial=$trial leaked keys: $unexpected',
      );
    }
  });

  test('forbidden-content property: no forbidden payload VALUE appears in '
      'the serialized output, under any key, across randomized '
      'aggregates', () {
    for (var trial = 0; trial < 200; trial += 1) {
      final random = math.Random(seed + trial * 104729);
      final encoded = jsonEncode(
        RecognitionTelemetryCodec.encode(
          _envelope(random),
          diagnosticContext: <String, Object?>{
            // Injected under BOTH an unknown key and an allowlisted one:
            // an allowlisted key must not become a smuggling route just
            // because its name was reviewed once.
            ..._forbiddenPayloads,
            'rolloutStage': _forbiddenPayloads['deviceId'],
            'sessionSurface': _forbiddenPayloads['importedFileName'],
          },
        ),
      );

      for (final payload in _forbiddenPayloads.values) {
        expect(
          encoded.contains(payload),
          isFalse,
          reason: 'seed=$seed trial=$trial leaked payload: $payload',
        );
      }
    }
  });

  test('identifier property: exactly one identifier is emitted and it is '
      'always the opaque rotating pseudonym', () {
    for (var trial = 0; trial < 200; trial += 1) {
      final random = math.Random(seed + trial * 15485863);
      final envelope = _envelope(random);
      final encoded = RecognitionTelemetryCodec.encode(envelope);

      final identifierKeys = encoded.keys
          .where((key) => key.toLowerCase().contains('id'))
          .toList();

      expect(
        identifierKeys,
        <String>['pseudonymId'],
        reason: 'seed=$seed trial=$trial',
      );
      expect(
        TelemetryPseudonymId.isWellFormedValue(
          encoded['pseudonymId']! as String,
        ),
        isTrue,
        reason: 'seed=$seed trial=$trial',
      );
    }
  });
}
