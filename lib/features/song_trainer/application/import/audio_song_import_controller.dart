/// Audio file → DRAFT song import (K3/A4).
///
/// The notation import flow (`SongImportController`) parses an authored
/// score; this one measures a recording. The stages are therefore different
/// enough to deserve their own operation: pick → decode (platform decoder) →
/// analyse (off the UI isolate) → map to a draft → persist → attach the
/// ORIGINAL compressed bytes as the backing track.
///
/// Three things this controller refuses to do quietly:
///
///   * it never reuses the notation `ImportLimits.maxSourceBytes` (1 MiB
///     sizes a score); the audio path carries `maxAudioImportSourceBytes`,
///     checked on the declared length AND on the running total while
///     streaming, because a picker may under-report;
///   * it never commits a document the mapper refused to build — the named
///     mapper failure becomes the operation's failure code;
///   * it never reports success when the backing asset could not be stored.
///     A draft whose audio silently vanished is the worst of both worlds.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../../core/audio/codec/platform_audio_decoder.dart';
import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../analyze/public.dart' show AnalyzeResult;
import '../../data/importers/audio_song_draft_mapper.dart';
import '../../data/importers/file_picker_adapter.dart';
import '../../data/importers/import_limits.dart';
import '../../data/importers/song_importer.dart';
import '../../domain/models/song_asset_reference.dart';
import '../../domain/models/song_capability.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/song_instrument.dart';
import '../../domain/models/song_track.dart';
import '../../domain/repositories/song_asset_repository.dart';
import '../../domain/repositories/song_repository.dart';
import '../../domain/services/song_capability_resolver.dart';
import '../../domain/services/song_normalizer.dart';
import '../../domain/services/song_validator.dart';
import 'song_import_effect.dart';

/// Stable failures produced by the audio import operation itself.
abstract final class AudioSongImportFailureCode {
  /// The picked container is not one the app can decode or play.
  static const String unsupportedFormat = 'songImport.audio.unsupportedFormat';

  /// The file is larger than the audio import ceiling.
  static const String sourceBytesExceeded = 'songImport.audio.sourceBytes';

  /// The picked file carried no bytes.
  static const String empty = 'songImport.audio.empty';

  /// The decoded clip carried no samples — nothing to analyse.
  static const String noSamples = 'songImport.audio.noSamples';

  /// The draft document failed document validation before any write.
  static const String validationFailed = 'songImport.validationFailed';
}

/// Explicit phases of one audio import operation.
enum AudioSongImportPhase {
  idle,
  selecting,
  decoding,
  analyzing,
  saving,
  success,
  failure,
  cancelled,
}

/// Immutable state. It owns no bytes, no path and no plugin object.
final class AudioSongImportState {
  const AudioSongImportState({
    required this.phase,
    this.fileName,
    this.failureCode,
  });

  const AudioSongImportState.idle() : this(phase: AudioSongImportPhase.idle);

  final AudioSongImportPhase phase;
  final String? fileName;
  final String? failureCode;

  bool get isActive => switch (phase) {
    AudioSongImportPhase.selecting ||
    AudioSongImportPhase.decoding ||
    AudioSongImportPhase.analyzing ||
    AudioSongImportPhase.saving => true,
    AudioSongImportPhase.idle ||
    AudioSongImportPhase.success ||
    AudioSongImportPhase.failure ||
    AudioSongImportPhase.cancelled => false,
  };
}

/// Decodes a container on disk into mono PCM. Production binds the K2
/// platform decoder; tests bind a synthetic clip and touch no channel.
typedef AudioPcmDecode = Future<AppResult<DecodedPcm>> Function(String path);

/// Resolves the song repository WHEN the operation needs it.
///
/// A function, not the repository itself: the import screen is mounted in
/// containers that have not opened the song tree (every widget test that just
/// renders the sheet-import screen), and constructing this controller must
/// never be the thing that forces the storage root open.
typedef SongRepositoryResolver = SongRepository Function();

/// Resolves the asset store WHEN the operation needs it — see
/// [SongRepositoryResolver] for why this is a function.
typedef SongAssetRepositoryResolver = SongAssetRepository Function();

/// Runs the clip analyzer — off the UI isolate in production.
typedef AudioClipAnalyze =
    Future<AnalyzeResult> Function(List<double> pcm, int sampleRate);

/// Drives one audio → draft import (K3/A4).
final class AudioSongImportController {
  AudioSongImportController({
    required this.decode,
    required this.analyze,
    required this.repository,
    required this.assetRepository,
    required this.workspaceRoot,
    this.mapper = const AudioSongDraftMapper(),
    this.normalizer = const SongNormalizer(),
    this.validator = const SongValidator(),
    this.capabilityResolver = const SongCapabilityResolver(),
    this.clock = DateTime.now,
    this.maxSourceBytes = maxAudioImportSourceBytes,
  });

  final AudioPcmDecode decode;
  final AudioClipAnalyze analyze;
  final SongRepositoryResolver repository;
  final SongAssetRepositoryResolver assetRepository;
  final Future<Directory> Function() workspaceRoot;
  final AudioSongDraftMapper mapper;
  final SongNormalizer normalizer;
  final SongValidator validator;
  final SongCapabilityResolver capabilityResolver;
  final DateTime Function() clock;
  final int maxSourceBytes;

  final StreamController<SongImportEffect> _effects =
      StreamController<SongImportEffect>.broadcast(sync: true);
  final StreamController<AudioSongImportState> _states =
      StreamController<AudioSongImportState>.broadcast(sync: true);

  AudioSongImportState _state = const AudioSongImportState.idle();
  Object? _operation;
  var _operationCount = 0;
  var _disposed = false;

  AudioSongImportState get state => _state;
  Stream<SongImportEffect> get effects => _effects.stream;
  Stream<AudioSongImportState> get states => _states.stream;

  /// Marks the picker as open. The presentation layer owns the picker call
  /// itself, exactly as the notation flow does.
  void beginSelection() {
    if (_disposed || _state.isActive) return;
    final operation = Object();
    _operation = operation;
    _operationCount += 1;
    const selecting = AudioSongImportState(
      phase: AudioSongImportPhase.selecting,
    );
    _publish(selecting);
  }

  /// Consumes the picker result and runs the whole operation.
  Future<void> selectSource(ImportSourceFile? source) async {
    final operation = _operation;
    if (operation == null || !_isCurrent(operation)) return;
    if (_state.phase != AudioSongImportPhase.selecting) return;
    if (source == null) {
      _finish(operation, const AudioSongImportState.idle());
      return;
    }
    try {
      await _run(operation, source);
    } catch (_) {
      // Any unexpected error becomes a NAMED terminal state; the operation
      // never hangs on a phase the user cannot leave.
      if (_isCurrent(operation)) _fail(operation, FailureCode.unknown);
    }
  }

  /// Cancels the active operation.
  ///
  /// The decode / analysis already in flight is not killed — it is DISOWNED:
  /// its result is dropped because the operation token no longer matches, and
  /// the `compute` isolate terminates on its own when its function returns,
  /// so leaving the screen leaks no isolate.
  void cancel() {
    final operation = _operation;
    if (operation == null || !_isCurrent(operation)) return;
    if (!_state.isActive) return;
    const cancelled = AudioSongImportState(
      phase: AudioSongImportPhase.cancelled,
    );
    _finish(operation, cancelled);
  }

  /// Releases the streams. Safe to call more than once.
  Future<void> dispose() async {
    if (_disposed) return;
    cancel();
    _disposed = true;
    _operation = null;
    if (!_effects.isClosed) await _effects.close();
    if (!_states.isClosed) await _states.close();
  }

  Future<void> _run(Object operation, ImportSourceFile source) async {
    final name = source.displayName;
    final extension = PlatformFilePickerAdapter.extensionOf(name);
    const playable = PlatformFilePickerAdapter.supportedAudioExtensions;
    if (extension == null || !playable.contains(extension)) {
      _fail(operation, AudioSongImportFailureCode.unsupportedFormat);
      return;
    }
    if (source.byteLength > maxSourceBytes) {
      _fail(operation, AudioSongImportFailureCode.sourceBytesExceeded);
      return;
    }

    final decoding = AudioSongImportState(
      phase: AudioSongImportPhase.decoding,
      fileName: name,
    );
    _publish(decoding);

    final builder = BytesBuilder();
    await for (final chunk in source.openRead()) {
      if (!_isCurrent(operation)) return;
      if (builder.length + chunk.length > maxSourceBytes) {
        // The declared length was checked above; a picker that under-reports
        // is caught here, before the bytes reach the asset store.
        _fail(operation, AudioSongImportFailureCode.sourceBytesExceeded);
        return;
      }
      builder.add(chunk);
    }
    if (!_isCurrent(operation)) return;
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) {
      _fail(operation, AudioSongImportFailureCode.empty);
      return;
    }
    final hash = sha256.convert(bytes).toString();

    final root = await workspaceRoot();
    if (!_isCurrent(operation)) return;
    await root.create(recursive: true);
    final separator = Platform.pathSeparator;
    final id = 'audio-import-$_operationCount';
    final scratch = File('${root.path}$separator$id.$extension');
    try {
      await scratch.writeAsBytes(bytes, flush: true);
      if (!_isCurrent(operation)) return;
      await _decodeAnalyseAndSave(
        operation,
        source: source,
        extension: extension,
        bytes: bytes,
        hash: hash,
        path: scratch.path,
      );
    } finally {
      // The decoder needs a real path, so the compressed bytes land in the
      // app's own temp tree for the length of one operation — never longer.
      await _deleteQuietly(scratch);
    }
  }

  Future<void> _decodeAnalyseAndSave(
    Object operation, {
    required ImportSourceFile source,
    required String extension,
    required Uint8List bytes,
    required String hash,
    required String path,
  }) async {
    final name = source.displayName;
    final decoded = await decode(path);
    if (!_isCurrent(operation)) return;
    if (decoded case Failure<DecodedPcm>(:final error)) {
      _fail(operation, error.code);
      return;
    }
    final pcm = (decoded as Success<DecodedPcm>).value;
    if (pcm.samples.isEmpty || pcm.sampleRate <= 0) {
      _fail(operation, AudioSongImportFailureCode.noSamples);
      return;
    }

    final analyzing = AudioSongImportState(
      phase: AudioSongImportPhase.analyzing,
      fileName: name,
    );
    _publish(analyzing);
    final analysis = await analyze(pcm.samples, pcm.sampleRate);
    if (!_isCurrent(operation)) return;

    final saving = AudioSongImportState(
      phase: AudioSongImportPhase.saving,
      fileName: name,
    );
    _publish(saving);
    final drafted = mapper.map(
      analysis: analysis,
      duration: pcm.duration,
      fileName: name,
      songId: _newSongId(),
      sha256: hash,
      importedAt: clock().toUtc(),
    );
    if (drafted case Failure<AudioSongDraft>(:final error)) {
      _fail(operation, error.code);
      return;
    }
    final draft = (drafted as Success<AudioSongDraft>).value;

    final request = SongAssetWriteRequest(
      bytes: bytes,
      assetId: SongAssetId('backing-${hash.substring(0, 16)}'),
      extension: extension,
      expectedSha256: hash,
      mimeType: source.mimeType,
      durationMs: pcm.duration.inMilliseconds,
    );
    final stored = await assetRepository().put(request);
    if (!_isCurrent(operation)) return;
    if (stored case Failure<SongAssetStoreReceipt>(:final error)) {
      // Never a silent drop: a draft that lost its audio is reported.
      _fail(operation, error.code);
      return;
    }
    final receipt = (stored as Success<SongAssetStoreReceipt>).value;

    final withBacking = _attachBacking(
      draft.document,
      receipt: receipt,
      extension: extension,
      mimeType: source.mimeType,
      durationMs: pcm.duration.inMilliseconds,
    );
    final document = normalizer.normalize(withBacking);
    final report = validator.validate(document);
    final capability = capabilityResolver.resolve(
      report: report,
      profile: SongCapabilityProfile.persist,
    );
    if (!capability.canPersist) {
      _fail(operation, AudioSongImportFailureCode.validationFailed);
      return;
    }

    final committed = await repository().create(document);
    if (!_isCurrent(operation)) return;
    if (committed case Failure<void>(:final error)) {
      _fail(operation, error.code);
      return;
    }
    final success = AudioSongImportState(
      phase: AudioSongImportPhase.success,
      fileName: name,
    );
    _finish(operation, success);
    if (!_effects.isClosed) {
      _effects.add(SongImportSucceededEffect(document.id));
    }
  }

  SongDocument _attachBacking(
    SongDocument document, {
    required SongAssetStoreReceipt receipt,
    required String extension,
    required String? mimeType,
    required int durationMs,
  }) {
    final asset = SongAssetReference(
      id: receipt.assetId,
      sha256: receipt.sha256,
      extension: extension,
      byteLength: receipt.byteLength,
      mimeType: mimeType,
      durationMs: durationMs,
    );
    final track = BackingAudioTrack(
      id: SongTrackId('backing-track'),
      name: 'Backing',
      instrument: SongInstrument(name: 'Audio'),
      assetId: asset.id,
      gridOffset: Duration.zero,
    );
    return SongDocument(
      schemaVersion: document.schemaVersion,
      id: document.id,
      revision: document.revision,
      metadata: document.metadata,
      source: document.source,
      createdAt: document.createdAt,
      updatedAt: document.updatedAt,
      assets: <SongAssetReference>[...document.assets, asset],
      markers: document.markers,
      tracks: <SongTrack>[...document.tracks, track],
      sections: document.sections,
      measures: document.measures,
      tempoMap: document.tempoMap,
      meterMap: document.meterMap,
      keyMap: document.keyMap,
    );
  }

  SongId _newSongId() {
    final stamp = clock().toUtc().microsecondsSinceEpoch;
    final noise = Random.secure().nextInt(1 << 32);
    return SongId('audio-$stamp-$noise');
  }

  void _fail(Object operation, String code) {
    final terminal = AudioSongImportState(
      phase: AudioSongImportPhase.failure,
      fileName: _state.fileName,
      failureCode: code,
    );
    _finish(operation, terminal);
  }

  void _finish(Object operation, AudioSongImportState terminal) {
    if (!_isCurrent(operation)) return;
    _operation = null;
    _publish(terminal);
  }

  void _publish(AudioSongImportState value) {
    _state = value;
    if (!_states.isClosed) _states.add(value);
  }

  bool _isCurrent(Object? operation) =>
      !_disposed && operation != null && identical(_operation, operation);

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A leftover scratch file in the app's own temp tree is not worth
      // failing an otherwise-successful import over; the next operation
      // overwrites it by operation id.
    }
  }
}
