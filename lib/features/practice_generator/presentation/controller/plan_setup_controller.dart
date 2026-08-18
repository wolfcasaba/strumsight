/// State and persistence boundary for the practice-plan setup wizard.
library;

import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../../core/foundation/app_result.dart';
import '../../../../core/storage/key_value_store.dart';
import '../../data/local/generation_draft_repository.dart';
import '../../domain/model/learner_constraints.dart';
import '../../domain/id/planner_ids.dart';
import '../../domain/model/plan_enums.dart';
import '../../domain/model/practice_generation_request.dart';
import '../../domain/model/practice_goal.dart';
import '../../domain/model/weekly_availability.dart';
import '../../domain/service/request_validator.dart';

/// Immutable view state for the five-step setup flow.
final class PlanSetupState {
  const PlanSetupState({
    this.currentStep = 0,
    this.request,
    this.findings = const <RequestValidationFinding>[],
    this.isRestoring = false,
    this.persistenceFailed = false,
  });

  final int currentStep;
  final PracticeGenerationRequest? request;
  final List<RequestValidationFinding> findings;
  final bool isRestoring;
  final bool persistenceFailed;

  bool get hasHardConflict => findings.any((finding) => finding.isError);

  PlanSetupState copyWith({
    int? currentStep,
    PracticeGenerationRequest? request,
    List<RequestValidationFinding>? findings,
    bool? isRestoring,
    bool? persistenceFailed,
  }) => PlanSetupState(
    currentStep: currentStep ?? this.currentStep,
    request: request ?? this.request,
    findings: findings ?? this.findings,
    isRestoring: isRestoring ?? this.isRestoring,
    persistenceFailed: persistenceFailed ?? this.persistenceFailed,
  );
}

/// Coordinates wizard answers with the local, resumable draft repository.
///
/// No answer is invented: an unknown response is represented by the absence
/// of its domain value. Every completed step is saved as a complete request.
final class PlanSetupController extends ChangeNotifier {
  PlanSetupController({
    required this.draftRepository,
    required this.clock,
    required this.generateId,
    required this.locale,
    this.validator = const RequestValidator(),
  });

  final GenerationDraftRepository draftRepository;
  final DateTime Function() clock;
  final String Function() generateId;
  final String locale;
  final RequestValidator validator;

  /// Kept beside, rather than inside, the request so an unanswered step is
  /// still distinct from a step the learner has explicitly completed as
  /// unknown.
  static const String _draftProgressStorageKey =
      '${GenerationDraftRepository.draftStorageKey}.step';

  PlanSetupState _state = const PlanSetupState();
  PlanSetupState get state => _state;

  Future<void> restore() async {
    _update(_state.copyWith(isRestoring: true));
    final result = await draftRepository.loadDraft();
    switch (result) {
      case Success<PracticeGenerationRequest?>(:final value):
        if (value == null) {
          _update(const PlanSetupState());
          return;
        }
        _update(
          PlanSetupState(
            currentStep: _savedCurrentStep ?? 0,
            request: value,
            findings: _findingsFor(value),
          ),
        );
      case Failure<PracticeGenerationRequest?>():
        _update(const PlanSetupState(persistenceFailed: true));
    }
  }

  void selectGoal(PracticeGoalType? type) {
    final request = _withRequest(
      goals: type == null
          ? const <PracticeGoal>[]
          : <PracticeGoal>[
              PracticeGoal(
                id: GoalId.generate(generateId),
                type: type,
                priority: GoalPriority.primary,
                status: PracticeGoalStatus.proposed,
                createdAt: clock(),
              ),
            ],
    );
    _setRequest(request);
  }

  void setAvailability(List<DailyAvailability> days) =>
      _setRequest(_withRequest(availability: WeeklyAvailability(days)));

  void setEquipment(String? equipment) => _setCategory(
    ConstraintCategory.equipment,
    equipment == null
        ? const <LearnerConstraint>[]
        : <LearnerConstraint>[
            LearnerConstraint(
              category: ConstraintCategory.equipment,
              strength: ConstraintStrength.hard,
              code: 'instrument',
              value: equipment,
            ),
          ],
  );

  void setPreference(String? preference) => _setCategory(
    ConstraintCategory.preference,
    preference == null
        ? const <LearnerConstraint>[]
        : <LearnerConstraint>[
            LearnerConstraint(
              category: ConstraintCategory.preference,
              strength: ConstraintStrength.soft,
              code: 'style',
              value: preference,
              softViolationCost: 1,
            ),
          ],
  );

  /// Keeps comfort text exclusively inside the plaintext local draft path;
  /// this controller deliberately has no logging or analytics dependency.
  void setComfortText(String value) => _setCategory(
    ConstraintCategory.comfort,
    value.trim().isEmpty
        ? const <LearnerConstraint>[]
        : <LearnerConstraint>[
            LearnerConstraint(
              category: ConstraintCategory.comfort,
              strength: ConstraintStrength.soft,
              code: 'freeText',
              value: value,
              softViolationCost: 1,
            ),
          ],
  );

  Future<void> next() async {
    final request = _state.request ?? _newRequest();
    if (_findingsFor(request).any((finding) => finding.isError)) return;
    final result = await draftRepository.saveDraft(request);
    final nextStep = min(_state.currentStep + 1, 5);
    final progressSaved = result.isSuccess && await _saveCurrentStep(nextStep);
    _update(
      PlanSetupState(
        currentStep: nextStep,
        request: request,
        findings: _findingsFor(request),
        persistenceFailed: result.isFailure || !progressSaved,
      ),
    );
  }

  void back() {
    if (_state.currentStep == 0) return;
    _update(_state.copyWith(currentStep: _state.currentStep - 1));
  }

  void _setCategory(
    ConstraintCategory category,
    List<LearnerConstraint> replacement,
  ) {
    final current = _state.request ?? _newRequest();
    final next = <LearnerConstraint>[
      ...current.constraints.constraints.where(
        (constraint) => constraint.category != category,
      ),
      ...replacement,
    ];
    _setRequest(_withRequest(constraints: LearnerConstraints(next)));
  }

  PracticeGenerationRequest _withRequest({
    List<PracticeGoal>? goals,
    WeeklyAvailability? availability,
    LearnerConstraints? constraints,
  }) {
    final current = _state.request ?? _newRequest();
    return PracticeGenerationRequest(
      id: current.id,
      createdAt: current.createdAt,
      locale: current.locale,
      generationMode: current.generationMode,
      planHorizonDays: current.planHorizonDays,
      goals: goals ?? current.goals,
      availability: availability ?? current.availability,
      constraints: constraints ?? current.constraints,
    );
  }

  PracticeGenerationRequest _newRequest() => PracticeGenerationRequest(
    id: GenerationRequestId.generate(generateId),
    createdAt: clock(),
    locale: locale,
    generationMode: GenerationMode.starter,
    planHorizonDays: 7,
    availability: WeeklyAvailability(const <DailyAvailability>[]),
    constraints: LearnerConstraints(const <LearnerConstraint>[]),
  );

  List<RequestValidationFinding> _findingsFor(
    PracticeGenerationRequest request,
  ) => validator
      .validate(
        goals: request.goals,
        availability: request.availability,
        scheduledMinutes: const <LocalDate, int>{},
      )
      .findings;

  int? get _savedCurrentStep {
    final currentStep = draftRepository.keyValueStore.readInt(
      _draftProgressStorageKey,
    );
    if (currentStep == null || currentStep < 0 || currentStep > 5) {
      return null;
    }
    return currentStep;
  }

  Future<bool> _saveCurrentStep(int currentStep) async {
    try {
      await draftRepository.keyValueStore.writeInt(
        _draftProgressStorageKey,
        currentStep,
      );
      return true;
    } on StorageException {
      return false;
    }
  }

  void _setRequest(PracticeGenerationRequest request) => _update(
    PlanSetupState(
      currentStep: _state.currentStep,
      request: request,
      findings: _findingsFor(request),
    ),
  );

  void _update(PlanSetupState value) {
    _state = value;
    notifyListeners();
  }
}

String createPlanSetupId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
