import '../../domain/models/song_id.dart';
import '../../domain/models/trainer_config.dart';

/// Lifecycle of the read-only trainer setup flow.
enum SongTrainerSetupStatus { idle, loading, ready, failure }

/// Explicit reason why a scoring lane cannot be selected.
enum TrainerModeUnavailableReason {
  trackNotCompatible,
  unsupportedChord,
  polyphonicNotes,
  songNotTrainable,
}

/// Honest availability state for backing playback-rate controls.
///
/// Rate support starts in E03-R18. R17 never advertises it as supported.
enum BackingRateAvailability { pending }

/// Immutable availability of one [TrainerMode] for the selected track.
final class TrainerModeAvailability {
  const TrainerModeAvailability.enabled() : isEnabled = true, reason = null;

  const TrainerModeAvailability.disabled(this.reason) : isEnabled = false;

  final bool isEnabled;
  final TrainerModeUnavailableReason? reason;

  @override
  bool operator ==(Object other) =>
      other is TrainerModeAvailability &&
      other.isEnabled == isEnabled &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(isEnabled, reason);
}

/// A presentation-safe summary of one selectable song track.
final class TrainerTrackOption {
  const TrainerTrackOption({
    required this.id,
    required this.name,
    required this.kind,
    required this.isEnabled,
    required this.isSelected,
  });

  final SongTrackId id;
  final String name;
  final String kind;
  final bool isEnabled;
  final bool isSelected;
}

/// A presentation-safe summary of one selectable song section.
final class TrainerSectionOption {
  const TrainerSectionOption({
    required this.id,
    required this.name,
    required this.startMeasure,
    required this.endMeasureExclusive,
  });

  final SongSectionId id;
  final String name;
  final int startMeasure;
  final int endMeasureExclusive;
}

/// Immutable state rendered by Song Overview and Trainer Setup.
final class SongTrainerSetupState {
  SongTrainerSetupState({
    required this.status,
    this.songId,
    this.title,
    List<TrainerTrackOption> tracks = const <TrainerTrackOption>[],
    List<TrainerSectionOption> sections = const <TrainerSectionOption>[],
    Map<TrainerMode, TrainerModeAvailability>? modeAvailabilities,
    this.config,
    this.hasBackingTrack = false,
    this.hasMissingBackingAsset = false,
    this.backingRateAvailability = BackingRateAvailability.pending,
    this.showTuningReminder = false,
    this.showCapoReminder = false,
    this.canResume = false,
    this.failureCode,
  }) : tracks = List<TrainerTrackOption>.unmodifiable(tracks),
       sections = List<TrainerSectionOption>.unmodifiable(sections),
       modeAvailabilities =
           Map<TrainerMode, TrainerModeAvailability>.unmodifiable(
             modeAvailabilities ??
                 const <TrainerMode, TrainerModeAvailability>{},
           );

  factory SongTrainerSetupState.idle() =>
      SongTrainerSetupState(status: SongTrainerSetupStatus.idle);

  final SongTrainerSetupStatus status;
  final SongId? songId;
  final String? title;
  final List<TrainerTrackOption> tracks;
  final List<TrainerSectionOption> sections;
  final Map<TrainerMode, TrainerModeAvailability> modeAvailabilities;
  final TrainerConfig? config;
  final bool hasBackingTrack;
  final bool hasMissingBackingAsset;
  final BackingRateAvailability backingRateAvailability;
  final bool showTuningReminder;
  final bool showCapoReminder;
  final bool canResume;
  final String? failureCode;

  TrainerModeAvailability modeAvailability(TrainerMode mode) =>
      modeAvailabilities[mode] ??
      const TrainerModeAvailability.disabled(
        TrainerModeUnavailableReason.trackNotCompatible,
      );
}
