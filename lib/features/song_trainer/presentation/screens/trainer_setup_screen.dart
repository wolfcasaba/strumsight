import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/public.dart';
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
        SongTrainerSetupStatus.idle ||
        SongTrainerSetupStatus.loading => Semantics(
          label: l10n.trainerSetupLoading,
          child: const _SetupLoading(),
        ),
        SongTrainerSetupStatus.failure => _SetupError(onRetry: _loadIfNeeded),
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final config = state.config;
    if (state.tracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SsSpacing.space6),
          child: Text(
            l10n.trainerNoTracks,
            style: typography.bodyMedium.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(SsSpacing.space4),
        children: <Widget>[
          Text(
            l10n.trainerSetupTrack,
            style: typography.titleMedium.copyWith(color: colors.textPrimary),
          ),
          SongTrackPicker(tracks: state.tracks, onSelected: onTrackSelected),
          const SizedBox(height: SsSpacing.space4),
          Text(
            l10n.trainerSetupMode,
            style: typography.titleMedium.copyWith(color: colors.textPrimary),
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
          const SizedBox(height: SsSpacing.space4),
          TrainerRangePicker(
            sections: state.sections,
            selection: config?.selection ?? const FullSongRange(),
            onSelected: onRangeSelected,
          ),
          const SizedBox(height: SsSpacing.space4),
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
            style: typography.bodyMedium.copyWith(color: colors.textPrimary),
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
            Padding(
              padding: const EdgeInsets.only(top: SsSpacing.space2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    l10n.trainerMissingBacking,
                    style: typography.bodyMedium.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: SsSpacing.space2),
                  SsButton(
                    onPressed: onRepairMissingBackingAsset,
                    variant: SsButtonVariant.secondary,
                    label: l10n.trainerRepairBacking,
                  ),
                ],
              ),
            ),
          TuningCapoReminder(
            tuning: config?.tuningReminder,
            showCapoReminder: state.showCapoReminder,
            canResume: state.canResume,
          ),
          const SizedBox(height: SsSpacing.space4),
          if (config == null)
            Text(
              l10n.trainerNoConfig,
              style: typography.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
            ),
          // Stays a literal FilledButton (not SsButton): `trainer_setup_test.dart`
          // casts `tester.widget<FilledButton>(find.byKey(...))` directly.
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

final class _SetupLoading extends StatelessWidget {
  const _SetupLoading();

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
/// setup controller's `failureCode` (`song_trainer_setup_state.dart`) is a
/// bare string, not an [AppFailure] with a `retryable` flag, so there is
/// nothing honest to feed [SsFailurePresentation.from] without fabricating
/// one (E15-R04 review MAJOR-2). The single retry action already existed
/// pre-migration (`_loadIfNeeded`) — only its styling moves onto tokens.
final class _SetupError extends StatelessWidget {
  const _SetupError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SsSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colors.danger, size: 40),
            const SizedBox(height: SsSpacing.space4),
            SsButton(label: l10n.songOverviewRetry, onPressed: onRetry),
          ],
        ),
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
