/// Grouped-recognition split strategies and the fail-closed leakage
/// detector (E14-R08, ADR 0509).
///
/// A leave-one-`X`-out split holds out every case sharing one distinct
/// group-key value (player/device/guitar/room) as that fold's eval set, and
/// trains on everything else — so a player, device, guitar, or room never
/// appears on both sides of the same fold (ADR 0509 D1). A case missing the
/// requested group key is a typed failure, never folded into an `unknown`
/// bucket (D2): an `unknown` fold would silently reintroduce exactly the
/// leakage this file exists to prevent. This file never imports
/// `package:strumsight/features/audio_analysis/…` and never opens a file or
/// a socket.
library;

import 'recognition_metrics.dart' show RecognitionCase;

/// The four group keys a recognition case can be split on.
enum GroupKey { player, device, guitar, room }

/// The four grouped split strategies (SDD Ch14 §7). Each strategy holds out
/// one distinct value of its [groupKey] per fold.
enum SplitStrategy {
  leaveOnePlayerOut,
  leaveOneDeviceOut,
  leaveOneGuitarOut,
  roomHoldout,
}

extension SplitStrategyGroupKey on SplitStrategy {
  GroupKey get groupKey => switch (this) {
    SplitStrategy.leaveOnePlayerOut => GroupKey.player,
    SplitStrategy.leaveOneDeviceOut => GroupKey.device,
    SplitStrategy.leaveOneGuitarOut => GroupKey.guitar,
    SplitStrategy.roomHoldout => GroupKey.room,
  };
}

enum RecognitionSplitErrorKind { missingGroupKey, leakage }

/// A typed split failure: a missing group key (D2) or detected leakage
/// (D1). Never thrown as a bare [ArgumentError] or [StateError] so a caller
/// can distinguish the two failure modes.
final class RecognitionSplitException implements Exception {
  const RecognitionSplitException(this.kind, this.message);

  final RecognitionSplitErrorKind kind;
  final String message;

  @override
  String toString() => 'RecognitionSplitException(${kind.name}): $message';
}

/// One leave-one-`X`-out fold: every case is either training data or, when
/// its [GroupKey] value equals [heldOutGroupValue], the eval slice. Case
/// ids are sorted (not insertion- or hash-ordered) so the same manifest
/// always produces the same fold (ADR 0509 D6).
final class RecognitionSplitFold {
  const RecognitionSplitFold({
    required this.strategy,
    required this.heldOutGroupValue,
    required this.trainCaseIds,
    required this.evalCaseIds,
  });

  final SplitStrategy strategy;
  final String heldOutGroupValue;
  final List<String> trainCaseIds;
  final List<String> evalCaseIds;
}

/// Fail-closed leakage protection (ADR 0509 D1): if a [GroupKey] value is
/// present on both sides of a fold, [validate] throws — it never warns,
/// never drops the offending case, and always names the conflicting value.
final class LeakageDetector {
  const LeakageDetector();

  void validate({
    required GroupKey groupKey,
    required Map<String, String> groupValueByCaseId,
    required RecognitionSplitFold fold,
  }) {
    final trainValues = <String>{
      for (final caseId in fold.trainCaseIds) groupValueByCaseId[caseId]!,
    };
    for (final caseId in fold.evalCaseIds) {
      final value = groupValueByCaseId[caseId]!;
      if (trainValues.contains(value)) {
        throw RecognitionSplitException(
          RecognitionSplitErrorKind.leakage,
          '${groupKey.name}="$value" appears on both sides of fold '
          '"${fold.heldOutGroupValue}" (eval case "$caseId" shares its '
          '${groupKey.name} with a training case): a grouped split must '
          'not let the same ${groupKey.name} cross the train/eval '
          'boundary.',
        );
      }
    }
  }
}

/// Builds every fold of a [SplitStrategy] over [cases]: one fold per
/// distinct group-key value, its eval set being every case sharing that
/// value and its train set being every other case. The union of every
/// fold's eval set is exactly [cases] — each case is held out in precisely
/// one fold. Each fold is validated against [LeakageDetector] before being
/// returned (defense in depth: a correctly built leave-one-out fold can
/// never leak, but the check runs unconditionally per D1).
final class RecognitionSplitBuilder {
  const RecognitionSplitBuilder();

  static const LeakageDetector _detector = LeakageDetector();

  List<RecognitionSplitFold> buildFolds(
    List<RecognitionCase> cases,
    SplitStrategy strategy,
  ) {
    final groupKey = strategy.groupKey;
    final groupValueByCaseId = <String, String>{};
    for (final recognitionCase in cases) {
      final value = _groupValue(recognitionCase, groupKey);
      if (value == null || value.trim().isEmpty) {
        throw RecognitionSplitException(
          RecognitionSplitErrorKind.missingGroupKey,
          'case "${recognitionCase.caseId}" has no ${groupKey.name} group '
          'key (required by ${strategy.name})',
        );
      }
      groupValueByCaseId[recognitionCase.caseId] = value;
    }

    final distinctValues = groupValueByCaseId.values.toSet().toList()..sort();
    final folds = <RecognitionSplitFold>[
      for (final value in distinctValues)
        RecognitionSplitFold(
          strategy: strategy,
          heldOutGroupValue: value,
          evalCaseIds: [
            for (final recognitionCase in cases)
              if (groupValueByCaseId[recognitionCase.caseId] == value)
                recognitionCase.caseId,
          ]..sort(),
          trainCaseIds: [
            for (final recognitionCase in cases)
              if (groupValueByCaseId[recognitionCase.caseId] != value)
                recognitionCase.caseId,
          ]..sort(),
        ),
    ];

    for (final fold in folds) {
      _detector.validate(
        groupKey: groupKey,
        groupValueByCaseId: groupValueByCaseId,
        fold: fold,
      );
    }
    return folds;
  }

  String? _groupValue(RecognitionCase recognitionCase, GroupKey key) =>
      switch (key) {
        GroupKey.player => recognitionCase.player,
        GroupKey.device => recognitionCase.device,
        GroupKey.guitar => recognitionCase.guitar,
        GroupKey.room => recognitionCase.room,
      };
}
