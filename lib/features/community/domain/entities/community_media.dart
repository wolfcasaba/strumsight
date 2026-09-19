/// Egy poszthoz csatolt média és a feldolgozási állapota (javító sáv
/// R27).
///
/// A szerver `MediaOut` alakjának kliens-oldali párja
/// (`backend/app/community/schemas/media.py`). Az entitás
/// SZÁNDÉKOSAN nem hordoz sem belső azonosítót, sem tartalom-lenyomatot,
/// sem fájlrendszer-útvonalat: a huzalon sincsenek rajta, és a kliensnek
/// egyetlen dolog kell hozzájuk, a [publicId] — abból áll össze a
/// `GET /community/media/{public_id}` út.
///
/// **Miért van saját állapot-enum a Kör 19-es
/// `CommunityMediaProcessingState` mellett.** A Kör 19-es enum a
/// LEJÁTSZÓ widgeté (`presentation/widgets/community_media_player.dart`),
/// és a réteg-irány kötött: a domain nem olvashat presentationt. A két
/// halmaz ugyanaz a hét állapot, EGY szó kivételével: a szerver az első,
/// vizsgálat előtti állapotot `pending`-nek hívja (a bájtok beértek,
/// még senki nem nézte meg őket), a Kör 19-es widget ugyanezt
/// `uploaded`-nek, mert az AKKORI, aláírt-URL-es út csak a vödör-PUT
/// UTÁN értesült a sorról. A leképezés a presentation rétegben, EGY
/// helyen történik (`presentation/widgets/community_media_tile.dart`),
/// így a widget, a pinelt Kör 19-es tesztje és a két ARB fájl
/// érintetlen marad — a hozzá tartozó ARB kulcs
/// (`communityMediaPendingQueued` — „Media is queued for processing")
/// amúgy is pontosan ezt az állapotot mondja ki.
library;

/// Legfeljebb ennyi csatolmány mehet egy posztra.
///
/// A szerver ugyanezt a korlátot KÉTSZER is érvényesíti (a
/// `CreatePostRequest.media_ids` séma-szintű `max_length`-e 422-t ad, a
/// `media/attach.py` `MAX_MEDIA_PER_POST`-ja 400-at), tehát ez a szám
/// itt kényelem és nem védelem: a szerkesztő ettől nem kínál fel egy
/// ötödik csatolást, de a szabály attól még a szerveré.
const int kCommunityMaxMediaPerPost = 4;

/// Amit a szerver a bájtokról MOND — kép vagy hang.
///
/// Az `unknown` nem hiba-sentinel, hanem a szerver saját harmadik
/// értéke: egy magic-byte alapján el sem ismert feltöltés leíróján ez
/// áll, mert épp a fajtát nem sikerült megállapítani.
enum CommunityMediaKind {
  image('image'),
  audio('audio'),
  unknown('unknown');

  const CommunityMediaKind(this.wireValue);

  final String wireValue;
}

/// A szerveroldali feldolgozási állam-gép hét állapota.
///
/// A literálok a huzal-értékek (`backend/app/community/models/
/// media_upload.py` `MEDIA_STATE_*`), tehát a leképezés string-egyezés,
/// nem sorrend-egyezés.
enum CommunityMediaState {
  pending('pending'),
  scanning('scanning'),
  transcoding('transcoding'),
  review('review'),
  ready('ready'),
  rejected('rejected'),
  deleted('deleted');

  const CommunityMediaState(this.wireValue);

  final String wireValue;
}

/// Egy csatolt média a kliens szemével.
final class CommunityMediaAttachment {
  const CommunityMediaAttachment({
    required this.publicId,
    required this.kind,
    required this.state,
    required this.contentType,
    required this.createdAt,
    this.rejectionCode,
    this.sizeBytes = 0,
    this.width,
    this.height,
    this.durationMs,
  });

  /// A huzal-azonosító. Ebből áll össze a letöltési út, és EZ az
  /// egyetlen azonosító, amit a szerkesztő a `media_ids` listában
  /// visszaküld.
  final String publicId;

  final CommunityMediaKind kind;
  final CommunityMediaState state;

  /// Gépi elutasítási ok; `null`, hacsak az állapot nem `rejected`. A
  /// kliens ezt a tokent képezi le lokalizált mondatra — a szerver SOHA
  /// nem küld kész mondatot.
  final String? rejectionCode;

  /// A TÁROLT bájtok médiatípusa: a szerver újrakódolás utáni saját
  /// verdiktje, nem a feltöltő állítása.
  final String contentType;

  final int sizeBytes;
  final int? width;
  final int? height;
  final int? durationMs;
  final DateTime createdAt;

  /// Igaz, ha a bájtok letölthetők. Minden más állapotban a
  /// `GET /community/media/{id}` 404-et ad — a kártya ilyenkor a
  /// folyamat-, illetve az elutasított arcot rajzolja.
  bool get isReady => state == CommunityMediaState.ready;

  /// Igaz, amíg a feldolgozás tart (a négy nem-terminális állapot).
  bool get isProcessing => switch (state) {
    CommunityMediaState.pending ||
    CommunityMediaState.scanning ||
    CommunityMediaState.transcoding ||
    CommunityMediaState.review => true,
    CommunityMediaState.ready ||
    CommunityMediaState.rejected ||
    CommunityMediaState.deleted => false,
  };

  /// A hitelesített letöltési út — relatív, mert az `ApiClient` a
  /// bázis-URL-t és a jogosultság-fejlécet maga teszi hozzá.
  String get downloadPath => '/community/media/$publicId';

  @override
  bool operator ==(Object other) =>
      other is CommunityMediaAttachment &&
      other.publicId == publicId &&
      other.kind == kind &&
      other.state == state &&
      other.rejectionCode == rejectionCode &&
      other.contentType == contentType &&
      other.sizeBytes == sizeBytes &&
      other.width == width &&
      other.height == height &&
      other.durationMs == durationMs &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    publicId,
    kind,
    state,
    rejectionCode,
    contentType,
    sizeBytes,
    width,
    height,
    durationMs,
    createdAt,
  );
}

/// A szerver `kind` literáljából [CommunityMediaKind].
///
/// Az ismeretlen érték `unknown` — NEM `image`. Egy jövőbeli, harmadik
/// fajtát képnek nézni azt jelentené, hogy a régi kliens egy videót
/// néma állóképként próbál kirajzolni.
CommunityMediaKind communityMediaKindFromWire(Object? raw) {
  for (final value in CommunityMediaKind.values) {
    if (value.wireValue == raw) return value;
  }
  return CommunityMediaKind.unknown;
}

/// A szerver `state` literáljából [CommunityMediaState].
///
/// Az ismeretlen állapot `rejected` — a LEGSZŰKEBB értelmezés. Egy
/// jövőbeli állapotot `ready`-nek nézni azt jelentené, hogy a régi
/// kliens olyan bájtokat próbál megjeleníteni, amelyeket a szerver épp
/// visszatartott; fordítva legfeljebb egy kész média marad rejtve, amíg
/// a felhasználó frissít.
CommunityMediaState communityMediaStateFromWire(Object? raw) {
  for (final value in CommunityMediaState.values) {
    if (value.wireValue == raw) return value;
  }
  return CommunityMediaState.rejected;
}

/// Egy `MediaOut` → [CommunityMediaAttachment].
///
/// A hiányzó KÖTELEZŐ mező `FormatException`: egy `public_id` nélküli
/// leíró nem média, mert nincs mit letölteni róla.
CommunityMediaAttachment decodeCommunityMedia(Map<String, Object?> json) {
  final publicId = json['public_id'];
  if (publicId is! String || publicId.isEmpty) {
    throw const FormatException('community media wire: public_id is required');
  }
  final createdAt = json['created_at'];
  if (createdAt is! String) {
    throw const FormatException('community media wire: created_at is required');
  }
  final contentType = json['content_type'];
  final rejectionCode = json['rejection_code'];
  final sizeBytes = json['size_bytes'];
  return CommunityMediaAttachment(
    publicId: publicId,
    kind: communityMediaKindFromWire(json['kind']),
    state: communityMediaStateFromWire(json['state']),
    rejectionCode: rejectionCode is String ? rejectionCode : null,
    // A hiányzó típus `application/octet-stream`: a kártya ebből azt
    // olvassa ki, hogy nem tudja megjeleníteni — ami igaz is.
    contentType: contentType is String && contentType.isNotEmpty
        ? contentType
        : 'application/octet-stream',
    sizeBytes: sizeBytes is int && sizeBytes > 0 ? sizeBytes : 0,
    width: json['width'] is int ? json['width'] as int : null,
    height: json['height'] is int ? json['height'] as int : null,
    durationMs: json['duration_ms'] is int ? json['duration_ms'] as int : null,
    createdAt: DateTime.parse(createdAt).toUtc(),
  );
}

/// Egy poszt `media` tömbje → csatolmány-lista.
///
/// A hiányzó kulcs ÜRES lista, nem hiba: a szerver minden poszthoz küldi
/// a mezőt, de egy régebbi (média előtti) gyorsítótár-bejegyzésen nincs
/// rajta, és egy ilyen bejegyzést eldobni több kárt okozna, mint amennyi
/// hasznot a szigor hoz.
List<CommunityMediaAttachment> decodeCommunityMediaList(Object? raw) {
  if (raw is! List) return const <CommunityMediaAttachment>[];
  return <CommunityMediaAttachment>[
    for (final item in raw)
      if (item is Map<String, Object?>) decodeCommunityMedia(item),
  ];
}
