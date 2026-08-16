import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';

void main() {
  group('PlanChangeSet', () {
    test('stores structured before and after values with a coded reason', () {
      final change = PlanChange(
        type: PlanChangeType.updated,
        target: 'day:day.1:block:block.1',
        before: const <String, Object?>{'estimatedElapsedMicros': 300000000},
        after: const <String, Object?>{'estimatedElapsedMicros': 600000000},
        reason: PlanChangeReason.systemAdaptation,
        evidenceRefs: const <String>['evidence.tempo-accuracy'],
        confidence: .8,
        requiresUserConfirmation: false,
        reversible: true,
      );
      final changeSet = PlanChangeSet(
        fromRevisionId: RevisionId('revision.1'),
        toRevisionId: RevisionId('revision.2'),
        changes: <PlanChange>[change],
      );

      expect(
        changeSet.changes.single.reason,
        PlanChangeReason.systemAdaptation,
      );
      expect(
        changeSet.changes.single.before['estimatedElapsedMicros'],
        300000000,
      );
      expect(
        changeSet.changes.single.after['estimatedElapsedMicros'],
        600000000,
      );
      final serializedChanges =
          changeSet.toJson()['changes']! as List<Map<String, Object?>>;
      expect(serializedChanges, isA<List<Object?>>());
      expect(serializedChanges.single['type'], 'updated');
    });
  });
}
