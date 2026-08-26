import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/models/song_source.dart';

/// Localised display label for a [SongSourceType] (ADR 0278 provenance).
String songSourceTypeLabel(AppLocalizations l10n, SongSourceType sourceType) =>
    switch (sourceType) {
      SongSourceType.legacyLocal => l10n.songLibrarySourceLegacy,
      SongSourceType.createdInApp => l10n.songLibrarySourceCreated,
      SongSourceType.strumSightJson => l10n.songLibrarySourceNativeJson,
      SongSourceType.musicXml => l10n.songLibrarySourceMusicXml,
      SongSourceType.compressedMusicXml => l10n.songLibrarySourceMxl,
      SongSourceType.midi => l10n.songLibrarySourceMidi,
      SongSourceType.guitarPro => l10n.songLibrarySourceGuitarPro,
    };

/// Compact provenance chip shown wherever a [SongSourceType] must be
/// visible to the user (ADR 0278). Never fabricates a source — the
/// [sourceType] is always the measured `SongSummary.sourceType` /
/// `SongDocument.source.type` value.
final class SongSourceBadge extends StatelessWidget {
  const SongSourceBadge({required this.sourceType, super.key});

  final SongSourceType sourceType;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = songSourceTypeLabel(l10n, sourceType);
    return Semantics(
      label: l10n.songLibrarySourceSemantic(label),
      child: Chip(
        visualDensity: VisualDensity.compact,
        avatar: const Icon(Icons.source_outlined, size: 16),
        label: Text(label),
      ),
    );
  }
}
