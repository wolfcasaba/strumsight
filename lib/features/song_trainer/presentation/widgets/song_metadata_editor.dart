import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/models/song_metadata.dart';

/// Small metadata surface; the controller remains the owner of the draft.
final class SongMetadataEditor extends StatelessWidget {
  const SongMetadataEditor({
    required this.metadata,
    required this.onChanged,
    super.key,
  });

  final SongMetadata metadata;
  final ValueChanged<SongMetadata> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          l10n.songEditorMetadata,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        TextFormField(
          key: const Key('song-editor-title'),
          initialValue: metadata.title,
          decoration: InputDecoration(labelText: l10n.songEditorTitleField),
          onFieldSubmitted: (title) => onChanged(_copy(metadata, title: title)),
        ),
        TextFormField(
          key: const Key('song-editor-artist'),
          initialValue: metadata.artist,
          decoration: InputDecoration(labelText: l10n.songEditorArtistField),
          onFieldSubmitted: (artist) => onChanged(
            _copy(metadata, artist: artist.isEmpty ? null : artist),
          ),
        ),
      ],
    );
  }

  static SongMetadata _copy(
    SongMetadata source, {
    String? title,
    String? artist,
  }) => SongMetadata(
    title: title ?? source.title,
    artist: artist ?? source.artist,
    album: source.album,
    composer: source.composer,
    copyright: source.copyright,
    tags: source.tags,
    notes: source.notes,
    defaultTuning: source.defaultTuning,
    defaultCapo: source.defaultCapo,
    originalKey: source.originalKey,
    artworkAssetId: source.artworkAssetId,
  );
}
