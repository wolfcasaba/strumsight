import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/routing/route_guards.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/editor/song_editor_state.dart';
import '../../application/editor/song_editor_controller.dart';
import '../../application/song_trainer_providers.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/song_track.dart';
import '../widgets/backing_asset_editor.dart';
import '../widgets/measure_grid.dart';
import '../widgets/song_event_editor.dart';
import '../widgets/song_metadata_editor.dart';
import '../widgets/song_section_editor.dart';

/// Route shell for the V2 editor. Editing state lives in the controller.
final class SongEditorScreen extends ConsumerStatefulWidget {
  const SongEditorScreen({required this.songId, super.key});

  final String songId;

  @override
  ConsumerState<SongEditorScreen> createState() => _SongEditorScreenState();
}

final class _SongEditorScreenState extends ConsumerState<SongEditorScreen> {
  late final SongId _id;

  @override
  void initState() {
    super.initState();
    _id = SongId(widget.songId);
    Future<void>.microtask(
      () => ref.read(songEditorControllerProvider(_id)).load(_id),
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
            onAddChord: () => controller.addChord(measureIndex: 0, symbol: 'C'),
            onApplyPattern: (pattern) =>
                controller.applyStrumPattern(measureIndex: 0, pattern: pattern),
            onAddNote: () =>
                controller.addBasicNote(measureIndex: 0, midiPitch: 60),
          ),
          const SizedBox(height: 20),
          BackingAssetEditor(
            hasBacking: draft.tracks.any((track) => track is BackingAudioTrack),
            onDetach: controller.detachBacking,
          ),
        ],
      ),
    );
  }
}
