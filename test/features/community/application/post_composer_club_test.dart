// A szerkesztő klub-kontextusa (E17-R11).
//
// MÉRT hiány (`docs/ui/apk-functionality-audit-2026-09-06.md` §5.2): a
// klubból indított poszt-írásnak nem volt útja. A bekötés seamje a
// [composerClubIdProvider] — ugyanaz, amit a
// [composerSourceArtifactProvider] már használ a megosztott
// artefaktumhoz. Ez a modul azt méri, hogy a seam a szerkesztő
// állapotán ÉS a persistált piszkozaton át tényleg a kimenő kérésig ér,
// és hogy a globális szerkesztő viselkedése változatlan.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/auth/model/auth_user.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/community/application/controllers/post_composer_controller.dart';
import 'package:strumsight/features/community/data/repositories/post_repository_impl.dart';

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
        'audience': 'followers',
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

/// A szerkesztő csak a bejelentkezett felhasználó azonosítóját olvassa
/// (a per-user piszkozat-kulcshoz); a hitelesítési folyamatokat nem hívja.
class _FakeAuthController extends AuthController {
  _FakeAuthController(this._user);

  final AuthUser _user;

  @override
  Future<AuthUser?> build() async => _user;
}

ProviderContainer _container({
  required InMemoryKeyValueStore store,
  required HttpCommunityPostRepository repository,
  String? clubId,
}) {
  final container = ProviderContainer(
    overrides: [
      communityKeyValueStoreProvider.overrideWithValue(store),
      communityLoggerProvider.overrideWithValue(const NoopAppLogger()),
      communityPostRepositoryProvider.overrideWithValue(repository),
      authControllerProvider.overrideWith(
        () => _FakeAuthController(
          const AuthUser(id: 42, email: 'szerzo@example.com'),
        ),
      ),
    ],
  );
  // A klub-kontextus NAVIGÁCIÓS ARGUMENTUM: a belépési pont a szerkesztő
  // megnyitása ELŐTT állítja be. A teszt ugyanezt a sorrendet követi —
  // az `enter` a controller első olvasása előtt fut.
  if (clubId != null) {
    container.read(composerClubIdProvider.notifier).enter(clubId);
  }
  container.listen<AsyncValue<PostComposerState>>(
    postComposerControllerProvider,
    (_, _) {},
    fireImmediately: false,
  );
  return container;
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

  test('Q1 — a klub-seam a szerkesztő ÁLLAPOTÁBA kerül', () async {
    final container = _container(
      store: InMemoryKeyValueStore(),
      repository: repository,
      clubId: _clubPublicId,
    );
    addTearDown(container.dispose);

    await container.read(postComposerControllerProvider.future);

    final state = container.read(postComposerControllerProvider).value!;
    expect(state.clubId, _clubPublicId);
  });

  test('Q2 — seam nélkül a szerkesztő GLOBÁLIS marad', () async {
    // Kontroll a Q1-hez: az alapértelmezett provider `null`-t ad, tehát a
    // meglévő hívási helyek viselkedése bájtra változatlan.
    final container = _container(
      store: InMemoryKeyValueStore(),
      repository: repository,
    );
    addTearDown(container.dispose);

    await container.read(postComposerControllerProvider.future);

    final state = container.read(postComposerControllerProvider).value!;
    expect(state.clubId, isNull);
  });

  test('Q3 — a klub-cél a persistált PISZKOZATBA is beíródik', () async {
    // A piszkozat túléli az app-újraindítást; ha a klub nem kerülne a
    // bájtokba, a visszatöltött piszkozat némán a globális feedbe menne.
    final store = InMemoryKeyValueStore();
    final container = _container(
      store: store,
      repository: repository,
      clubId: _clubPublicId,
    );
    addTearDown(container.dispose);
    await container.read(postComposerControllerProvider.future);

    await container
        .read(postComposerControllerProvider.notifier)
        .updateBody('klub-poszt szövege');

    final draftStore = container.read(communityDraftStoreProvider);
    expect(draftStore.readDraft()!.clubId, _clubPublicId);
  });

  test('Q4 — a közzététel a KLUB felé megy ki', () async {
    // A teljes lánc: seam → állapot → piszkozat → kimenő sor → kérés.
    final container = _container(
      store: InMemoryKeyValueStore(),
      repository: repository,
      clubId: _clubPublicId,
    );
    addTearDown(container.dispose);
    await container.read(postComposerControllerProvider.future);
    final notifier = container.read(postComposerControllerProvider.notifier);

    await notifier.updateBody('klub-poszt szövege');
    await notifier.submit();

    final state = container.read(postComposerControllerProvider).value!;
    expect(state.status, PostComposerStatus.success);
    final sent = adapter.requests.single.data! as Map;
    expect(sent['club_public_id'], _clubPublicId);
    // A siker után a szerkesztő a KLUBBAN marad: a következő poszt is
    // ide megy, amíg a felhasználó vissza nem lép.
    expect(state.clubId, _clubPublicId);
  });

  test(
    'Q5 — a MEGNYITÁS klubja nyer a visszatöltött piszkozatéval szemben',
    () async {
      // Egy globálisként mentett piszkozatot a klubból megnyitva a poszt
      // a KLUBBA megy. A fordított sorrend azt jelentené, hogy a
      // klub-gomb némán a globális feedbe posztol.
      final store = InMemoryKeyValueStore();
      final globalContainer = _container(store: store, repository: repository);
      await globalContainer.read(postComposerControllerProvider.future);
      await globalContainer
          .read(postComposerControllerProvider.notifier)
          .updateBody('globálisként kezdett szöveg');
      globalContainer.dispose();

      final clubContainer = _container(
        store: store,
        repository: repository,
        clubId: _clubPublicId,
      );
      addTearDown(clubContainer.dispose);
      await clubContainer.read(postComposerControllerProvider.future);

      final state = clubContainer.read(postComposerControllerProvider).value!;
      expect(state.body, 'globálisként kezdett szöveg');
      expect(state.clubId, _clubPublicId);
    },
  );
}
