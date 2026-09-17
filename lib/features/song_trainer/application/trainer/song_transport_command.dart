import '../../domain/models/song_asset_reference.dart';

sealed class SongTransportCommand {
  const SongTransportCommand();
}

final class PrepareSongTransport extends SongTransportCommand {
  const PrepareSongTransport({
    required this.asset,
    this.gridOffset = Duration.zero,
  });

  /// The backing track to load, or `null` for a SILENT transport.
  ///
  /// E16-R01/A4: a song with no backing audio still needs a running
  /// transport — it is what advances the playhead the lanes and the highway
  /// read. A `null` asset prepares the state machine and its clock while the
  /// player is left untouched; every other command then behaves identically,
  /// minus the audio I/O.
  final SongAssetReference? asset;

  final Duration gridOffset;
}

final class StartSongTransport extends SongTransportCommand {
  const StartSongTransport({this.withCountIn = false});

  final bool withCountIn;
}

final class CompleteCountIn extends SongTransportCommand {
  const CompleteCountIn();
}

final class PauseSongTransport extends SongTransportCommand {
  const PauseSongTransport();
}

final class ResumeSongTransport extends SongTransportCommand {
  const ResumeSongTransport();
}

final class SeekSongTransport extends SongTransportCommand {
  const SeekSongTransport(this.position);

  final Duration position;
}

final class SetSongTransportSpeed extends SongTransportCommand {
  const SetSongTransportSpeed(this.speed);

  final double speed;
}

final class RestartSongTransport extends SongTransportCommand {
  const RestartSongTransport();
}

final class FinishSongTransport extends SongTransportCommand {
  const FinishSongTransport();
}

final class StopSongTransport extends SongTransportCommand {
  const StopSongTransport();
}
