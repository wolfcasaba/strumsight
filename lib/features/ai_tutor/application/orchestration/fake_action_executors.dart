import '../../domain/models/tutor_action.dart';
import 'action_confirmation_service.dart';

final class FakeTutorActionExecutor implements TutorActionExecutor {
  final List<TutorAction> _actions = <TutorAction>[];

  List<TutorAction> get actions => List<TutorAction>.unmodifiable(_actions);

  List<TutorProfileUpdateAction> get profileUpdates =>
      List<TutorProfileUpdateAction>.unmodifiable(
        _actions.whereType<TutorProfileUpdateAction>(),
      );

  List<TutorPlanSaveAction> get planSaves =>
      List<TutorPlanSaveAction>.unmodifiable(
        _actions.whereType<TutorPlanSaveAction>(),
      );

  List<TutorSessionLaunchAction> get sessionLaunches =>
      List<TutorSessionLaunchAction>.unmodifiable(
        _actions.whereType<TutorSessionLaunchAction>(),
      );

  @override
  Future<void> execute(TutorAction action) async {
    _actions.add(action);
  }
}
