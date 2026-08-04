import '../../domain/models/song_asset_reference.dart';

sealed class SongTransportCommand {
  const SongTransportCommand();
}

final class PrepareSongTransport extends SongTransportCommand {
  const PrepareSongTransport({
    required this.asset,
    this.gridOffset = Duration.zero,
  });

  final SongAssetReference asset;
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
