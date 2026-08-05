/// Immutable, granular permissions for the three independent tutor data uses.
final class TutorConsent {
  const TutorConsent({
    this.modelUseGranted = false,
    this.persistentStorageGranted = false,
    this.evaluationWithRedactionGranted = false,
  });

  final bool modelUseGranted;
  final bool persistentStorageGranted;
  final bool evaluationWithRedactionGranted;

  TutorConsent grantModelUse() => TutorConsent(
    modelUseGranted: true,
    persistentStorageGranted: persistentStorageGranted,
    evaluationWithRedactionGranted: evaluationWithRedactionGranted,
  );

  TutorConsent revokeModelUse() => TutorConsent(
    modelUseGranted: false,
    persistentStorageGranted: persistentStorageGranted,
    evaluationWithRedactionGranted: evaluationWithRedactionGranted,
  );

  TutorConsent grantPersistentStorage() => TutorConsent(
    modelUseGranted: modelUseGranted,
    persistentStorageGranted: true,
    evaluationWithRedactionGranted: evaluationWithRedactionGranted,
  );

  TutorConsent revokePersistentStorage() => TutorConsent(
    modelUseGranted: modelUseGranted,
    persistentStorageGranted: false,
    evaluationWithRedactionGranted: evaluationWithRedactionGranted,
  );

  TutorConsent grantEvaluationWithRedaction() => TutorConsent(
    modelUseGranted: modelUseGranted,
    persistentStorageGranted: persistentStorageGranted,
    evaluationWithRedactionGranted: true,
  );

  TutorConsent revokeEvaluationWithRedaction() => TutorConsent(
    modelUseGranted: modelUseGranted,
    persistentStorageGranted: persistentStorageGranted,
    evaluationWithRedactionGranted: false,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TutorConsent &&
          other.modelUseGranted == modelUseGranted &&
          other.persistentStorageGranted == persistentStorageGranted &&
          other.evaluationWithRedactionGranted ==
              evaluationWithRedactionGranted;

  @override
  int get hashCode => Object.hash(
    modelUseGranted,
    persistentStorageGranted,
    evaluationWithRedactionGranted,
  );
}
