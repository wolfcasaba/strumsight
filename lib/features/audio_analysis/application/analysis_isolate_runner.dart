import 'dart:async';
import 'dart:isolate';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/data/analysis_document_codec.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';

/// A cancellable execution returned synchronously when a run is started.
abstract interface class AnalysisRunHandle {
  String get runId;
  Stream<AnalysisProgressEvent> get progress;
  Future<AnalysisRunResult> get result;
  Future<void> cancel();
}

/// Application-facing terminal value. The engine-only pipeline result is
/// translated at the runner boundary so controllers cannot depend on DSP code.
final class AnalysisRunResult {
  const AnalysisRunResult({
    required this.completion,
    this.document,
    this.failure,
  });

  final AnalysisCompletionStatus completion;
  final AnalysisDocument? document;
  final AppFailure? failure;
}

/// Boundary consumed by the application use case and faked by controller tests.
abstract interface class AnalysisRunner {
  AnalysisRunHandle start(AnalysisDocument input);
}

/// Top-level, isolate-sendable document transformation using codec JSON.
///
/// A future real stage-chain composition supplies this operation. It is not
/// created in this round because no concrete V2 stage list exists yet.
typedef AnalysisDocumentIsolateOperation =
    FutureOr<String> Function(String documentJson);

/// Spawns the isolate used for one analysis run.
///
/// This narrow seam keeps the runner's spawn-to-assignment lifecycle
/// testable without exposing its private isolate message protocol.
typedef AnalysisIsolateSpawner =
    Future<Isolate> Function(
      SendPort replyTo,
      String input,
      AnalysisDocumentIsolateOperation operation,
    );

/// Default [AnalysisIsolateSpawner] used by production analysis runs.
Future<Isolate> spawnAnalysisIsolate(
  SendPort replyTo,
  String input,
  AnalysisDocumentIsolateOperation operation,
) => Isolate.spawn<_IsolateRequest>(
  _isolateEntry,
  _IsolateRequest(replyTo: replyTo, input: input, operation: operation),
);

/// One-shot isolate runner. Each [start] creates a fresh isolate; [cancel]
/// kills only that isolate and closes its progress channel.
final class AnalysisIsolateRunner implements AnalysisRunner {
  AnalysisIsolateRunner({
    required this.operation,
    this.isolateSpawner = spawnAnalysisIsolate,
  });

  final AnalysisDocumentIsolateOperation operation;
  final AnalysisIsolateSpawner isolateSpawner;
  int _nextRunNumber = 0;

  @override
  AnalysisRunHandle start(AnalysisDocument input) {
    final runId = 'analysis-isolate-${++_nextRunNumber}';
    return _IsolateAnalysisRun(
      runId: runId,
      input: input,
      operation: operation,
      isolateSpawner: isolateSpawner,
    );
  }
}

final class _IsolateAnalysisRun implements AnalysisRunHandle {
  _IsolateAnalysisRun({
    required this.runId,
    required this.input,
    required this.operation,
    required this.isolateSpawner,
  }) : _result = Completer<AnalysisRunResult>() {
    unawaited(_start());
  }

  @override
  final String runId;
  final AnalysisDocument input;
  final AnalysisDocumentIsolateOperation operation;
  final AnalysisIsolateSpawner isolateSpawner;
  final StreamController<AnalysisProgressEvent> _progress =
      StreamController<AnalysisProgressEvent>.broadcast();
  final Completer<AnalysisRunResult> _result;
  Isolate? _isolate;
  ReceivePort? _messages;
  var _cancelled = false;
  var _disposed = false;

  @override
  Stream<AnalysisProgressEvent> get progress => _progress.stream;

  @override
  Future<AnalysisRunResult> get result => _result.future;

  Future<void> _start() async {
    try {
      final encodedInput = const AnalysisDocumentCodec().encode(input);
      final messages = ReceivePort();
      _messages = messages;
      _isolate = await isolateSpawner(
        messages.sendPort,
        encodedInput,
        operation,
      );
      if (_cancelled) {
        await _dispose();
        return;
      }
      _progress.add(
        AnalysisPhaseProgressEvent(
          runId: runId,
          phase: AnalysisProgressPhase.finalizing,
        ),
      );
      final message = await messages.first;
      if (_cancelled) return;
      if (message is String) {
        final decoded = const AnalysisDocumentCodec().decode(message);
        switch (decoded) {
          case Success<AnalysisDocument>(:final value):
            _complete(completion: value.completion.status, value: value);
          case Failure<AnalysisDocument>(:final error):
            _complete(
              completion: AnalysisCompletionStatus.failed,
              failure: error,
            );
        }
      } else {
        _complete(
          completion: AnalysisCompletionStatus.failed,
          failure: UnknownFailure(cause: message),
        );
      }
    } on Object catch (error, stackTrace) {
      if (!_cancelled) {
        _complete(
          completion: AnalysisCompletionStatus.failed,
          failure: UnknownFailure(cause: error, stackTrace: stackTrace),
        );
      }
    } finally {
      await _dispose();
    }
  }

  @override
  Future<void> cancel() async {
    if (_disposed || _cancelled) return;
    _cancelled = true;
    await _dispose();
    if (!_result.isCompleted) {
      _result.complete(
        const AnalysisRunResult(completion: AnalysisCompletionStatus.cancelled),
      );
    }
  }

  void _complete({
    required AnalysisCompletionStatus completion,
    AnalysisDocument? value,
    AppFailure? failure,
  }) {
    if (_result.isCompleted || _cancelled) return;
    _result.complete(
      AnalysisRunResult(
        completion: completion,
        document: value,
        failure: failure,
      ),
    );
  }

  Future<void> _dispose() async {
    // An isolate can be assigned after a concurrent cancel has already
    // closed the ports. Kill it before observing the once-only cleanup guard,
    // so the spawn-to-assignment window cannot leak a live worker.
    final isolate = _isolate;
    _isolate = null;
    isolate?.kill(priority: Isolate.immediate);
    if (_disposed) return;
    _disposed = true;
    _messages?.close();
    await _progress.close();
  }
}

final class _IsolateRequest {
  const _IsolateRequest({
    required this.replyTo,
    required this.input,
    required this.operation,
  });

  final SendPort replyTo;
  final String input;
  final AnalysisDocumentIsolateOperation operation;
}

void _isolateEntry(_IsolateRequest request) async {
  try {
    request.replyTo.send(await request.operation(request.input));
  } on Object catch (error) {
    request.replyTo.send(error.toString());
  }
}
