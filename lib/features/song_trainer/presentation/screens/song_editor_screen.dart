import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/routing/route_guards.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/editor/song_editor_state.dart';
import '../../application/editor/song_editor_controller.dart';
import '../../application/song_trainer_providers.dart';
import '../../domain/models/meter_map.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/song_measure.dart';
import '../../domain/models/song_metadata.dart';
import '../../domain/models/song_source.dart';
import '../../domain/models/song_track.dart';
import '../../domain/models/tempo_map.dart';
import '../../domain/repositories/song_asset_repository.dart';
import '../widgets/backing_asset_editor.dart';
import '../widgets/measure_grid.dart';
import '../widgets/song_event_editor.dart';
import '../widgets/song_metadata_editor.dart';
import '../widgets/song_section_editor.dart';

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
              onPressed: state.isLoaded ? controller.save : null,
              child: Text(l10n.songEditorSave),
            ),
          ],
        ),
        body: switch (state.status) {
          SongEditorStatus.loading => const Center(
            child: CircularProgressIndicator(),
          ),
          SongEditorStatus.failure when !state.isLoaded => Center(
            child: Text(l10n.songEditorLoadFailed),
          ),
          _ => _EditorBody(id: _id, state: state),
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
  const _EditorBody({required this.id, required this.state});

  final SongId id;
  final SongEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final draft = state.draft!;
    final controller = ref.read(songEditorControllerProvider(id));
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (state.status == SongEditorStatus.conflict)
            Text(l10n.songEditorConflict),
          if (state.status == SongEditorStatus.validationFailed)
            Text(l10n.songEditorInvalid),
          SongMetadataEditor(
            metadata: draft.metadata,
            onChanged: controller.editMetadata,
          ),
          const SizedBox(height: 20),
          SongSectionEditor(
            sections: draft.sections,
            onMove: controller.reorderSections,
          ),
          const SizedBox(height: 20),
          MeasureGrid(
            measures: draft.measures,
            onInsert: controller.insertMeasure,
            onDelete: controller.deleteMeasure,
          ),
          const SizedBox(height: 20),
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
          const SizedBox(height: 20),
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
}
