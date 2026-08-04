import 'dart:async';
import 'dart:io';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../data/importers/import_limits.dart';
import '../../data/importers/import_workspace.dart';
import '../../data/importers/importer_registry.dart';
import '../../data/importers/song_importer.dart';
import '../../domain/models/song_capability.dart';
import '../../domain/repositories/song_repository.dart';
import '../../domain/services/song_capability_resolver.dart';
import '../../domain/services/song_normalizer.dart';
import '../../domain/services/song_validator.dart';
import 'import_preview.dart';
import 'song_import_effect.dart';
import 'song_import_state.dart';

/// Application-owned import operation: source and workspace never enter state.
final class SongImportController {
  SongImportController({
    required this.registry,
    required this.repository,
    required this.workspaceRoot,
    this.normalizer = const SongNormalizer(),
    this.validator = const SongValidator(),
    this.capabilityResolver = const SongCapabilityResolver(),
  });

  final ImporterRegistry registry;
  final SongRepository repository;
  final Future<Directory> Function() workspaceRoot;
  final SongNormalizer normalizer;
  final SongValidator validator;
  final SongCapabilityResolver capabilityResolver;
  final StreamController<SongImportEffect> _effects =
      StreamController<SongImportEffect>.broadcast(sync: true);
  final StreamController<SongImportState> _states =
      StreamController<SongImportState>.broadcast(sync: true);

  SongImportState _state = const SongImportState.idle();
  _ImportOperation? _operation;
  var _nextOperation = 0;
  var _disposed = false;

  SongImportState get state => _state;
  Stream<SongImportEffect> get effects => _effects.stream;
  Stream<SongImportState> get states => _states.stream;

  /// Starts a new picker request. The presentation layer returns its source
  /// through [selectSource], keeping platform picker values out of state.
  void requestSelection() {
    if (_disposed || _state.isActive) return;
    final operation = _ImportOperation('import-${++_nextOperation}');
    _operation = operation;
    _setState(
      SongImportState(
        phase: SongImportPhase.selecting,
        operationId: operation.id,
      ),
    );
    _effects.add(const RequestFilePickerEffect());
  }

  /// Consumes the picker result and probes content before any persistent write.
  Future<void> selectSource(ImportSourceFile? source) async {
    final operation = _operation;
    if (operation == null ||
        !_isCurrent(operation) ||
        _state.phase != SongImportPhase.selecting) {
      return;
    }
    if (source == null) {
      await _finish(
        operation,
        const SongImportState.idle(),
        pickerCleanup: true,
      );
      return;
    }
    operation.source = source;
    _setState(
      SongImportState(
        phase: SongImportPhase.probing,
        operationId: operation.id,
      ),
    );
    try {
      final selection = await registry.probe(source, operation.token);
      if (!_isCurrent(operation)) return;
      operation.selection = selection;
      _setState(
        SongImportState(
          phase: SongImportPhase.preview,
          operationId: operation.id,
          preview: ImportPreview(
            displayName: source.displayName,
            byteLength: source.byteLength,
            format: selection.importer.runtimeType.toString(),
            warnings: selection.probe.warnings,
            parts: selection.probe.parts,
          ),
        ),
      );
    } on ImportRegistryException catch (error) {
      if (_isCurrent(operation)) await _failure(operation, error.code);
    } on TimeoutException {
      if (_isCurrent(operation)) {
        await _failure(operation, ImportLimitFailureCode.wallTimeExceeded);
      }
    } catch (_) {
      if (_isCurrent(operation)) await _failure(operation, FailureCode.unknown);
    }
  }

  /// Reopens the selected source, then normalizes, validates, and atomically
  /// creates the repository record only after all earlier stages succeed.
  Future<void> confirmPreview() async {
    final operation = _operation;
    if (operation == null ||
        !_isCurrent(operation) ||
        _state.phase != SongImportPhase.preview) {
      return;
    }
    final source = operation.source!;
    final selection = operation.selection!;
    _setState(
      SongImportState(
        phase: SongImportPhase.importing,
        operationId: operation.id,
        preview: _state.preview,
      ),
    );
    try {
      final workspace = await ImportWorkspace.open(
        root: await workspaceRoot(),
        operationId: operation.id,
        limits: registry.limits,
      );
      if (!_isCurrent(operation)) {
        await workspace.close();
        return;
      }
      operation.workspace = workspace;
      final imported = await registry.import(
        selection,
        source,
        const SongImportOptions(),
        operation.token,
      );
      if (!_isCurrent(operation)) return;
      if (imported case Failure<SongImportResult>(:final error)) {
        if (error.code == FailureCode.cancelled) {
          await _cancelOperation(operation);
        } else {
          await _failure(operation, error.code);
        }
        return;
      }
      final document = normalizer.normalize(
        (imported as Success<SongImportResult>).value.document,
      );
      _setState(
        SongImportState(
          phase: SongImportPhase.validating,
          operationId: operation.id,
          preview: _state.preview,
        ),
      );
      final report = validator.validate(document);
      final capability = capabilityResolver.resolve(
        report: report,
        profile: SongCapabilityProfile.persist,
      );
      if (!capability.canPersist) {
        await _failure(operation, 'songImport.validationFailed');
        return;
      }
      if (!_isCurrent(operation)) return;
      _setState(
        SongImportState(
          phase: SongImportPhase.committing,
          operationId: operation.id,
          preview: _state.preview,
        ),
      );
      final committed = await repository.create(document);
      if (!_isCurrent(operation)) return;
      if (committed case Failure<void>(:final error)) {
        await _failure(operation, error.code);
        return;
      }
      await _finish(
        operation,
        SongImportState(
          phase: SongImportPhase.success,
          operationId: operation.id,
          preview: _state.preview,
        ),
      );
      if (!_effects.isClosed) {
        _effects.add(SongImportSucceededEffect(document.id));
      }
    } on ImportWorkspaceException catch (error) {
      if (_isCurrent(operation)) await _failure(operation, error.code);
    } catch (_) {
      if (_isCurrent(operation)) await _failure(operation, FailureCode.unknown);
    }
  }

  /// Cancels the active operation and closes every operation-owned resource.
  Future<void> cancel() async {
    final operation = _operation;
    if (operation == null || !_isCurrent(operation)) return;
    if (_state.phase == SongImportPhase.selecting) {
      operation.token.cancel();
      await _finish(
        operation,
        const SongImportState.idle(),
        pickerCleanup: true,
      );
      return;
    }
    if (_state.isActive) await _cancelOperation(operation);
  }

  /// Cancels any active operation and begins a fresh operation ID.
  Future<void> retry() async {
    await cancel();
    requestSelection();
  }

  /// Releases all operation resources. Safe to call more than once.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final operation = _operation;
    if (operation != null) {
      operation.token.cancel();
      if (_state.isActive) {
        _setState(
          SongImportState(
            phase: SongImportPhase.cancelled,
            operationId: operation.id,
          ),
        );
      }
      await _closeWorkspace(operation);
    }
    _operation = null;
    if (!_effects.isClosed) await _effects.close();
    if (!_states.isClosed) await _states.close();
  }

  Future<void> _cancelOperation(_ImportOperation operation) async {
    operation.token.cancel();
    await _finish(
      operation,
      SongImportState(
        phase: SongImportPhase.cancelled,
        operationId: operation.id,
      ),
      pickerCleanup: _state.phase == SongImportPhase.selecting,
    );
  }

  Future<void> _failure(_ImportOperation operation, String code) => _finish(
    operation,
    SongImportState(
      phase: SongImportPhase.failure,
      operationId: operation.id,
      failureCode: code,
    ),
  );

  Future<void> _finish(
    _ImportOperation operation,
    SongImportState terminalState, {
    bool pickerCleanup = false,
  }) async {
    if (!_isCurrent(operation)) return;
    // Detach before asynchronous cleanup so a callback that completes while
    // deletion is in flight cannot enter validation or commit a stale result.
    _operation = null;
    await _closeWorkspace(operation);
    _setState(terminalState);
    if (pickerCleanup && !_effects.isClosed) {
      _effects.add(const CleanupFilePickerEffect());
    }
  }

  Future<void> _closeWorkspace(_ImportOperation operation) async {
    final workspace = operation.workspace;
    operation.workspace = null;
    await workspace?.close();
  }

  void _setState(SongImportState value) {
    _state = value;
    if (!_states.isClosed) _states.add(value);
  }

  bool _isCurrent(_ImportOperation? operation) =>
      !_disposed && operation != null && identical(_operation, operation);
}

final class _ImportOperation {
  _ImportOperation(this.id);

  final String id;
  final _MutableCancellationToken token = _MutableCancellationToken();
  ImportSourceFile? source;
  ImporterSelection? selection;
  ImportWorkspace? workspace;
}

final class _MutableCancellationToken implements CancellationToken {
  var _isCancelled = false;

  @override
  bool get isCancelled => _isCancelled;

  void cancel() => _isCancelled = true;
}
