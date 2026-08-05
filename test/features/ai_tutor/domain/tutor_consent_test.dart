import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_consent.dart';

void main() {
  group('TutorConsent', () {
    test('keeps the three consent axes independent', () {
      const consent = TutorConsent(
        modelUseGranted: true,
        persistentStorageGranted: false,
        evaluationWithRedactionGranted: false,
      );

      expect(consent.modelUseGranted, isTrue);
      expect(consent.persistentStorageGranted, isFalse);
      expect(consent.evaluationWithRedactionGranted, isFalse);
    });

    test('grants and revokes model use without changing other axes', () {
      const original = TutorConsent();

      final granted = original.grantModelUse();
      final revoked = granted.revokeModelUse();

      expect(granted.modelUseGranted, isTrue);
      expect(granted.persistentStorageGranted, isFalse);
      expect(granted.evaluationWithRedactionGranted, isFalse);
      expect(revoked, original);
    });

    test(
      'grants and revokes persistent storage without changing other axes',
      () {
        const original = TutorConsent();

        final granted = original.grantPersistentStorage();
        final revoked = granted.revokePersistentStorage();

        expect(granted.modelUseGranted, isFalse);
        expect(granted.persistentStorageGranted, isTrue);
        expect(granted.evaluationWithRedactionGranted, isFalse);
        expect(revoked, original);
      },
    );

    test(
      'grants and revokes redacted evaluation without changing other axes',
      () {
        const original = TutorConsent();

        final granted = original.grantEvaluationWithRedaction();
        final revoked = granted.revokeEvaluationWithRedaction();

        expect(granted.modelUseGranted, isFalse);
        expect(granted.persistentStorageGranted, isFalse);
        expect(granted.evaluationWithRedactionGranted, isTrue);
        expect(revoked, original);
      },
    );

    test('uses value equality and matching hashes for equal consent', () {
      const first = TutorConsent(modelUseGranted: true);
      const second = TutorConsent(modelUseGranted: true);

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(const TutorConsent(persistentStorageGranted: true)));
    });
  });
}
