// A kimenő sor klub-kontextusa (E17-R11).
//
// MÉRT hiány (`docs/ui/apk-functionality-audit-2026-09-06.md` §5.2): a
// klub-poszt írásának nem volt kliens-oldali útja. A bekötés három ponton
// dönthetett rosszul, és mindhármat cella méri:
//
//   1. a klub-cél elveszik a sorban (a poszt a globális feedbe megy);
//   2. a klub-cél elveszik az ÚJRAINDÍTÁSNÁL (a piszkozat-bájtokban);
//   3. a klub-utat nem ismerő repository esetén CSENDES visszaesés a
//      klub nélküli írásra — a felhasználó sikert lát, rossz célponttal.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/application/outbox/community_outbox.dart';
import 'package:strumsight/features/community/data/local/community_draft_store.dart';
import 'package:strumsight/features/community/data/repositories/post_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/share_artifact.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

const String _clubPublicId = '44444444-4444-4444-8444-444444444444';

/// Hálózat NÉLKÜLI adapter: rögzíti a kimenő kéréseket.
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
        'created_at': '2026-09-06T10:00:00Z',
        'resource_version': '2026-09-06T10:00:00Z',
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

/// Naplózó, ami megjegyzi a `warning` hívások hibáit — a 3. cella ezen
/// keresztül méri, hogy a klub-ág tényleg elutasította a kiküldést.
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

CommunityDraft _draft({String? clubId, String body = 'törzs'}) {
  return CommunityDraft.fresh(
    body: body,
    audience: CommunityAudience.public,
    sourceArtifactJson: const <String, Object?>{},
    sharePreview: const SharePreview(),
    now: DateTime.utc(2026, 9, 6, 10),
    clubId: clubId,
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

  test('O1 — a klub-cél a KIMENŐ KÉRÉSIG eljut', () async {
    final outbox = LocalCommunityOutbox(
      repository: repository,
      store: InMemoryKeyValueStore(),
      logger: const NoopAppLogger(),
    );

    await outbox.enqueue(draft: _draft(clubId: _clubPublicId));
    final report = await outbox.drain();

    expect(report.retrying, isEmpty);
    expect(report.acknowledged, hasLength(1));
    final sent = adapter.requests.single.data! as Map;
    expect(sent['club_public_id'], _clubPublicId);
  });

  test('O2 — klub nélkül a törzs alakja VÁLTOZATLAN', () async {
    // Kontroll az O1-hez: a klub-ág nem szivároghat át a globális
    // posztokra.
    final outbox = LocalCommunityOutbox(
      repository: repository,
      store: InMemoryKeyValueStore(),
      logger: const NoopAppLogger(),
    );

    await outbox.enqueue(draft: _draft());
    await outbox.drain();

    final sent = adapter.requests.single.data! as Map;
    expect(sent.containsKey('club_public_id'), isFalse);
  });

  test('O3 — a klub-cél TÚLÉLI az app újraindítását', () async {
    // A rekord a tárban él; egy friss kimenő sor ugyanabból a tárból
    // olvassa vissza. Ha a `clubId` nem kerülne a bájtokba, a
    // visszatöltött poszt némán a globális feedbe menne.
    final store = InMemoryKeyValueStore();
    final first = LocalCommunityOutbox(
      repository: repository,
      store: store,
      logger: const NoopAppLogger(),
    );
    await first.enqueue(draft: _draft(clubId: _clubPublicId));

    final reopened = LocalCommunityOutbox(
      repository: repository,
      store: store,
      logger: const NoopAppLogger(),
    );
    final pending = reopened.pendingPosts();

    expect(pending, hasLength(1));
    expect(pending.single.clubId, _clubPublicId);

    await reopened.drain();
    final sent = adapter.requests.single.data! as Map;
    expect(sent['club_public_id'], _clubPublicId);
  });

  test('O4 — klub-utat nem ismerő repository: NINCS néma visszaesés', () async {
    // A fiók nélküli (`Disabled*`) repository a szerződést megvalósítja,
    // de a klub-utat nem ismeri. A helyes válasz a hiba + megtartott
    // rekord; a HELYTELEN az volna, ha a sor a klub nélküli `createPost`-ra
    // esne vissza, mert akkor a felhasználó sikert látna, rossz célponttal.
    final logger = _RecordingLogger();
    final outbox = LocalCommunityOutbox(
      repository: const DisabledCommunityPostRepository(),
      store: InMemoryKeyValueStore(),
      logger: logger,
    );

    final enqueued = await outbox.enqueue(draft: _draft(clubId: _clubPublicId));
    final report = await outbox.drain();

    expect(report.acknowledged, isEmpty);
    expect(report.retrying, contains(enqueued.record.idempotencyKey));
    expect(outbox.pendingPosts(), hasLength(1));
    // A hiba a KLUB-ágé (StateError), nem a `createPost` konfigurációs
    // hibája — vagyis a sor meg sem kísérelte a klub nélküli utat. A
    // szűrés szándékos: az üres tár betöltése is naplóz egy (hiba
    // nélküli) figyelmeztetést, ami nem tartozik ehhez az állításhoz.
    expect(logger.warnings.whereType<StateError>(), hasLength(1));
    expect(logger.warnings.whereType<ConfigurationFailure>(), isEmpty);
  });
}
