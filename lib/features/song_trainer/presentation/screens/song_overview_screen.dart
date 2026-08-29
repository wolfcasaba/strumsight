import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routing/app_route.dart';
import '../../../../core/design_system/public.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/song_trainer_providers.dart';
import '../../application/trainer/song_trainer_setup_controller.dart';
import '../../application/trainer/song_trainer_setup_state.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/song_source.dart';
import '../../domain/models/trainer_config.dart';
import '../../domain/models/trainer_range.dart';
import '../widgets/song_section_list.dart';
import '../widgets/song_source_badge.dart';
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

  /// Provenance fetched independently of [songTrainerSetupControllerProvider]
  /// — the setup state does not carry `SongSource` / `SongMetadata.copyright`
  /// (§0.0/B/R16), so the overview loads the document once more, purely for
  /// display. `null` until the read resolves or when it fails; the failure
  /// is silent here because [songTrainerSetupControllerProvider] already
  /// surfaces the authoritative load failure for this song.
  SongSource? _source;
  String? _copyright;

  @override
  void initState() {
    super.initState();
    _songId = SongId(widget.songId);
    Future<void>.microtask(_loadIfNeeded);
    Future<void>.microtask(_loadProvenance);
  }

  void _loadIfNeeded() {
    final controller = ref.read(songTrainerSetupControllerProvider(_songId));
    if (controller.state.status == SongTrainerSetupStatus.idle ||
        controller.state.songId != _songId) {
      unawaited(controller.load(_songId));
    }
  }

  Future<void> _loadProvenance() async {
    final repository = ref.read(songRepositoryProvider);
    final result = await repository.get(_songId);
    if (!mounted) return;
    if (result case Success<SongDocument?>(value: final document?)) {
      setState(() {
        _source = document.source;
        _copyright = document.metadata.copyright;
      });
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
        SongTrainerSetupStatus.idle ||
        SongTrainerSetupStatus.loading => Semantics(
          label: l10n.songOverviewLoading,
          child: const _OverviewLoading(),
        ),
        SongTrainerSetupStatus.failure => _OverviewError(
          onRetry: _loadIfNeeded,
        ),
        SongTrainerSetupStatus.ready => _OverviewBody(
          state: state,
          source: _source,
          copyright: _copyright,
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
    required this.source,
    required this.copyright,
    required this.onSectionSelected,
    required this.onTrackSelected,
    required this.onStart,
  });

  final SongTrainerSetupState state;
  final SongSource? source;
  final String? copyright;
  final ValueChanged<TrainerSectionOption> onSectionSelected;
  final ValueChanged<TrainerTrackOption> onTrackSelected;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final title = state.title ?? '';
    final source = this.source;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(SsSpacing.space4),
        children: <Widget>[
          Text(
            title,
            style: typography.titleLarge.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: SsSpacing.space6),
          Text(
            l10n.songOverviewSections,
            style: typography.titleMedium.copyWith(color: colors.textPrimary),
          ),
          SongSectionList(
            sections: state.sections,
            onSelected: onSectionSelected,
          ),
          const SizedBox(height: SsSpacing.space6),
          Text(
            l10n.songOverviewTracks,
            style: typography.titleMedium.copyWith(color: colors.textPrimary),
          ),
          SongTrackPicker(tracks: state.tracks, onSelected: onTrackSelected),
          const SizedBox(height: SsSpacing.space6),
          Text(
            l10n.songOverviewCapabilities,
            style: typography.titleMedium.copyWith(color: colors.textPrimary),
          ),
          for (final mode in TrainerMode.values)
            ListTile(
              enabled: state.modeAvailability(mode).isEnabled,
              title: Text(_modeLabel(l10n, mode)),
              subtitle: state.modeAvailability(mode).isEnabled
                  ? null
                  : Text(_unavailableLabel(l10n, state.modeAvailability(mode))),
            ),
          const SizedBox(height: SsSpacing.space6),
          // Stays a literal FilledButton (not SsButton): `song_asset_state_test.dart`
          // casts `tester.widget<FilledButton>(find.byKey(...))` directly.
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
          if (source != null) ...[
            const SizedBox(height: SsSpacing.space4),
            Wrap(
              key: const Key('song-overview-source-row'),
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: SsSpacing.space2,
              children: <Widget>[
                SongSourceBadge(sourceType: source.type),
                if (copyright != null)
                  Text(
                    l10n.songOverviewLicense(copyright!),
                    key: const Key('song-overview-license'),
                    style: typography.bodyMedium.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
              ],
            ),
          ],
          if (state.hasMissingBackingAsset) ...[
            const SizedBox(height: SsSpacing.space3),
            Semantics(
              key: const Key('song-overview-missing-backing'),
              label: l10n.songOverviewMissingBackingAsset,
              child: Row(
                children: <Widget>[
                  Icon(Icons.music_off_outlined, color: colors.warning),
                  const SizedBox(width: SsSpacing.space2),
                  Expanded(
                    child: Text(
                      l10n.songOverviewMissingBackingAsset,
                      style: typography.bodyMedium.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OverviewLoading extends StatelessWidget {
  const _OverviewLoading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SsSkeleton(
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
class _OverviewError extends StatelessWidget {
  const _OverviewError({required this.onRetry});
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
