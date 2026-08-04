import '../../domain/models/song_document.dart';
import '../../domain/models/song_validation_report.dart';

enum SongEditorStatus {
  loading,
  ready,
  saving,
  validationFailed,
  conflict,
  failure,
  disposed,
}

/// Immutable application state for a document editor.
final class SongEditorState {
  const SongEditorState({
    required this.status,
    this.persisted,
    this.draft,
    this.validation,
    this.failureCode,
    this.canUndo = false,
    this.canRedo = false,
  });

  const SongEditorState.loading() : this(status: SongEditorStatus.loading);

  final SongEditorStatus status;
  final SongDocument? persisted;
  final SongDocument? draft;
  final SongValidationReport? validation;
  final String? failureCode;
  final bool canUndo;
  final bool canRedo;

  bool get isLoaded => draft != null;
  bool get isDirty => draft != persisted;
  bool get hasConflict => status == SongEditorStatus.conflict;

  SongEditorState copyWith({
    SongEditorStatus? status,
    SongDocument? persisted,
    SongDocument? draft,
    SongValidationReport? validation,
    String? failureCode,
    bool? canUndo,
    bool? canRedo,
    bool clearValidation = false,
    bool clearFailure = false,
  }) => SongEditorState(
    status: status ?? this.status,
    persisted: persisted ?? this.persisted,
    draft: draft ?? this.draft,
    validation: clearValidation ? null : validation ?? this.validation,
    failureCode: clearFailure ? null : failureCode ?? this.failureCode,
    canUndo: canUndo ?? this.canUndo,
    canRedo: canRedo ?? this.canRedo,
  );
}
