/// Egy csatolt média csempéje — a szerkesztőben és a feedben (javító
/// sáv R27).
///
/// EGY widget mindkét helyre, mert a két felület ugyanazt a
/// [CommunityMediaAttachment]-et kapja, és két külön rajzoló azt
/// jelentené, hogy a „feldolgozás alatt" arc a szerkesztőben és a
/// feedben elcsúszhat egymástól.
///
/// **Amit rajzol:**
///
/// * `ready` + kép → a VALÓDI bájtok. A letöltés hitelesített
///   (`GET /community/media/{public_id}`), tehát nem `Image.network`:
///   annak nincs JWT-je, és a szerver 404-et adna. A bájtokat a
///   [communityMediaBytesProvider] hozza, és a Riverpod
///   `autoDispose`-a dobja el, amikor a csempe eltűnik.
/// * `ready` + hang → a Kör 19-es [CommunityMediaPlayer] `ready` arca.
///   Ez a widget SZÁNDÉKOSAN nem szólaltat meg hangot: a lejátszó
///   bekötése a Kör 19 óta nyitott horog, és egy néma „lejátszás" gomb
///   rosszabb, mint a mai, kimondottan placeholder arc.
/// * minden más állapot → ugyanaz a Kör 19-es widget, ugyanazokkal az
///   ARB kulcsokkal, amelyek R21 óta a fában vannak.
///
/// **A `pending` → `uploaded` leképezés EGYETLEN helye** a
/// [_processingStateFor] alatt: a szerver az első, vizsgálat előtti
/// állapotot `pending`-nek hívja, a Kör 19-es widget-enum `uploaded`-nek
/// (l. `domain/entities/community_media.dart` fejléce). A leképezés itt
/// él, tehát a widget és a pinelt Kör 19-es tesztje érintetlen marad.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/repositories/post_repository_impl.dart'
    show communityPostApiClientProvider;
import '../../domain/entities/community_media.dart';
import 'community_media_player.dart';

/// Egy csatolmány újrakódolt bájtjai, azonosító szerint.
///
/// `autoDispose`: egy feedből kigörgetett kép bájtjai nem maradnak a
/// memóriában. `family`: a kulcs a publikus azonosító, tehát két kártya
/// ugyanarra a médiára EGY letöltésen osztozik.
final communityMediaBytesProvider = FutureProvider.autoDispose
    .family<Uint8List, String>((ref, publicId) async {
      final client = ref.watch(communityPostApiClientProvider);
      if (client == null) {
        // Fiók nélküli mód: nincs hitelesített kliens, tehát a bájtokat
        // nem is lehet elkérni. Ugyanaz a hiba, amit a repository adna.
        throw const ConfigurationFailure();
      }
      final result = await client.getBytes('/community/media/$publicId');
      return switch (result) {
        Success(:final value) => value,
        Failure(:final error) => throw error,
      };
    });

/// A csatolmány megjelenítője.
class CommunityMediaTile extends ConsumerWidget {
  const CommunityMediaTile({
    super.key,
    required this.media,
    this.aspectRatio = 16 / 9,
    this.onRemove,
  });

  final CommunityMediaAttachment media;

  /// A `ready` kép kerete. A szerver a hosszabb élt korlátozza, tehát a
  /// tényleges képarány bármi lehet — a kép `BoxFit.cover`-rel tölti ki.
  final double aspectRatio;

  /// A szerkesztő „csatolmány eltávolítása" művelete. `null` a feedben:
  /// ott nincs mit eltávolítani.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = _content(context, ref);
    if (onRemove == null) return card;
    return Stack(
      alignment: Alignment.topRight,
      children: <Widget>[
        card,
        Padding(
          padding: const EdgeInsets.all(4),
          child: IconButton(
            key: Key('community-media-remove-${media.publicId}'),
            tooltip: AppLocalizations.of(context).communityMediaRemove,
            icon: const Icon(Icons.close),
            onPressed: onRemove,
          ),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, WidgetRef ref) {
    if (!media.isReady || media.kind != CommunityMediaKind.image) {
      return CommunityMediaPlayer(
        processingState: _processingStateFor(media.state),
        aspectRatio: aspectRatio,
        title: _rejectionLabel(context),
      );
    }
    final bytes = ref.watch(communityMediaBytesProvider(media.publicId));
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: bytes.when(
        data: (data) => ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            data,
            key: Key('community-media-image-${media.publicId}'),
            fit: BoxFit.cover,
            // A bájtok a szerver saját enkóderének kimenete, tehát egy
            // dekódolási hiba itt nem a felhasználó hibája — de attól
            // még nem szabad piros hiba-widgetet dobni a feedbe.
            errorBuilder: (context, error, stackTrace) => _MediaMessage(
              text: AppLocalizations.of(context).communityMediaUnavailable,
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _MediaMessage(
          text: AppLocalizations.of(context).communityMediaUnavailable,
        ),
      ),
    );
  }

  /// Az elutasítás GÉPI kódjából lokalizált mondat.
  ///
  /// A szerver sosem küld kész szöveget; a token → mondat leképezés a
  /// kliensé. Az ismeretlen kód az általános mondatot kapja — egy
  /// nyersen kirakott `scanner_not_configured` a felhasználónak semmit
  /// nem mond.
  String? _rejectionLabel(BuildContext context) {
    if (media.state != CommunityMediaState.rejected) return null;
    final l10n = AppLocalizations.of(context);
    return switch (media.rejectionCode) {
      'unsupported_media_type' ||
      'scriptable_media_rejected' => l10n.communityMediaRejectedUnsupported,
      'empty_upload' => l10n.communityMediaRejectedEmpty,
      'file_too_large' => l10n.communityMediaRejectedTooLarge,
      'malware_detected' => l10n.communityMediaRejectedMalware,
      'image_unreadable' => l10n.communityMediaRejectedUnsupported,
      'scanner_not_configured' ||
      'scanner_unavailable' => l10n.communityMediaRejectedUnavailable,
      'audio_transcoder_unavailable' ||
      'audio_unreadable' ||
      'audio_too_long' => l10n.communityMediaRejectedAudio,
      _ => l10n.communityMediaRejectedGeneric,
    };
  }
}

/// A domain-állapot → Kör 19-es widget-állapot leképezés.
CommunityMediaProcessingState _processingStateFor(CommunityMediaState state) {
  return switch (state) {
    // A szerver `pending`-je és a widget `uploaded`-je UGYANAZ az
    // állapot — l. a fájl fejlécét.
    CommunityMediaState.pending => CommunityMediaProcessingState.uploaded,
    CommunityMediaState.scanning => CommunityMediaProcessingState.scanning,
    CommunityMediaState.transcoding =>
      CommunityMediaProcessingState.transcoding,
    CommunityMediaState.review => CommunityMediaProcessingState.review,
    CommunityMediaState.ready => CommunityMediaProcessingState.ready,
    CommunityMediaState.rejected => CommunityMediaProcessingState.rejected,
    CommunityMediaState.deleted => CommunityMediaProcessingState.deleted,
  };
}

/// Egy semleges, egysoros üzenet a kép helyén.
class _MediaMessage extends StatelessWidget {
  const _MediaMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
