import 'package:meta/meta.dart';

import '../../model/recognition_runtime_info.dart';

/// The typed result of trying to activate a model (ADR 0355 — fail-VISIBLE,
/// not fail-fast): either it loaded and [model] is ready to use, or it fell
/// back and [info] carries a stable, machine-checkable [FallbackReason]. The
/// CALLER's behaviour is unchanged either way — a fallback still lets the
/// heuristic run; this type only makes the outcome OBSERVABLE.
@immutable
class ModelActivation<T> {
  const ModelActivation._({this.model, required this.info});

  /// The model loaded; [info].fallbackReason is null.
  factory ModelActivation.activated(T model, RecognitionRuntimeInfo info) {
    assert(
      info.fallbackReason == null,
      'ModelActivation.activated requires a fallbackReason-free info',
    );
    return ModelActivation._(model: model, info: info);
  }

  /// The model did NOT load; [info].fallbackReason equals [reason].
  factory ModelActivation.fallback(
    FallbackReason reason,
    RecognitionRuntimeInfo info,
  ) {
    assert(
      info.fallbackReason == reason,
      'ModelActivation.fallback requires info.fallbackReason == reason',
    );
    return ModelActivation._(model: null, info: info);
  }

  /// The caller explicitly disabled the model (a feature flag) — not an
  /// error path. Reading the flag itself is out of this round's scope (ADR
  /// 0355, R8); this factory only makes the outcome representable.
  factory ModelActivation.disabled(RecognitionRuntimeInfo info) =>
      ModelActivation.fallback(FallbackReason.disabledByFlag, info);

  /// Ready-to-use model, or null when [info].fallbackReason is set.
  final T? model;

  /// Always present: which model activated, or why it fell back.
  final RecognitionRuntimeInfo info;

  /// True when [model] is non-null (equivalently, [info].fallbackReason is
  /// null).
  bool get isActivated => model != null;
}
