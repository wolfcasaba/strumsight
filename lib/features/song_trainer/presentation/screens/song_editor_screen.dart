import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/routing/route_guards.dart';
import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/editor/song_editor_state.dart';
import '../../application/editor/song_editor_controller.dart';
import '../../application/song_trainer_providers.dart';
import '../../domain/models/meter_map.dart';
import '../../domain/models/song_capability.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/song_measure.dart';
import '../../domain/models/song_metadata.dart';
import '../../domain/models/song_source.dart';
import '../../domain/models/song_track.dart';
import '../../domain/models/tempo_map.dart';
import '../../domain/repositories/song_asset_repository.dart';
import '../../domain/services/song_capability_resolver.dart';
import '../../domain/services/song_validator.dart';
import '../widgets/backing_asset_editor.dart';
import '../widgets/measure_grid.dart';
import '../widgets/song_event_editor.dart';
import '../widgets/song_metadata_editor.dart';
import '../widgets/song_section_editor.dart';

/// A5.6/§0.0/B/R10: read-only-ness is a property of the persisted document
/// itself, computed by the editor from the same framework-independent
/// domain services the repository and the Library screen use — never
/// derived from route origin, so a direct/deep-linked route gets the same
/// answer a Library-mediated open would. A brand-new, not-yet-persisted
/// document (`persisted == null`) is always persistable via `create`.
bool _canPersist(SongDocument? persisted) {
  if (persisted == null) return true;
  final report = const SongValidator().validate(persisted);
  final capability = const SongCapabilityResolver().resolve(
    report: report,
    profile: SongCapabilityProfile.persist,
  );
  return capability.canPersist;
}

/// Route shell for the V2 editor. Editing state lives in the controller.
final class SongEditorScreen extends ConsumerStatefulWidget {
  const SongEditorScreen({required this.songId, super.key})
    : newDocument = false;

  const SongEditorScreen.newDocument({super.key})
    : songId = 'new',
      newDocument = true;

  final String songId;
  final bool newDocument;

  @override
  ConsumerState<SongEditorScreen> createState() => _SongEditorScreenState();
}

final class _SongEditorScreenState extends ConsumerState<SongEditorScreen> {
  late final SongId _id;
  var _startedNewDraft = false;

  // MINOR-1: `build()` reruns on every editing step (undo/redo, metadata
  // typing, chord add — anything the `songEditorStateProvider` publishes),
  // but `_canPersist` only depends on `state.persisted`, which changes only
  // on load/successful save. Memoize by identity so an edit-heavy session
  // doesn't re-run `SongValidator().validate()` on every keystroke.
  SongDocument? _canPersistCacheKey;
  var _canPersistCacheValue = true;
  var _canPersistCacheComputed = false;

  bool _canPersistMemo(SongDocument? persisted) {
    if (!_canPersistCacheComputed ||
        !identical(persisted, _canPersistCacheKey)) {
      _canPersistCacheKey = persisted;
      _canPersistCacheValue = _canPersist(persisted);
      _canPersistCacheComputed = true;
    }
    return _canPersistCacheValue;
  }

  // MAJOR-2 (E13-R24 review §6.2): `_saveCopy` calls `controller.startNew`,
  // which detaches `persisted` (sets it to `null`) before `save()` runs. If
  // the repository write itself then fails — as opposed to a still-fatal
  // copy, which `_saveCopy` now rejects before ever calling `startNew` — the
  // controller has no public API to restore `persisted` without also
  // overwriting `draft` (see `load`). `_canPersist(null)` is always `true`,
  // which would silently re-enable Save on the orphaned, unpersisted copy.
  // This screen-local flag keeps Save locked and the "Save copy" retry
  // affordance visible until `state.persisted` is non-null again (a
  // successful save, or a fresh load).
  var _copyWriteFailed = false;

  @override
  void initState() {
    super.initState();
    _id = SongId(widget.songId);
    final controller = ref.read(songEditorControllerProvider(_id));
    if (!widget.newDocument) {
      Future<void>.microtask(() => controller.load(_id));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.newDocument || _startedNewDraft) return;
    _startedNewDraft = true;
    ref
        .read(songEditorControllerProvider(_id))
        .startNew(_newDraft(AppLocalizations.of(context).songEditorNewTitle));
  }

  SongDocument _newDraft(String title) {
    final now = DateTime.now().toUtc();
    final unique =
        '${now.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    return SongDocument(
      schemaVersion: songDocumentSchemaVersion,
      id: SongId('editor-$unique'),
      revision: 0,
      metadata: SongMetadata(title: title),
      source: SongSource(
        type: SongSourceType.createdInApp,
        originalFileName: 'new-song.song',
        sha256: '0' * 64,
        importedAt: now,
        importerVersion: 'editor@1',
      ),
      createdAt: now,
      updatedAt: now,
      measures: <SongMeasure>[
        SongMeasure(index: 0, durationBeats: BeatPosition.fromBeats(4)),
      ],
      tempoMap: TempoMap.constant(Tempo(120)),
      meterMap: MeterMap.constant(Meter(4, 4)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(songEditorControllerProvider(_id));
    final state =
        ref.watch(songEditorStateProvider(_id)).value ?? controller.state;
    if (state.persisted != null) _copyWriteFailed = false;
    final canPersist = _copyWriteFailed
        ? false
        : _canPersistMemo(state.persisted);
    return PopScope<Object?>(
      canPop: !state.isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && await _confirmExit(context, controller, state)) {
          if (context.mounted) {
            Navigator.of(context).pop(result);
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.songEditorTitle),
          actions: <Widget>[
            IconButton(
              onPressed: state.canUndo ? controller.undo : null,
              icon: const Icon(Icons.undo),
              tooltip: l10n.songEditorUndo,
            ),
            IconButton(
              onPressed: state.canRedo ? controller.redo : null,
              icon: const Icon(Icons.redo),
              tooltip: l10n.songEditorRedo,
            ),
            TextButton(
              key: const Key('song-editor-save'),
              onPressed: (state.isLoaded && canPersist)
                  ? controller.save
                  : null,
              child: Text(l10n.songEditorSave),
            ),
          ],
        ),
        body: switch (state.status) {
          SongEditorStatus.loading => const _EditorLoading(),
          SongEditorStatus.failure when !state.isLoaded => _EditorLoadError(
            message: l10n.songEditorLoadFailed,
          ),
          _ => _EditorBody(
            id: _id,
            state: state,
            canPersist: canPersist,
            onCopyWriteFailed: () => setState(() => _copyWriteFailed = true),
          ),
        },
      ),
    );
  }

  Future<bool> _confirmExit(
    BuildContext context,
    SongEditorController controller,
    SongEditorState state,
  ) async {
    if (!state.isDirty) return true;
    final l10n = AppLocalizations.of(context);
    final decision =
        await showDialog<UnsavedEditorDecision>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.songEditorUnsavedTitle),
            content: Text(l10n.songEditorUnsavedBody),
            actions: <Widget>[
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, UnsavedEditorDecision.stay),
                child: Text(l10n.songEditorStay),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, UnsavedEditorDecision.discard),
                child: Text(l10n.songEditorDiscard),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, UnsavedEditorDecision.save),
                child: Text(l10n.songEditorSave),
              ),
            ],
          ),
        ) ??
        UnsavedEditorDecision.stay;
    if (decision == UnsavedEditorDecision.save) await controller.save();
    if (decision == UnsavedEditorDecision.discard) controller.discard();
    return mayLeaveEditor(
      dirty: state.isDirty,
      decision: decision,
      saveSucceeded: !controller.state.isDirty,
    );
  }
}

final class _EditorBody extends ConsumerWidget {
  const _EditorBody({
    required this.id,
    required this.state,
    required this.canPersist,
    required this.onCopyWriteFailed,
  });

  final SongId id;
  final SongEditorState state;
  final bool canPersist;
  final VoidCallback onCopyWriteFailed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final draft = state.draft!;
    final controller = ref.read(songEditorControllerProvider(id));
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(SsSpacing.space4),
        children: <Widget>[
          if (state.status == SongEditorStatus.conflict)
            Text(
              l10n.songEditorConflict,
              style: typography.bodyMedium.copyWith(color: colors.danger),
            ),
          if (state.status == SongEditorStatus.validationFailed)
            Text(
              l10n.songEditorInvalid,
              style: typography.bodyMedium.copyWith(color: colors.danger),
            ),
          // A5: a failed save (or other post-load operation) never discards
          // the draft — the content below stays exactly as edited, and the
          // failure is named with `failureCode` rather than a generic
          // message (docs/adr/0284-import-preview-is-not-a-commit.md §4).
          if (state.status == SongEditorStatus.failure)
            Padding(
              padding: const EdgeInsets.only(bottom: SsSpacing.space3),
              child: Semantics(
                label: l10n.songEditorSaveFailed(state.failureCode ?? ''),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.error_outline, color: colors.danger),
                    const SizedBox(width: SsSpacing.space2),
                    Expanded(
                      child: Text(
                        l10n.songEditorSaveFailed(state.failureCode ?? ''),
                        style: typography.bodyMedium.copyWith(
                          color: colors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // A6: a read-only source (validator-fatal persisted document) can
          // never be updated in place — Save above is disabled and the only
          // write path left is an explicit, new-identity copy
          // (docs/adr/0284-import-preview-is-not-a-commit.md §5).
          if (!canPersist)
            Padding(
              padding: const EdgeInsets.only(bottom: SsSpacing.space3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.lock_outline, color: colors.warning),
                  const SizedBox(width: SsSpacing.space2),
                  Expanded(
                    child: Text(
                      l10n.songEditorReadOnlySource,
                      style: typography.bodyMedium.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const Key('song-editor-save-copy'),
                    onPressed: () => _saveCopy(context, controller, draft),
                    child: Text(l10n.songEditorSaveCopy),
                  ),
                ],
              ),
            ),
          SongMetadataEditor(
            metadata: draft.metadata,
            onChanged: controller.editMetadata,
          ),
          const SizedBox(height: SsSpacing.space5),
          SongSectionEditor(
            sections: draft.sections,
            onMove: controller.reorderSections,
          ),
          const SizedBox(height: SsSpacing.space5),
          MeasureGrid(
            measures: draft.measures,
            onInsert: controller.insertMeasure,
            onDelete: controller.deleteMeasure,
          ),
          const SizedBox(height: SsSpacing.space5),
          SongEventEditor(
            measureCount: draft.measures.length,
            onAddChord: (measureIndex, symbol) =>
                controller.addChord(measureIndex: measureIndex, symbol: symbol),
            onApplyPattern: (measureIndex, pattern) =>
                controller.applyStrumPattern(
                  measureIndex: measureIndex,
                  pattern: pattern,
                ),
            onAddNote: (measureIndex, midiPitch) => controller.addBasicNote(
              measureIndex: measureIndex,
              midiPitch: midiPitch,
            ),
            onSetTempo: (measureIndex, bpm) =>
                controller.setTempo(atBeat: measureIndex * 4, bpm: bpm),
            onSetMeter: (measureIndex, numerator, denominator) =>
                controller.setMeter(
                  atMeasure: measureIndex,
                  numerator: numerator,
                  denominator: denominator,
                ),
          ),
          const SizedBox(height: SsSpacing.space5),
          BackingAssetEditor(
            hasBacking: draft.tracks.any((track) => track is BackingAudioTrack),
            onAttach: () => _attachBacking(ref, controller),
            onDetach: controller.detachBacking,
          ),
        ],
      ),
    );
  }

  Future<void> _attachBacking(
    WidgetRef ref,
    SongEditorController controller,
  ) async {
    final source = await ref.read(songFilePickerAdapterProvider).pickSongFile();
    if (source == null) return;
    final bytes = <int>[];
    await for (final chunk in source.openRead()) {
      bytes.addAll(chunk);
    }
    if (bytes.isEmpty) return;
    final hash = sha256.convert(bytes).toString();
    await controller.attachBacking(
      SongAssetWriteRequest(
        bytes: Uint8List.fromList(bytes),
        assetId: SongAssetId('backing-${hash.substring(0, 16)}'),
        extension: _fileExtension(source.displayName),
        expectedSha256: hash,
        mimeType: source.mimeType,
      ),
    );
  }

  String _fileExtension(String name) {
    final separator = name.lastIndexOf('.');
    if (separator <= 0 || separator == name.length - 1) return 'bin';
    return name.substring(separator + 1).toLowerCase();
  }

  /// The only write path A6 allows for a read-only source: a brand-new
  /// document identity (fresh [SongId], `createdInApp` source) carrying the
  /// current draft's content. `controller.startNew` detaches the persisted
  /// pointer, so the following `save()` always calls `repository.create`
  /// and the original stored document is never touched.
  Future<void> _saveCopy(
    BuildContext context,
    SongEditorController controller,
    SongDocument draft,
  ) async {
    final now = DateTime.now().toUtc();
    final unique =
        '${now.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    final copy = SongDocument(
      schemaVersion: draft.schemaVersion,
      id: SongId('editor-copy-$unique'),
      revision: 0,
      metadata: draft.metadata,
      source: SongSource(
        type: SongSourceType.createdInApp,
        originalFileName: draft.source.originalFileName,
        sha256: '0' * 64,
        importedAt: now,
        importerVersion: 'editor@1',
      ),
      createdAt: now,
      updatedAt: now,
      assets: draft.assets,
      markers: draft.markers,
      tracks: draft.tracks,
      sections: draft.sections,
      measures: draft.measures,
      tempoMap: draft.tempoMap,
      meterMap: draft.meterMap,
      keyMap: draft.keyMap,
    );
    // MAJOR-2 (E13-R24 review §6.2): a copy carries `draft`'s exact content,
    // so it fails the same fatal-reference check `draft` itself would fail
    // if the user never ran the in-editor fix. Checking that HERE, before
    // `controller.startNew` runs, means the controller — and with it the
    // user's live, unsaved draft — is never touched on this path:
    // `startNew` detaches `persisted`, and the controller exposes no way to
    // restore it without also overwriting `draft` (see `load`), which is
    // exactly the silent-data-loss bug this check exists to avoid.
    if (!_canPersist(copy)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).songEditorInvalid),
          ),
        );
      }
      return;
    }
    controller.startNew(copy);
    await controller.save();
    // A repository failure at this point (as opposed to the still-fatal
    // case caught above) still leaves `persisted == null` — the controller
    // has no API to avoid that without touching the forbidden application
    // layer. `onCopyWriteFailed` keeps Save locked and the "Save copy"
    // retry affordance visible from the screen side instead; `draft` is
    // untouched either way, since `save()` never rewrites it on failure.
    if (_isFailureStatus(controller.state.status)) {
      onCopyWriteFailed();
    }
  }

  static bool _isFailureStatus(SongEditorStatus status) => switch (status) {
    SongEditorStatus.validationFailed ||
    SongEditorStatus.failure ||
    SongEditorStatus.conflict => true,
    _ => false,
  };
}

final class _EditorLoading extends StatelessWidget {
  const _EditorLoading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: const SsSkeleton(
        width: 120,
        height: SsSpacing.space6,
        radius: SsRadius.pill,
      ),
    );
  }
}

/// Built from design tokens directly rather than [SsFailureState]: the
/// editor's load failure carries no [AppFailure]/`retryable` flag on this
/// path (`SongEditorState` — measured), so there is nothing honest to feed
/// [SsFailurePresentation.from] without fabricating one (E15-R04 review
/// MAJOR-2). This state was action-less pre-migration (a bare `Text`) —
/// adding a retry affordance here would be a new action in an
/// appearance-only round (E15-R04 review MAJOR-3 pattern).
final class _EditorLoadError extends StatelessWidget {
  const _EditorLoadError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SsSpacing.space6),
        child: Text(
          message,
          key: const Key('song-editor-load-error'),
          style: typography.bodyMedium.copyWith(color: colors.danger),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
