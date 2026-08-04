import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/music/tuning.dart';
import '../../../../core/foundation/app_result.dart';

import '../song_trainer_providers.dart';
import '../../domain/models/loop_config.dart';
import '../../domain/models/song_capability.dart';
import '../../domain/models/song_document.dart';
import '../../domain/models/song_id.dart';
import '../../domain/models/song_section.dart';
import '../../domain/models/song_track.dart';
import '../../domain/models/trainer_config.dart';
import '../../domain/models/trainer_range.dart';
import '../../domain/repositories/song_repository.dart';
import '../../domain/services/song_capability_resolver.dart';
import '../../domain/services/song_validator.dart';
import 'song_trainer_setup_state.dart';

/// Route-scoped, read-only coordinator for Song Overview and Trainer Setup.
///
/// The controller's only provider-supplied dependency is [SongRepository].
/// Validation and capability resolution are pure domain services constructed
/// directly here, so no provider wiring or hidden mutable service is needed.
final class SongTrainerSetupController {
  SongTrainerSetupController({required this.repository});

  final SongRepository repository;
  final StreamController<SongTrainerSetupState> _states =
      StreamController<SongTrainerSetupState>.broadcast(sync: true);

  SongTrainerSetupState _state = SongTrainerSetupState.idle();
  SongId? _songId;
  int _songRevision = 0;
  String? _title;
  List<SongTrack> _tracks = const <SongTrack>[];
  List<SongSection> _sections = const <SongSection>[];
  bool _canTrain = false;
  bool _hasBackingTrack = false;
  bool _hasMissingBackingAsset = false;
  bool _showTuningReminder = false;
  bool _showCapoReminder = false;
  Tuning? _tuningReminder;
  int _capo = 0;
  SongTrackId? _selectedTrackId;
  TrainerRange _selection = const FullSongRange();
  TrainerMode? _mode;
  double _targetSpeed = TrainerConfig.defaultSpeed;
  int _countInBars = 1;
  bool _metronomeEnabled = true;
  int? _loopRepeats;
  SongCapabilityReport? _capability;

  SongTrainerSetupState get state => _state;
  Stream<SongTrainerSetupState> get states => _states.stream;

  /// Loads one immutable document and derives presentation-safe setup data.
  Future<void> load(SongId id) async {
    _emit(
      SongTrainerSetupState(status: SongTrainerSetupStatus.loading, songId: id),
    );
    final result = await repository.get(id);
    switch (result) {
      case Failure<SongDocument?>(:final error):
        _emit(
          SongTrainerSetupState(
            status: SongTrainerSetupStatus.failure,
            songId: id,
            failureCode: error.code,
          ),
        );
      case Success<SongDocument?>(value: null):
        _emit(
          SongTrainerSetupState(
            status: SongTrainerSetupStatus.failure,
            songId: id,
            failureCode: SongRepositoryErrorCode.notFound,
          ),
        );
      case Success<SongDocument?>(:final value?):
        _loadDocument(value);
    }
  }

  /// Selects a participant track when it offers at least one supported mode.
  bool selectTrack(SongTrackId trackId) {
    final track = _trackById(trackId);
    if (track == null || !track.enabled) return false;
    _selectedTrackId = trackId;
    final modes = _modeAvailabilities(track);
    _mode = _firstEnabledMode(modes);
    _publishReady();
    return _mode != null;
  }

  /// Accepts a range only when it resolves inside the current song bounds.
  bool selectRange(TrainerRange range) {
    if (range case BookmarkRange()
        when _songId == null ||
            !range.matchesSong(songId: _songId!, revision: _songRevision)) {
      return false;
    }
    if (range.resolve(measureCount: _measureCount, sections: _sections) ==
        null) {
      return false;
    }
    _selection = range;
    _publishReady();
    return true;
  }

  /// Changes the active scoring lane only when the capability matrix permits it.
  bool selectMode(TrainerMode mode) {
    final availability = _modeAvailabilities(_selectedTrack)[mode];
    if (availability == null || !availability.isEnabled) {
      return false;
    }
    _mode = mode;
    _publishReady();
    return true;
  }

  /// Changes setup speed within the SDD's 50%–150% configuration range.
  bool setTargetSpeed(double speed) {
    if (!speed.isFinite ||
        speed < TrainerConfig.minimumSpeed ||
        speed > TrainerConfig.maximumSpeed) {
      return false;
    }
    _targetSpeed = speed;
    _publishReady();
    return true;
  }

  bool setCountInBars(int bars) {
    if (bars < 0) return false;
    _countInBars = bars;
    _publishReady();
    return true;
  }

  void setMetronomeEnabled(bool enabled) {
    _metronomeEnabled = enabled;
    _publishReady();
  }

  void setLoopEnabled(bool enabled) {
    _loopRepeats = enabled ? 2 : null;
    _publishReady();
  }

  /// Returns the one immutable hand-off value, or `null` until setup is valid.
  TrainerConfig? complete() =>
      _state.status == SongTrainerSetupStatus.ready ? _state.config : null;

  void dispose() => unawaited(_states.close());

  void _loadDocument(SongDocument document) {
    final validation = const SongValidator().validate(document);
    _capability = const SongCapabilityResolver().resolve(
      report: validation,
      profile: SongCapabilityProfile.trainer,
    );
    _songId = document.id;
    _songRevision = document.revision;
    _title = document.metadata.title;
    _tracks = document.tracks;
    _sections = document.sections;
    _canTrain = _capability!.canTrain;
    _hasBackingTrack = document.tracks.any(
      (track) => track is BackingAudioTrack,
    );
    final referencedAssetIds = document.assets.map((asset) => asset.id).toSet();
    _hasMissingBackingAsset = document.tracks
        .whereType<BackingAudioTrack>()
        .any((track) => !referencedAssetIds.contains(track.assetId));
    _showTuningReminder = document.metadata.defaultTuning != null;
    _showCapoReminder = document.metadata.defaultCapo > 0;
    _tuningReminder = document.metadata.defaultTuning;
    _capo = document.metadata.defaultCapo;
    _measureCount = document.measures.length;
    _selection = const FullSongRange();
    _targetSpeed = TrainerConfig.defaultSpeed;
    _countInBars = 1;
    _metronomeEnabled = true;
    _loopRepeats = null;
    _selectedTrackId = null;
    for (final track in _tracks) {
      if (track.enabled) {
        _selectedTrackId = track.id;
        break;
      }
    }
    _mode = _firstEnabledMode(_modeAvailabilities(_selectedTrack));
    _publishReady();
  }

  int _measureCount = 0;

  SongTrack? get _selectedTrack =>
      _selectedTrackId == null ? null : _trackById(_selectedTrackId!);

  SongTrack? _trackById(SongTrackId id) {
    for (final track in _tracks) {
      if (track.id == id) return track;
    }
    return null;
  }

  Map<TrainerMode, TrainerModeAvailability> _modeAvailabilities(
    SongTrack? track,
  ) {
    if (!_canTrain) {
      return <TrainerMode, TrainerModeAvailability>{
        for (final mode in TrainerMode.values)
          mode: const TrainerModeAvailability.disabled(
            TrainerModeUnavailableReason.songNotTrainable,
          ),
      };
    }
    if (track == null || !track.enabled) {
      return <TrainerMode, TrainerModeAvailability>{
        for (final mode in TrainerMode.values)
          mode: const TrainerModeAvailability.disabled(
            TrainerModeUnavailableReason.trackNotCompatible,
          ),
      };
    }
    final capability = _capability!;
    return <TrainerMode, TrainerModeAvailability>{
      TrainerMode.chord: track is ChordTrack
          ? capability.chord.scoring
                ? const TrainerModeAvailability.enabled()
                : const TrainerModeAvailability.disabled(
                    TrainerModeUnavailableReason.unsupportedChord,
                  )
          : const TrainerModeAvailability.disabled(
              TrainerModeUnavailableReason.trackNotCompatible,
            ),
      TrainerMode.rhythm:
          track is ChordTrack || track is StrumTrack || track is NoteTrack
          ? const TrainerModeAvailability.enabled()
          : const TrainerModeAvailability.disabled(
              TrainerModeUnavailableReason.trackNotCompatible,
            ),
      TrainerMode.pitch: track is NoteTrack
          ? capability.pitch.scoring && capability.pitch.isMonophonic
                ? const TrainerModeAvailability.enabled()
                : const TrainerModeAvailability.disabled(
                    TrainerModeUnavailableReason.polyphonicNotes,
                  )
          : const TrainerModeAvailability.disabled(
              TrainerModeUnavailableReason.trackNotCompatible,
            ),
    };
  }

  TrainerMode? _firstEnabledMode(
    Map<TrainerMode, TrainerModeAvailability> modes,
  ) {
    for (final mode in TrainerMode.values) {
      if (modes[mode]!.isEnabled) return mode;
    }
    return null;
  }

  void _publishReady() {
    final modeAvailabilities = _modeAvailabilities(_selectedTrack);
    if (_mode == null || !modeAvailabilities[_mode]!.isEnabled) {
      _mode = _firstEnabledMode(modeAvailabilities);
    }
    final range = _selection.resolve(
      measureCount: _measureCount,
      sections: _sections,
    );
    final config =
        _songId == null ||
            _selectedTrackId == null ||
            _mode == null ||
            range == null
        ? null
        : TrainerConfig(
            songId: _songId!,
            songRevision: _songRevision,
            trackId: _selectedTrackId!,
            selection: _selection,
            range: range,
            mode: _mode!,
            targetSpeed: _targetSpeed,
            countInBars: _countInBars,
            metronomeEnabled: _metronomeEnabled,
            loopConfig: LoopConfig(range: range, maxRepeats: _loopRepeats),
            tuningReminder: _tuningReminder,
            capo: _capo,
            capoReminder: _showCapoReminder,
          );
    _emit(
      SongTrainerSetupState(
        status: SongTrainerSetupStatus.ready,
        songId: _songId,
        title: _title,
        tracks: List<TrainerTrackOption>.unmodifiable(
          _tracks.map(
            (track) => TrainerTrackOption(
              id: track.id,
              name: track.name,
              kind: _trackKind(track),
              isEnabled: track.enabled,
              isSelected: track.id == _selectedTrackId,
            ),
          ),
        ),
        sections: List<TrainerSectionOption>.unmodifiable(
          _sections.map(
            (section) => TrainerSectionOption(
              id: section.id,
              name: section.name,
              startMeasure: section.startMeasure,
              endMeasureExclusive: section.endMeasureExclusive,
            ),
          ),
        ),
        modeAvailabilities: modeAvailabilities,
        config: config,
        hasBackingTrack: _hasBackingTrack,
        hasMissingBackingAsset: _hasMissingBackingAsset,
        showTuningReminder: _showTuningReminder,
        showCapoReminder: _showCapoReminder,
      ),
    );
  }

  String _trackKind(SongTrack track) => switch (track) {
    ChordTrack() => 'chord',
    StrumTrack() => 'strum',
    NoteTrack() => 'note',
    LyricsTrack() => 'lyrics',
    MarkerTrack() => 'marker',
    BackingAudioTrack() => 'backing',
  };

  void _emit(SongTrainerSetupState next) {
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }
}

/// Co-located route-scoped setup controller. Its only provider dependency is
/// the existing Song Trainer repository binding.
final songTrainerSetupControllerProvider = Provider.autoDispose
    .family<SongTrainerSetupController, SongId>((ref, _) {
      final controller = SongTrainerSetupController(
        repository: ref.watch(songRepositoryProvider),
      );
      ref.onDispose(controller.dispose);
      return controller;
    });

final songTrainerSetupStateProvider = StreamProvider.autoDispose
    .family<SongTrainerSetupState, SongId>(
      (ref, id) => ref.watch(songTrainerSetupControllerProvider(id)).states,
    );
