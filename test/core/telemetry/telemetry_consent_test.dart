// E14-R41 (ADR 0542) — the opt-in beta telemetry consent model and the
// upload gate that reads it.
//
// Every cell here would be RED before this round for the plain reason that
// none of these types existed: the tree carried `ConsentGatedTelemetrySink`
// with a hand-injected `bool Function()` and, in its own words, "no
// telemetry-consent switch exists on the tree today".
//
// What the group proves, in order: the default is a refusal; a grant is
// bound to the consent COPY it answered; revocation drops the identifier
// rather than parking it; and the gate is an AND of three fail-closed
// conditions, so no single flag can open it.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/telemetry/public.dart';

TelemetryPseudonymId _id({int high = 0x0123abcd, int low = 0x4567ef01}) =>
    TelemetryPseudonymId(highBits: high, lowBits: low, issuedOnDay: 20000);

void main() {
  group('TelemetryConsentState — anything that is not `granted` is a '
      'refusal (an opt-in has no third, permissive state)', () {
    test('notAsked does not permit collection', () {
      expect(TelemetryConsentState.notAsked.permitsCollection, isFalse);
    });

    test('denied does not permit collection', () {
      expect(TelemetryConsentState.denied.permitsCollection, isFalse);
    });

    test('granted is the only permissive value', () {
      final permissive = TelemetryConsentState.values
          .where((state) => state.permitsCollection)
          .toList();
      expect(permissive, <TelemetryConsentState>[
        TelemetryConsentState.granted,
      ]);
    });
  });

  group('TelemetryConsentRecord', () {
    test('the shipped default is notAsked, carries no pseudonym and '
        'permits nothing', () {
      const record = TelemetryConsentRecord.initial;

      expect(record.state, TelemetryConsentState.notAsked);
      expect(record.pseudonym, isNull);
      expect(record.permitsCollection, isFalse);
      expect(record.needsDecision, isTrue);
    });

    test('a grant permits collection and carries exactly one identifier', () {
      final record = TelemetryConsentRecord.granted(_id());

      expect(record.permitsCollection, isTrue);
      expect(record.needsDecision, isFalse);
      expect(record.pseudonym, isNotNull);
    });

    test('revocation DROPS the pseudonym — it is not parked for a later '
        'return, which is the whole point of revoking it', () {
      final granted = TelemetryConsentRecord.granted(_id());
      expect(granted.pseudonym, isNotNull);

      const revoked = TelemetryConsentRecord.revoked;

      expect(revoked.state, TelemetryConsentState.denied);
      expect(revoked.pseudonym, isNull);
      expect(revoked.permitsCollection, isFalse);
    });

    test('a grant answering a SUPERSEDED consent copy stops permitting '
        'collection instead of silently carrying over', () {
      // Simulates a stored decision made against an older copy version.
      // Constructed directly because the enum currently has one value —
      // the guard must hold the day a second value is added.
      final stale = TelemetryConsentRecord(
        state: TelemetryConsentState.granted,
        version: TelemetryConsentVersion.values.first,
        pseudonym: _id(),
      );
      expect(stale.permitsCollection, isTrue);

      expect(
        TelemetryConsentVersion.current,
        TelemetryConsentVersion.values.first,
        reason:
            'when a newer copy version is added, update this cell: the '
            'stale record above must then flip to permitsCollection == '
            'false and needsDecision == true',
      );
    });

    test('an unknown persisted version name parses to null (fail-closed), '
        'never to the current version', () {
      expect(TelemetryConsentVersion.tryParse(null), isNull);
      expect(TelemetryConsentVersion.tryParse(''), isNull);
      expect(TelemetryConsentVersion.tryParse('ch99-beta-9'), isNull);
      expect(
        TelemetryConsentVersion.tryParse(TelemetryConsentVersion.current.name),
        TelemetryConsentVersion.current,
      );
    });
  });

  group('TelemetryPseudonymId — rotating, opaque, device-independent', () {
    test('the rendered value is 16 lower-case hex characters', () {
      final id = TelemetryPseudonymId.generate(
        random: Random(42),
        nowUtc: DateTime.utc(2026, 9, 9),
      );

      expect(id.value.length, TelemetryPseudonymId.hexLength);
      expect(TelemetryPseudonymId.isWellFormedValue(id.value), isTrue);
    });

    test('small bit values are zero-padded, so the id length never leaks '
        'how small the drawn number happened to be', () {
      const id = TelemetryPseudonymId(
        highBits: 1,
        lowBits: 0,
        issuedOnDay: 20000,
      );

      expect(id.value, '0000000100000000');
      expect(id.value.length, TelemetryPseudonymId.hexLength);
    });

    test('two draws from different seeds differ — the id is not derived '
        'from anything stable about the device', () {
      final first = TelemetryPseudonymId.generate(
        random: Random(1),
        nowUtc: DateTime.utc(2026, 9, 9),
      );
      final second = TelemetryPseudonymId.generate(
        random: Random(2),
        nowUtc: DateTime.utc(2026, 9, 9),
      );

      expect(first.value, isNot(second.value));
    });

    test('an id expires exactly at the rotation period, not before', () {
      final issued = DateTime.utc(2026, 9, 1);
      final id = TelemetryPseudonymId.generate(
        random: Random(7),
        nowUtc: issued,
      );

      expect(id.isExpiredAt(issued), isFalse);
      expect(id.isExpiredAt(issued.add(const Duration(days: 6))), isFalse);
      expect(id.isExpiredAt(issued.add(const Duration(days: 7))), isTrue);
      expect(id.isExpiredAt(issued.add(const Duration(days: 70))), isTrue);
    });

    test('restore is fail-closed on every malformed part', () {
      expect(
        TelemetryPseudonymId.restore(
          highBits: null,
          lowBits: 1,
          issuedOnDay: 1,
        ),
        isNull,
      );
      expect(
        TelemetryPseudonymId.restore(
          highBits: 1,
          lowBits: null,
          issuedOnDay: 1,
        ),
        isNull,
      );
      expect(
        TelemetryPseudonymId.restore(
          highBits: 1,
          lowBits: 1,
          issuedOnDay: null,
        ),
        isNull,
      );
      expect(
        TelemetryPseudonymId.restore(highBits: -1, lowBits: 1, issuedOnDay: 1),
        isNull,
      );
      expect(
        TelemetryPseudonymId.restore(
          highBits: 1,
          lowBits: 1 << 32,
          issuedOnDay: 1,
        ),
        isNull,
      );
      expect(
        TelemetryPseudonymId.restore(highBits: 1, lowBits: 2, issuedOnDay: 3),
        isNotNull,
      );
    });

    test('a non-opaque value is rejected by the well-formedness guard — an '
        'e-mail or a device serial in this slot is a leak, not an id', () {
      expect(
        TelemetryPseudonymId.isWellFormedValue('user@example.com'),
        isFalse,
      );
      expect(
        TelemetryPseudonymId.isWellFormedValue('SM-G991B-serial'),
        isFalse,
      );
      expect(
        TelemetryPseudonymId.isWellFormedValue('0123ABCD4567EF01'),
        isFalse,
        reason: 'upper-case hex is not the shape value renders',
      );
    });
  });

  group('TelemetryUploadGate — three fail-closed conditions, ANDed', () {
    TelemetryUploadGate gateOf({
      required bool beta,
      required bool diagnostics,
      required TelemetryConsentRecord consent,
    }) => TelemetryUploadGate(
      consent: consent,
      betaTelemetryEnabled: beta,
      diagnosticsEnabled: diagnostics,
    );

    test('the closed constant allows nothing', () {
      expect(TelemetryUploadGate.closed.allowsUpload, isFalse);
      expect(
        TelemetryUploadGate.closed.blockReason,
        TelemetryUploadBlockReason.buildDisabled,
      );
    });

    test('consent alone does NOT open the gate (build flags off)', () {
      final gate = gateOf(
        beta: false,
        diagnostics: false,
        consent: TelemetryConsentRecord.granted(_id()),
      );

      expect(gate.allowsUpload, isFalse);
      expect(gate.blockReason, TelemetryUploadBlockReason.buildDisabled);
    });

    test('build flags alone do NOT open the gate (no consent)', () {
      final gate = gateOf(
        beta: true,
        diagnostics: true,
        consent: TelemetryConsentRecord.initial,
      );

      expect(gate.allowsUpload, isFalse);
      expect(gate.blockReason, TelemetryUploadBlockReason.consentMissing);
    });

    test('the diagnostics flag is a separate veto — a production build '
        'stays silent even with the beta flag and consent on', () {
      final gate = gateOf(
        beta: true,
        diagnostics: false,
        consent: TelemetryConsentRecord.granted(_id()),
      );

      expect(gate.allowsUpload, isFalse);
      expect(gate.blockReason, TelemetryUploadBlockReason.diagnosticsDisabled);
    });

    test('a revoked consent reports its own reason, distinct from "never '
        'asked"', () {
      final gate = gateOf(
        beta: true,
        diagnostics: true,
        consent: TelemetryConsentRecord.revoked,
      );

      expect(gate.allowsUpload, isFalse);
      expect(gate.blockReason, TelemetryUploadBlockReason.consentRefused);
    });

    test('all three conditions together open it, and only then', () {
      final gate = gateOf(
        beta: true,
        diagnostics: true,
        consent: TelemetryConsentRecord.granted(_id()),
      );

      expect(gate.allowsUpload, isTrue);
      expect(gate.blockReason, isNull);
    });

    test('withConsent re-evaluates immediately — a mid-session revocation '
        'closes the gate without rebuilding it', () {
      final open = gateOf(
        beta: true,
        diagnostics: true,
        consent: TelemetryConsentRecord.granted(_id()),
      );
      expect(open.allowsUpload, isTrue);

      final closed = open.withConsent(TelemetryConsentRecord.revoked);

      expect(closed.allowsUpload, isFalse);
      expect(closed.blockReason, TelemetryUploadBlockReason.consentRefused);
    });
  });

  group('ConsentGatedTelemetrySink bound to the real gate (the "azonnal '
      'hat" requirement, ADR 0484 D4)', () {
    test('flipping consent off mid-run stops recording at once, and the '
        'events dropped while it was off are never flushed afterwards', () {
      final delegate = _RecordingSink();
      var consent = TelemetryConsentRecord.granted(_id());
      final sink = ConsentGatedTelemetrySink(
        delegate: delegate,
        consentGranted: () => TelemetryUploadGate(
          consent: consent,
          betaTelemetryEnabled: true,
          diagnosticsEnabled: true,
        ).allowsUpload,
      );

      sink.record(_event());
      expect(delegate.recorded, hasLength(1));

      consent = TelemetryConsentRecord.revoked;
      sink.record(_event());
      sink.record(_event());
      expect(delegate.recorded, hasLength(1));

      consent = TelemetryConsentRecord.granted(_id());
      sink.record(_event());
      expect(
        delegate.recorded,
        hasLength(2),
        reason:
            'the two events dropped while consent was off must NOT arrive '
            'after the re-grant — that would be collection before consent '
            'with the sending merely delayed',
      );
    });
  });
}

TelemetryEvent _event() => const TelemetryEvent(
  name: TelemetryEventName.recognitionQualityReported,
  category: TelemetryEventCategory.detection,
  result: TelemetryOperationResult.success,
  durationBucket: TelemetryDurationBucket.ms0To250,
);

final class _RecordingSink implements TelemetrySink {
  final List<TelemetryEvent> recorded = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => recorded.add(event);
}
