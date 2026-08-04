import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/trainer/song_trainer_setup_controller.dart';
import '../../application/trainer/song_trainer_setup_state.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/trainer_config.dart';
import '../../domain/models/trainer_range.dart';
import '../widgets/song_track_picker.dart';
import '../widgets/trainer_range_picker.dart';
import '../widgets/tuning_capo_reminder.dart';

/// Selects immutable trainer configuration values; it does not start a
/// transport, playback, microphone, or practice session.
final class TrainerSetupScreen extends ConsumerStatefulWidget {
  const TrainerSetupScreen({
    required this.songId,
    this.onComplete,
    this.onRepairMissingBackingAsset,
    super.key,
  });

  final String songId;
  final ValueChanged<TrainerConfig>? onComplete;
  final VoidCallback? onRepairMissingBackingAsset;

  @override
  ConsumerState<TrainerSetupScreen> createState() => _TrainerSetupScreenState();
}

final class _TrainerSetupScreenState extends ConsumerState<TrainerSetupScreen> {
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
      appBar: AppBar(title: Text(l10n.trainerSetupTitle)),
      body: switch (state.status) {
        SongTrainerSetupStatus.idle || SongTrainerSetupStatus.loading => Center(
          child: Semantics(
            label: l10n.trainerSetupLoading,
            child: const CircularProgressIndicator(),
          ),
        ),
        SongTrainerSetupStatus.failure => Center(
          child: FilledButton(
            onPressed: _loadIfNeeded,
            child: Text(l10n.songOverviewRetry),
          ),
        ),
        SongTrainerSetupStatus.ready => _SetupBody(
          state: state,
          onTrackSelected: (track) => controller.selectTrack(track.id),
          onRangeSelected: controller.selectRange,
          onModeSelected: controller.selectMode,
          onCountInChanged: controller.setCountInBars,
          onMetronomeChanged: controller.setMetronomeEnabled,
          onLoopChanged: controller.setLoopEnabled,
          onSpeedChanged: controller.setTargetSpeed,
          onStart: () {
            final config = controller.complete();
            if (config != null) widget.onComplete?.call(config);
          },
          onRepairMissingBackingAsset: widget.onRepairMissingBackingAsset,
        ),
      },
    );
  }
}

final class _SetupBody extends StatelessWidget {
  const _SetupBody({
    required this.state,
    required this.onTrackSelected,
    required this.onRangeSelected,
    required this.onModeSelected,
    required this.onCountInChanged,
    required this.onMetronomeChanged,
    required this.onLoopChanged,
    required this.onSpeedChanged,
    required this.onStart,
    required this.onRepairMissingBackingAsset,
  });

  final SongTrainerSetupState state;
  final ValueChanged<TrainerTrackOption> onTrackSelected;
  final bool Function(TrainerRange range) onRangeSelected;
  final ValueChanged<TrainerMode> onModeSelected;
  final ValueChanged<int> onCountInChanged;
  final ValueChanged<bool> onMetronomeChanged;
  final ValueChanged<bool> onLoopChanged;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback onStart;
  final VoidCallback? onRepairMissingBackingAsset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = state.config;
    if (state.tracks.isEmpty) return Center(child: Text(l10n.trainerNoTracks));
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            l10n.trainerSetupTrack,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SongTrackPicker(tracks: state.tracks, onSelected: onTrackSelected),
          const SizedBox(height: 16),
          Text(
            l10n.trainerSetupMode,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          RadioGroup<TrainerMode>(
            groupValue: config?.mode,
            onChanged: (selected) {
              if (selected != null &&
                  state.modeAvailability(selected).isEnabled) {
                onModeSelected(selected);
              }
            },
            child: Column(
              children: <Widget>[
                for (final mode in TrainerMode.values)
                  RadioListTile<TrainerMode>(
                    key: Key('trainer-mode-${mode.name}'),
                    value: mode,
                    title: Text(_modeLabel(l10n, mode)),
                    subtitle: state.modeAvailability(mode).isEnabled
                        ? null
                        : Text(
                            _unavailableLabel(
                              l10n,
                              state.modeAvailability(mode),
                            ),
                          ),
                    enabled: state.modeAvailability(mode).isEnabled,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TrainerRangePicker(
            sections: state.sections,
            selection: config?.selection ?? const FullSongRange(),
            onSelected: onRangeSelected,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            key: const Key('trainer-count-in'),
            initialValue: config?.countInBars ?? 0,
            decoration: InputDecoration(labelText: l10n.trainerCountIn),
            items: <DropdownMenuItem<int>>[
              for (var bars = 0; bars <= 4; bars++)
                DropdownMenuItem<int>(value: bars, child: Text('$bars')),
            ],
            onChanged: (bars) {
              if (bars != null) onCountInChanged(bars);
            },
          ),
          SwitchListTile(
            key: const Key('trainer-metronome'),
            title: Text(l10n.trainerMetronome),
            value: config?.metronomeEnabled ?? false,
            onChanged: onMetronomeChanged,
          ),
          SwitchListTile(
            key: const Key('trainer-loop'),
            title: Text(l10n.trainerLoop),
            value: config?.loopConfig.maxRepeats != null,
            onChanged: onLoopChanged,
          ),
          Text(
            l10n.trainerTargetSpeed(((config?.targetSpeed ?? 1) * 100).round()),
          ),
          Slider(
            key: const Key('trainer-target-speed'),
            value: config?.targetSpeed ?? TrainerConfig.defaultSpeed,
            min: TrainerConfig.minimumSpeed,
            max: TrainerConfig.maximumSpeed,
            divisions: 20,
            onChanged: onSpeedChanged,
          ),
          Semantics(
            key: const Key('trainer-backing-rate-pending'),
            enabled: false,
            label: l10n.trainerBackingRatePending,
            child: ListTile(
              enabled: false,
              title: Text(l10n.trainerBackingRatePending),
            ),
          ),
          if (state.hasMissingBackingAsset)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(l10n.trainerMissingBacking),
                OutlinedButton(
                  onPressed: onRepairMissingBackingAsset,
                  child: Text(l10n.trainerRepairBacking),
                ),
              ],
            ),
          TuningCapoReminder(
            tuning: config?.tuningReminder,
            showCapoReminder: state.showCapoReminder,
            canResume: state.canResume,
          ),
          const SizedBox(height: 16),
          if (config == null) Text(l10n.trainerNoConfig),
          FilledButton(
            key: const Key('trainer-setup-start'),
            onPressed: config == null ? null : onStart,
            child: Text(l10n.trainerSetupStart),
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
