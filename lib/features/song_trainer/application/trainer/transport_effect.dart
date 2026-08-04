import '../../data/playback/backing_audio_player.dart';
import '../../domain/models/song_asset_reference.dart';

sealed class TransportEffect {
  const TransportEffect();
}

final class PrepareBackingAudioEffect extends TransportEffect {
  const PrepareBackingAudioEffect(this.asset);

  final SongAssetReference asset;
}

final class StartBackingAudioEffect extends TransportEffect {
  const StartBackingAudioEffect();
}

final class PauseBackingAudioEffect extends TransportEffect {
  const PauseBackingAudioEffect();
}

final class SeekBackingAudioEffect extends TransportEffect {
  const SeekBackingAudioEffect(this.position);

  final Duration position;
}

final class SetBackingRateEffect extends TransportEffect {
  const SetBackingRateEffect(this.rate);

  final double rate;
}

final class TransportFailureEffect extends TransportEffect {
  const TransportFailureEffect(this.code);

  final String code;
}

final class BackingDriftEffect extends TransportEffect {
  const BackingDriftEffect(this.report);

  final BackingDriftReport report;
}
