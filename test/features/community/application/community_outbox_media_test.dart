/// Javító sáv R27 — a kimenő sor csatolmány-kontextusa.
///
/// A klub-céllal (E17-R11) azonos hibaosztály, egy szinttel arrébb: a
/// csatolmány a FELTÖLTÉSKOR keletkezik, a poszthoz KÖTÉS viszont csak a
/// közzétételkor. A kettő között bármi történhet — a felhasználó
/// offline, kilép, kill-eli az appot —, és három ponton lehet rosszul
/// dönteni:
///
///   1. a csatolmány-lista elveszik a sorban (a poszt kép nélkül megy ki);
///   2. a lista elveszik az ÚJRAINDÍTÁSNÁL (a rekord bájtjaiban);
///   3. a média-utat nem ismerő repository esetén CSENDES visszaesés a
///      csatolmány nélküli írásra — a felhasználó sikert lát, üres
///      poszttal.
///
/// Mindhármat egy-egy cella méri, plusz a kontroll: csatolmány nélkül a
/// kimenő törzs alakja bájtra változatlan.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/application/outbox/community_outbox.dart';
import 'package:strumsight/features/community/data/local/community_draft_store.dart';
import 'package:strumsight/features/community/data/repositories/post_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/share_artifact.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

const String _mediaPublicId = '55555555-5555-4555-8555-555555555555';

class _RecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(<String, Object?>{
        'public_id': '11111111-1111-4111-8111-111111111111',
        'author_public_id': '22222222-2222-4222-8222-222222222222',
        'audience': 'public',
        'body': 'törzs',
        'moderation_state': 'visible',
        'created_at': '2026-09-08T10:00:00Z',
        'resource_version': '2026-09-08T10:00:00Z',
      }),
      201,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Naplózó, ami megjegyzi a `warning`/`error` hívások hibáit.
class _RecordingLogger implements AppLogger {
  final List<Object?> warnings = <Object?>[];

  @override
  void debug(String event, {Map<String, Object?> fields = const {}}) {}

  @override
  void info(String event, {Map<String, Object?> fields = const {}}) {}

  @override
  void warning(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    warnings.add(error);
  }

  @override
  void error(
    String event, {
    required Object error,
    required StackTrace stackTrace,
    Map<String, Object?> fields = const {},
  }) {
    warnings.add(error);
  }
}

CommunityDraft _draft({List<String> mediaIds = const <String>[]}) {
  return CommunityDraft.fresh(
    body: 'törzs',
    audience: CommunityAudience.public,
    sourceArtifactJson: const <String, Object?>{},
    sharePreview: const SharePreview(),
    now: DateTime.utc(2026, 9, 8, 10),
    mediaIds: mediaIds,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingAdapter adapter;
  late HttpCommunityPostRepository repository;

  setUp(() {
    adapter = _RecordingAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    repository = HttpCommunityPostRepository(ApiClient(dio));
  });

  test('M1 — a csatolmány-lista a KIMENŐ KÉRÉSIG eljut', () async {
    final outbox = LocalCommunityOutbox(
      repository: repository,
      store: InMemoryKeyValueStore(),
      logger: const NoopAppLogger(),
    );

    await outbox.enqueue(draft: _draft(mediaIds: <String>[_mediaPublicId]));
    final report = await outbox.drain();

    expect(report.retrying, isEmpty);
    expect(report.acknowledged, hasLength(1));
    final sent = adapter.requests.single.data! as Map;
    expect(sent['media_ids'], <String>[_mediaPublicId]);
  });

  test('M2 — csatolmány nélkül a törzs alakja VÁLTOZATLAN', () async {
    // Kontroll az M1-hez: a média-ág nem szivároghat át a szöveges
    // posztokra.
    final outbox = LocalCommunityOutbox(
      repository: repository,
      store: InMemoryKeyValueStore(),
      logger: const NoopAppLogger(),
    );

    await outbox.enqueue(draft: _draft());
    await outbox.drain();

    final sent = adapter.requests.single.data! as Map;
    expect(sent.containsKey('media_ids'), isFalse);
  });

  test('M3 — a csatolmány-lista TÚLÉLI az app újraindítását', () async {
    // A rekord a tárban él; egy friss kimenő sor ugyanabból a tárból
    // olvassa vissza. Ha a `mediaIds` nem kerülne a bájtokba, a
    // visszatöltött poszt némán kép NÉLKÜL menne ki, a felhasználó
    // pedig sikert látna.
    final store = InMemoryKeyValueStore();
    final first = LocalCommunityOutbox(
      repository: repository,
      store: store,
      logger: const NoopAppLogger(),
    );
    await first.enqueue(draft: _draft(mediaIds: <String>[_mediaPublicId]));

    final reopened = LocalCommunityOutbox(
      repository: repository,
      store: store,
      logger: const NoopAppLogger(),
    );
    final pending = reopened.pendingPosts();

    expect(pending, hasLength(1));
    expect(pending.single.mediaIds, <String>[_mediaPublicId]);

    await reopened.drain();
    final sent = adapter.requests.single.data! as Map;
    expect(sent['media_ids'], <String>[_mediaPublicId]);
  });

  test('M4 — média-út nélküli repository: NINCS néma visszaesés', () async {
    // A fiók nélküli (`Disabled*`) repository a szerződést megvalósítja,
    // de a `media_ids` opcionális paramétert nem ismeri. A helyes válasz
    // a hiba + megtartott rekord; a HELYTELEN az volna, ha a sor a
    // csatolmány nélküli `createPost`-ra esne vissza, mert akkor a
    // felhasználó sikert látna egy üres poszttal.
    final logger = _RecordingLogger();
    final outbox = LocalCommunityOutbox(
      repository: const DisabledCommunityPostRepository(),
      store: InMemoryKeyValueStore(),
      logger: logger,
    );

    final enqueued = await outbox.enqueue(
      draft: _draft(mediaIds: <String>[_mediaPublicId]),
    );
    final report = await outbox.drain();

    expect(report.acknowledged, isEmpty);
    expect(report.retrying, contains(enqueued.record.idempotencyKey));
    expect(outbox.pendingPosts(), hasLength(1));
    // A hiba a MÉDIA-ágé (StateError), nem a `createPost` konfigurációs
    // hibája — vagyis a sor meg sem kísérelte a csatolmány nélküli utat.
    expect(logger.warnings.whereType<StateError>(), hasLength(1));
  });

  test('M5 — a piszkozat csatolmánnyal NEM üres', () async {
    // Egy csak képet hordozó piszkozat perzisztálódik: ha üresnek
    // számítana, a szerkesztő kiürítené, és a szerveren maradna egy laza
    // feltöltés, amiről a felhasználó nem tud.
    expect(_draft(mediaIds: <String>[_mediaPublicId]).isEmpty, isFalse);
    final onlyMedia = CommunityDraft.fresh(
      body: '',
      audience: CommunityAudience.public,
      sourceArtifactJson: const <String, Object?>{},
      sharePreview: const SharePreview(),
      now: DateTime.utc(2026, 9, 8, 10),
      mediaIds: <String>[_mediaPublicId],
    );
    expect(onlyMedia.isEmpty, isFalse);
    // Kontroll: szöveg és csatolmány nélkül továbbra is üres.
    final blank = CommunityDraft.fresh(
      body: '',
      audience: CommunityAudience.public,
      sourceArtifactJson: const <String, Object?>{},
      sharePreview: const SharePreview(),
      now: DateTime.utc(2026, 9, 8, 10),
    );
    expect(blank.isEmpty, isTrue);
  });

  test('M6 — a piszkozat csatolmány-listája körbejár a JSON-on', () async {
    final draft = _draft(mediaIds: <String>[_mediaPublicId]);
    final restored = CommunityDraft.fromJson(draft.toJson());
    expect(restored.mediaIds, <String>[_mediaPublicId]);

    // Az ÜRES lista nem kerül a dokumentumba, tehát a média előtti
    // bájtok séma-verzió emelés nélkül olvashatók maradnak.
    expect(_draft().toJson().containsKey('mediaIds'), isFalse);
    expect(CommunityDraft.fromJson(_draft().toJson()).mediaIds, isEmpty);
  });
}
