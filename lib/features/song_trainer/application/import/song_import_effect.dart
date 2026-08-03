import '../../domain/models/song_id.dart';

/// One-shot boundary events, kept separate from durable [SongImportState].
sealed class SongImportEffect {
  const SongImportEffect();
}

final class RequestFilePickerEffect extends SongImportEffect {
  const RequestFilePickerEffect();

  @override
  bool operator ==(Object other) => other is RequestFilePickerEffect;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class CleanupFilePickerEffect extends SongImportEffect {
  const CleanupFilePickerEffect();

  @override
  bool operator ==(Object other) => other is CleanupFilePickerEffect;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class SongImportSucceededEffect extends SongImportEffect {
  const SongImportSucceededEffect(this.songId);

  final SongId songId;
}
