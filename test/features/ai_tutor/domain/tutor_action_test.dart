import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_action.dart';

void main() {
  group('Tutor actions', () {
    test('profile update copies exact preview fields', () {
      final changes = <String, Object?>{'preferredTempo': 120};
      final action = TutorProfileUpdateAction(
        metadata: _metadata(capability: TutorActionCapability.updateProfile),
        changes: changes,
      );
      changes['preferredTempo'] = 90;

      expect(action.preview.kind, TutorActionPreviewKind.profileUpdate);
      expect(action.preview.fields, <String, Object?>{'preferredTempo': 120});
      expect(
        () => action.changes['preferredTempo'] = 90,
        throwsUnsupportedError,
      );
    });

    test('session launch holds a typed capability instead of a route', () {
      final action = TutorSessionLaunchAction(
        metadata: _metadata(
          capability: TutorActionCapability.launchPracticeSession,
        ),
        launchCapability: TutorSessionLaunchCapability.practiceSession,
      );

      expect(
        action.launchCapability,
        TutorSessionLaunchCapability.practiceSession,
      );
      expect(
        action.metadata.requiredCapability,
        TutorActionCapability.launchPracticeSession,
      );
    });
  });
}

TutorActionMetadata _metadata({required TutorActionCapability capability}) =>
    TutorActionMetadata(
      source: TutorActionSource.modelSuggestion,
      expiresAt: DateTime.utc(2026, 8, 5, 12),
      requiredCapability: capability,
      clientActionId: 'action-1',
    );
