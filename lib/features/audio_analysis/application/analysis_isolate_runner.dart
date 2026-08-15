import 'dart:async';
import 'dart:isolate';

import 'package:meta/meta.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/data/analysis_document_codec.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_document.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_input.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_progress.dart';
import 'package:strumsight/features/audio_analysis/domain/target/analysis_target.dart';

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
  AnalysisRunHandle start(AnalysisRunRequest input);
}

/// The input to one analysis run (ADR 0254 §1): a document seed carrying
/// identity/mode/provenance, the validated PCM the chain actually analyses,
/// and an optional performance reference. [seed] is never the audio carrier —
/// [audio] lives only in memory for the lifetime of the run and is never
/// written into a persisted, exportable [AnalysisDocument].
final class AnalysisRunRequest {
  const AnalysisRunRequest({
    required this.seed,
    required this.audio,
    this.target,
  });

  final AnalysisDocument seed;
  final ValidatedPcmAnalysisInput audio;
  final AnalysisTarget? target;
}

/// Top-level, isolate-sendable analysis operation. [documentJson] carries the
/// codec-encoded run seed; [audio] and [target] cross the isolate boundary as
/// native Dart objects so the raw PCM never round-trips through the document
/// codec (ADR 0254 §2). [reportProgress] lets a long-running operation (e.g.
/// the V2 stage chain) publish [AnalysisProgressEvent]s back to the spawning
/// isolate as they occur, ahead of the final return value.
typedef AnalysisDocumentIsolateOperation =
    FutureOr<String> Function(
      String documentJson,
      ValidatedPcmAnalysisInput audio,
      AnalysisTarget? target,
      void Function(AnalysisProgressEvent event) reportProgress,
    );

/// Spawns the isolate used for one analysis run.
///
/// This narrow seam keeps the runner's spawn-to-assignment lifecycle
/// testable without exposing its private isolate message protocol.
typedef AnalysisIsolateSpawner =
    Future<Isolate> Function(
      SendPort replyTo,
      String documentJson,
      ValidatedPcmAnalysisInput audio,
      AnalysisTarget? target,
      AnalysisDocumentIsolateOperation operation,
    );

/// Default [AnalysisIsolateSpawner] used by production analysis runs.
Future<Isolate> spawnAnalysisIsolate(
  SendPort replyTo,
  String documentJson,
  ValidatedPcmAnalysisInput audio,
  AnalysisTarget? target,
  AnalysisDocumentIsolateOperation operation,
) => Isolate.spawn<_IsolateRequest>(
  _isolateEntry,
  _IsolateRequest(
    replyTo: replyTo,
    documentJson: documentJson,
    audio: audio,
    target: target,
    operation: operation,
  ),
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
  AnalysisRunHandle start(AnalysisRunRequest input) {
    final runId = 'analysis-isolate-${++_nextRunNumber}';
    return _IsolateAnalysisRun(
      runId: runId,
      request: input,
      operation: operation,
      isolateSpawner: isolateSpawner,
    );
  }
}

final class _IsolateAnalysisRun implements AnalysisRunHandle {
  _IsolateAnalysisRun({
    required this.runId,
    required AnalysisRunRequest request,
    required this.operation,
    required this.isolateSpawner,
  }) : _result = Completer<AnalysisRunResult>() {
    _request = request;
    unawaited(_start());
  }

  @override
  final String runId;

  /// The raw-PCM-carrying request. Nulled out as soon as the spawn call has
  /// handed the audio off to the isolate boundary (or on any terminal/cancel
  /// path that never reaches spawn), so a caller holding a closed
  /// [AnalysisRunHandle] cannot keep the sample buffer reachable (ADR 0254
  /// §2, brief §5.2).
  AnalysisRunRequest? _request;
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
      final request = _request;
      if (request == null) return;
      final encodedSeed = const AnalysisDocumentCodec().encode(request.seed);
      final messages = ReceivePort();
      _messages = messages;
      _isolate = await isolateSpawner(
        messages.sendPort,
        encodedSeed,
        request.audio,
        request.target,
        operation,
      );
      _request = null;
      if (_cancelled) {
        await _dispose();
        return;
      }
      await for (final message in messages) {
        if (_cancelled) break;
        if (message is AnalysisProgressEvent) {
          _progress.add(_remapRunId(message));
          continue;
        }
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
        break;
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
    _request = null;
    await _dispose();
    if (!_result.isCompleted) {
      _result.complete(
        const AnalysisRunResult(completion: AnalysisCompletionStatus.cancelled),
      );
    }
  }

  /// The isolate-side operation (e.g. the V2 pipeline) mints its own
  /// internal run id for [AnalysisProgressEvent]s. Callers only know this
  /// handle's [runId] (ADR 0254's stable `AnalysisRunHandle` contract), so
  /// every forwarded event is re-stamped with it here, keeping phase and
  /// unit-count data untouched.
  AnalysisProgressEvent _remapRunId(AnalysisProgressEvent event) {
    return switch (event) {
      AnalysisPhaseProgressEvent(
        :final phase,
        :final completedUnits,
        :final totalUnits,
      ) =>
        AnalysisPhaseProgressEvent(
          runId: runId,
          phase: phase,
          completedUnits: completedUnits,
          totalUnits: totalUnits,
        ),
      AnalysisRunResultEvent(:final completion) => AnalysisRunResultEvent(
        runId: runId,
        completion: completion,
      ),
    };
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
    _request = null;
    if (_disposed) return;
    _disposed = true;
    _messages?.close();
    await _progress.close();
  }
}

/// Test-only introspection of whether [handle] still holds the raw-PCM
/// request (ADR 0254 §2, brief §5.2: a run releases its sample buffer once
/// terminal or cancelled). Not part of [AnalysisRunHandle]'s contract.
@visibleForTesting
bool debugAnalysisRunHandleHoldsRequest(AnalysisRunHandle handle) =>
    handle is _IsolateAnalysisRun && handle._request != null;

final class _IsolateRequest {
  const _IsolateRequest({
    required this.replyTo,
    required this.documentJson,
    required this.audio,
    required this.target,
    required this.operation,
  });

  final SendPort replyTo;
  final String documentJson;
  final ValidatedPcmAnalysisInput audio;
  final AnalysisTarget? target;
  final AnalysisDocumentIsolateOperation operation;
}

void _isolateEntry(_IsolateRequest request) async {
  try {
    final result = await request.operation(
      request.documentJson,
      request.audio,
      request.target,
      request.replyTo.send,
    );
    request.replyTo.send(result);
  } on Object catch (error) {
    request.replyTo.send(error.toString());
  }
}
