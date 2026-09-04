import 'package:meta/meta.dart';

import '../../model/recognition_runtime_info.dart';

/// The typed result of trying to activate a model (ADR 0355 — fail-VISIBLE,
/// not fail-fast): either it loaded and [model] is ready to use, or it fell
/// back and [info] carries a stable, machine-checkable [FallbackReason]. The
/// CALLER's behaviour is unchanged either way — a fallback still lets the
/// heuristic run; this type only makes the outcome OBSERVABLE.
///
/// The activated/fallback split is enforced with a real `throw`, not
/// `assert` — `assert` disappears in release builds (ADR 0271 `UNKNOWN >
/// CONFIDENTLY WRONG`: a lying pair — `isActivated == true` alongside a
/// [FallbackReason], or a [fallback] reporting a different code than its own
/// [RecognitionRuntimeInfo.fallbackReason] — must be impossible to construct
/// in every build mode, not just under test).
@immutable
class ModelActivation<T> {
  const ModelActivation._({this.model, required this.info});

  /// The model loaded; [info].fallbackReason must be null.
  factory ModelActivation.activated(T model, RecognitionRuntimeInfo info) {
    if (info.fallbackReason != null) {
      throw ArgumentError.value(
        info.fallbackReason,
        'info.fallbackReason',
        'ModelActivation.activated requires a fallbackReason-free info',
      );
    }
    return ModelActivation._(model: model, info: info);
  }

  /// The model did NOT load; [info].fallbackReason carries why. No separate
  /// `reason` parameter — [info] is the single source of truth, so the
  /// reported code can never diverge from what [info] itself says.
  factory ModelActivation.fallback(RecognitionRuntimeInfo info) {
    if (info.fallbackReason == null) {
      throw ArgumentError.value(
        info.fallbackReason,
        'info.fallbackReason',
        'ModelActivation.fallback requires a non-null fallbackReason',
      );
    }
    return ModelActivation._(model: null, info: info);
  }

  /// The caller explicitly disabled the model (a feature flag) — not an
  /// error path. Reading the flag itself is out of this round's scope (ADR
  /// 0355, R8); this factory only makes the outcome representable. [info]
  /// must already carry [FallbackReason.disabledByFlag].
  factory ModelActivation.disabled(RecognitionRuntimeInfo info) =>
      ModelActivation.fallback(info);

  /// Ready-to-use model, or null when [info].fallbackReason is set.
  final T? model;

  /// Always present: which model activated, or why it fell back.
  final RecognitionRuntimeInfo info;

  /// True when [model] is non-null AND [info] carries no [FallbackReason] —
  /// the conjunction (not just [model] non-null) so the two sources of truth
  /// can never disagree, in any build mode.
  bool get isActivated => model != null && info.fallbackReason == null;
}
