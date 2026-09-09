// E14-R41 (ADR 0542 D5) — the recognition-aggregate event contract.
//
// The plan's R41 §2 asks for "model version, quality bucket,
// accepted/rejected count, latency, user correction flag". These cells pin
// the SHAPE those five arrive in: closed enums and buckets, never a raw
// count, never a raw millisecond value, never a free model-version string.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/telemetry/public.dart';

RecognitionTelemetryEvent _event({
  RecognitionTelemetryModel model = RecognitionTelemetryModel.strumCrnnLive3c,
  bool userCorrected = false,
}) => RecognitionTelemetryEvent(
  band: RecognitionTelemetryBand.strumDirection,
  model: model,
  qualityBucket: RecognitionTelemetryQualityBucket.fair,
  acceptedCount: RecognitionTelemetryCountBucket.c5To19,
  rejectedCount: RecognitionTelemetryCountBucket.c1To4,
  verdictLatencyBucket: TelemetryDurationBucket.ms250To500,
  userCorrected: userCorrected,
);

const _pseudonym = TelemetryPseudonymId(
  highBits: 0x0123abcd,
  lowBits: 0x4567ef01,
  issuedOnDay: 20000,
);

void main() {
  group('RecognitionTelemetryCountBucket — bucketed, never raw', () {
    test('boundaries are inclusive on the lower edge', () {
      expect(
        RecognitionTelemetryCountBucket.fromCount(0),
        RecognitionTelemetryCountBucket.none,
      );
      expect(
        RecognitionTelemetryCountBucket.fromCount(1),
        RecognitionTelemetryCountBucket.c1To4,
      );
      expect(
        RecognitionTelemetryCountBucket.fromCount(4),
        RecognitionTelemetryCountBucket.c1To4,
      );
      expect(
        RecognitionTelemetryCountBucket.fromCount(5),
        RecognitionTelemetryCountBucket.c5To19,
      );
      expect(
        RecognitionTelemetryCountBucket.fromCount(19),
        RecognitionTelemetryCountBucket.c5To19,
      );
      expect(
        RecognitionTelemetryCountBucket.fromCount(20),
        RecognitionTelemetryCountBucket.c20To99,
      );
      expect(
        RecognitionTelemetryCountBucket.fromCount(99),
        RecognitionTelemetryCountBucket.c20To99,
      );
      expect(
        RecognitionTelemetryCountBucket.fromCount(100),
        RecognitionTelemetryCountBucket.c100AndAbove,
      );
      expect(
        RecognitionTelemetryCountBucket.fromCount(1000000),
        RecognitionTelemetryCountBucket.c100AndAbove,
      );
    });

    test('a negative count is rejected rather than bucketed into `none`', () {
      expect(
        () => RecognitionTelemetryCountBucket.fromCount(-1),
        throwsArgumentError,
      );
    });
  });

  group('envelopeEvent — the aggregate reports as one catalogued event', () {
    test('it is the recognitionQualityReported detection event', () {
      final event = _event().envelopeEvent;

      expect(event.name, TelemetryEventName.recognitionQualityReported);
      expect(event.category, TelemetryEventCategory.detection);
      expect(event.durationBucket, TelemetryDurationBucket.ms250To500);
    });

    test('the DSP path reports onDeviceDsp, every model asset reports '
        'onDeviceMl — so "which recogniser ran" never needs a version '
        'string', () {
      expect(
        _event(model: RecognitionTelemetryModel.nnlsChroma)
            .envelopeEvent
            .capability,
        TelemetryCapability.onDeviceDsp,
      );
      for (final model in <RecognitionTelemetryModel>[
        RecognitionTelemetryModel.strumCrnn,
        RecognitionTelemetryModel.strumCrnnLive,
        RecognitionTelemetryModel.strumCrnnLive3c,
        RecognitionTelemetryModel.chordCrnn,
      ]) {
        expect(
          _event(model: model).envelopeEvent.capability,
          TelemetryCapability.onDeviceMl,
          reason: '${model.name} runs an on-device model asset',
        );
      }
    });
  });

  group('RecognitionTelemetryCodec', () {
    test('the encoded key set is exactly the declared allowlist minus the '
        'optional context keys', () {
      final encoded = RecognitionTelemetryCodec.encode(
        RecognitionTelemetryEnvelope(event: _event(), pseudonym: _pseudonym),
      );

      expect(
        encoded.keys.toSet().difference(RecognitionTelemetryCodec.allowedKeys),
        isEmpty,
      );
      expect(encoded['band'], 'strumDirection');
      expect(encoded['model'], 'strumCrnnLive3c');
      expect(encoded['qualityBucket'], 'fair');
      expect(encoded['acceptedCountBucket'], 'c5To19');
      expect(encoded['rejectedCountBucket'], 'c1To4');
      expect(encoded['verdictLatencyBucket'], 'ms250To500');
      expect(encoded['userCorrected'], isFalse);
      expect(encoded['pseudonymId'], _pseudonym.value);
      expect(
        encoded['schemaVersion'],
        RecognitionTelemetryCodec.schemaVersion,
      );
    });

    test('the only identifier on the wire is the rotating pseudonym, and it '
        'is opaque-shaped', () {
      final encoded = RecognitionTelemetryCodec.encode(
        RecognitionTelemetryEnvelope(event: _event(), pseudonym: _pseudonym),
      );
      final identifiers = encoded.entries
          .where((entry) => entry.key.toLowerCase().contains('id'))
          .toList();

      expect(identifiers, hasLength(1));
      expect(identifiers.single.key, 'pseudonymId');
      expect(
        TelemetryPseudonymId.isWellFormedValue(
          identifiers.single.value! as String,
        ),
        isTrue,
      );
    });

    test('an allowlisted context key survives; an unknown one is DROPPED, '
        'not forwarded (allowlist, not denylist)', () {
      final encoded = RecognitionTelemetryCodec.encode(
        RecognitionTelemetryEnvelope(event: _event(), pseudonym: _pseudonym),
        diagnosticContext: const <String, Object?>{
          'rolloutStage': 'shadow',
          'brandNewUnreviewedField': 'sneaky-value-should-never-leak',
        },
      );

      expect(encoded['rolloutStage'], 'shadow');
      expect(encoded.containsKey('brandNewUnreviewedField'), isFalse);
      expect(encoded.values, isNot(contains('sneaky-value-should-never-leak')));
    });

    test('a nested map or list under an ALLOWLISTED key is dropped too — a '
        'permitted key is not a permitted subtree', () {
      final encoded = RecognitionTelemetryCodec.encode(
        RecognitionTelemetryEnvelope(event: _event(), pseudonym: _pseudonym),
        diagnosticContext: const <String, Object?>{
          'rolloutStage': <String, Object?>{'deviceId': 'serial-9f8e7d'},
          'sessionSurface': <String>['/private/path/take-1.wav'],
        },
      );

      expect(encoded.containsKey('rolloutStage'), isFalse);
      expect(encoded.containsKey('sessionSurface'), isFalse);
    });

    test('an allowlisted KEY is not an allowlisted VALUE: a filename, a '
        'serial or a sentence under a reviewed key is DROPPED, because the '
        'key name is reviewed once and the content never is', () {
      final encoded = RecognitionTelemetryCodec.encode(
        RecognitionTelemetryEnvelope(event: _event(), pseudonym: _pseudonym),
        diagnosticContext: const <String, Object?>{
          'rolloutStage': 'private-family-recording-do-not-share.wav',
          'sessionSurface': 'unique-hardware-serial-9f8e7d',
        },
      );

      expect(encoded.containsKey('rolloutStage'), isFalse);
      expect(encoded.containsKey('sessionSurface'), isFalse);
    });

    test('an over-long value under an allowlisted key is dropped by the '
        'token-shape rule before the redactor ever truncates it', () {
      final encoded = RecognitionTelemetryCodec.encode(
        RecognitionTelemetryEnvelope(event: _event(), pseudonym: _pseudonym),
        diagnosticContext: <String, Object?>{'sessionSurface': 'x' * 250},
      );

      expect(encoded.containsKey('sessionSurface'), isFalse);
    });

    test('an enum-name-shaped token under an allowlisted key survives — the '
        'rule narrows what may pass, it does not empty the channel', () {
      final encoded = RecognitionTelemetryCodec.encode(
        RecognitionTelemetryEnvelope(event: _event(), pseudonym: _pseudonym),
        diagnosticContext: const <String, Object?>{
          'rolloutStage': 'shadow',
          'sessionSurface': 'live',
        },
      );

      expect(encoded['rolloutStage'], 'shadow');
      expect(encoded['sessionSurface'], 'live');
    });
  });
}
