/// Cooperative cancellation contract for one analysis run (SDD Ch7 §22.4).
abstract interface class AnalysisCancellationToken {
  bool get isCancelled;

  void throwIfCancelled();
}

/// Thrown only to leave cooperative analysis work early; cancellation is not
/// surfaced as an [AppFailure] to the pipeline caller.
final class AnalysisCancelledException implements Exception {
  const AnalysisCancelledException();
}

/// Per-run cancellation source. It is deliberately not global so one run can
/// never cancel another run.
final class AnalysisCancellationSource implements AnalysisCancellationToken {
  bool _isCancelled = false;

  @override
  bool get isCancelled => _isCancelled;

  void cancel() => _isCancelled = true;

  @override
  void throwIfCancelled() {
    if (_isCancelled) throw const AnalysisCancelledException();
  }
}
