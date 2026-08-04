import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/routing/route_guards.dart';

void main() {
  test(
    'browser or app back is blocked when a dirty draft stays or fails save',
    () {
      expect(
        mayLeaveEditor(
          dirty: true,
          decision: UnsavedEditorDecision.stay,
          saveSucceeded: false,
        ),
        isFalse,
      );
      expect(
        mayLeaveEditor(
          dirty: true,
          decision: UnsavedEditorDecision.save,
          saveSucceeded: false,
        ),
        isFalse,
      );
    },
  );
}
