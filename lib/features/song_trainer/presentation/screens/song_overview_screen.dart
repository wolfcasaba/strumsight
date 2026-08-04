import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/trainer/song_trainer_setup_controller.dart';
import '../../application/trainer/song_trainer_setup_state.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/trainer_config.dart';
import '../../domain/models/trainer_range.dart';
import '../widgets/song_section_list.dart';
import '../widgets/song_track_picker.dart';

/// Read-only summary of a persisted song before trainer configuration.
final class SongOverviewScreen extends ConsumerStatefulWidget {
  const SongOverviewScreen({required this.songId, super.key});

  final String songId;

  @override
  ConsumerState<SongOverviewScreen> createState() => _SongOverviewScreenState();
}

final class _SongOverviewScreenState extends ConsumerState<SongOverviewScreen> {
  late final SongId _songId;

  @override
  void initState() {
    super.initState();
    _songId = SongId(widget.songId);
    Future<void>.microtask(_loadIfNeeded);
  }

  void _loadIfNeeded() {
    final controller = ref.read(songTrainerSetupControllerProvider(_songId));
    if (controller.state.status == SongTrainerSetupStatus.idle ||
        controller.state.songId != _songId) {
      unawaited(controller.load(_songId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(songTrainerSetupControllerProvider(_songId));
    final state =
        ref.watch(songTrainerSetupStateProvider(_songId)).value ??
        controller.state;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.songOverviewTitle)),
      body: switch (state.status) {
        SongTrainerSetupStatus.idle || SongTrainerSetupStatus.loading => Center(
          child: Semantics(
            label: l10n.songOverviewLoading,
            child: const CircularProgressIndicator(),
          ),
        ),
        SongTrainerSetupStatus.failure => Center(
          child: FilledButton(
            onPressed: _loadIfNeeded,
            child: Text(l10n.songOverviewRetry),
          ),
        ),
        SongTrainerSetupStatus.ready => _OverviewBody(
          state: state,
          onSectionSelected: (section) =>
              controller.selectRange(SectionRange(section.id)),
          onTrackSelected: (track) => controller.selectTrack(track.id),
          onStart: () => _openSetup(context),
        ),
      },
    );
  }

  void _openSetup(BuildContext context) {
    context.push(
      AppRoutes.songTrainerSetup.replaceFirst(
        ':songId',
        Uri.encodeComponent(_songId.value),
      ),
    );
  }
}

final class _OverviewBody extends StatelessWidget {
  const _OverviewBody({
    required this.state,
    required this.onSectionSelected,
    required this.onTrackSelected,
    required this.onStart,
  });

  final SongTrainerSetupState state;
  final ValueChanged<TrainerSectionOption> onSectionSelected;
  final ValueChanged<TrainerTrackOption> onTrackSelected;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = state.title ?? '';
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 24),
          Text(
            l10n.songOverviewSections,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SongSectionList(
            sections: state.sections,
            onSelected: onSectionSelected,
          ),
          const SizedBox(height: 24),
          Text(
            l10n.songOverviewTracks,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SongTrackPicker(tracks: state.tracks, onSelected: onTrackSelected),
          const SizedBox(height: 24),
          Text(
            l10n.songOverviewCapabilities,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (final mode in TrainerMode.values)
            ListTile(
              enabled: state.modeAvailability(mode).isEnabled,
              title: Text(_modeLabel(l10n, mode)),
              subtitle: state.modeAvailability(mode).isEnabled
                  ? null
                  : Text(_unavailableLabel(l10n, state.modeAvailability(mode))),
            ),
          const SizedBox(height: 24),
          Semantics(
            label: l10n.songOverviewStartSemantic(title),
            button: true,
            child: FilledButton.icon(
              key: const Key('song-overview-start'),
              onPressed: state.config == null ? null : onStart,
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.songOverviewStart),
            ),
          ),
        ],
      ),
    );
  }
}

String _modeLabel(AppLocalizations l10n, TrainerMode mode) => switch (mode) {
  TrainerMode.chord => l10n.trainerModeChord,
  TrainerMode.rhythm => l10n.trainerModeRhythm,
  TrainerMode.pitch => l10n.trainerModePitch,
};

String _unavailableLabel(
  AppLocalizations l10n,
  TrainerModeAvailability availability,
) => switch (availability.reason!) {
  TrainerModeUnavailableReason.trackNotCompatible =>
    l10n.trainerModeUnavailableTrack,
  TrainerModeUnavailableReason.unsupportedChord =>
    l10n.trainerModeUnavailableChord,
  TrainerModeUnavailableReason.polyphonicNotes =>
    l10n.trainerModeUnavailablePolyphonic,
  TrainerModeUnavailableReason.songNotTrainable =>
    l10n.trainerModeUnavailableSong,
};
