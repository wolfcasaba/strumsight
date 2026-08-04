import '../../../../core/music/tuning.dart';

import 'loop_config.dart';
import 'song_id.dart';
import 'trainer_range.dart';

/// The scoring lane selected for one future trainer session.
enum TrainerMode { chord, rhythm, pitch }

/// Immutable output of Song Trainer setup.
///
/// This value contains only the selected session inputs. It deliberately does
/// not retain a [SongDocument], so setup cannot mutate the persisted song.
final class TrainerConfig {
  TrainerConfig({
    required this.songId,
    required this.songRevision,
    required this.trackId,
    required this.selection,
    required this.range,
    required this.mode,
    required this.targetSpeed,
    required this.countInBars,
    required this.metronomeEnabled,
    required this.loopConfig,
    required this.tuningReminder,
    required this.capo,
    required this.capoReminder,
  }) {
    if (!targetSpeed.isFinite ||
        targetSpeed < minimumSpeed ||
        targetSpeed > maximumSpeed) {
      throw ArgumentError.value(
        targetSpeed,
        'targetSpeed',
        'Trainer speed must stay within the supported setup range.',
      );
    }
    if (songRevision < 0) {
      throw ArgumentError.value(
        songRevision,
        'songRevision',
        'Song revision cannot be negative.',
      );
    }
    if (countInBars < 0) {
      throw ArgumentError.value(
        countInBars,
        'countInBars',
        'Count-in bars cannot be negative.',
      );
    }
    if (capo < 0) {
      throw ArgumentError.value(capo, 'capo', 'Capo fret cannot be negative.');
    }
    if (loopConfig.range != range) {
      throw ArgumentError.value(
        loopConfig,
        'loopConfig',
        'The loop and session ranges must match.',
      );
    }
  }

  static const double minimumSpeed = 0.5;
  static const double maximumSpeed = 1.5;
  static const double defaultSpeed = 1;

  final SongId songId;
  final int songRevision;
  final SongTrackId trackId;
  final TrainerRange selection;
  final MeasureRange range;
  final TrainerMode mode;
  final double targetSpeed;
  final int countInBars;
  final bool metronomeEnabled;
  final LoopConfig loopConfig;
  final Tuning? tuningReminder;
  final int capo;
  final bool capoReminder;

  @override
  bool operator ==(Object other) =>
      other is TrainerConfig &&
      other.songId == songId &&
      other.songRevision == songRevision &&
      other.trackId == trackId &&
      other.selection == selection &&
      other.range == range &&
      other.mode == mode &&
      other.targetSpeed == targetSpeed &&
      other.countInBars == countInBars &&
      other.metronomeEnabled == metronomeEnabled &&
      other.loopConfig == loopConfig &&
      other.tuningReminder == tuningReminder &&
      other.capo == capo &&
      other.capoReminder == capoReminder;

  @override
  int get hashCode => Object.hash(
    songId,
    songRevision,
    trackId,
    selection,
    range,
    mode,
    targetSpeed,
    countInBars,
    metronomeEnabled,
    loopConfig,
    tuningReminder,
    capo,
    capoReminder,
  );
}
