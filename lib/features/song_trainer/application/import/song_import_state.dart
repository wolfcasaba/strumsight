import 'import_preview.dart';

/// Explicit, replay-safe phases of one import operation.
enum SongImportPhase {
  idle,
  selecting,
  probing,
  preview,
  importing,
  validating,
  committing,
  success,
  failure,
  cancelled,
}

/// Immutable application state; it intentionally owns no file or byte payload.
final class SongImportState {
  const SongImportState({
    required this.phase,
    this.operationId,
    this.preview,
    this.failureCode,
  });

  const SongImportState.idle() : this(phase: SongImportPhase.idle);

  final SongImportPhase phase;
  final String? operationId;
  final ImportPreview? preview;
  final String? failureCode;

  bool get isActive => switch (phase) {
    SongImportPhase.selecting ||
    SongImportPhase.probing ||
    SongImportPhase.preview ||
    SongImportPhase.importing ||
    SongImportPhase.validating ||
    SongImportPhase.committing => true,
    SongImportPhase.idle ||
    SongImportPhase.success ||
    SongImportPhase.failure ||
    SongImportPhase.cancelled => false,
  };
}
