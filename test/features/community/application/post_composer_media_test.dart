/// Javító sáv R27 — a szerkesztő média-csatolási folyamata.
///
/// A teljes út egy hamis képválasztóval és egy hálózat nélküli, RÖGZÍTŐ
/// Dio-adapterrel, a `communityMediaEnabled` zászlóval BEKAPCSOLVA (a
/// szállított buildekben a zászló ki van kapcsolva — a MI5 cella a
/// `composer_audience_test.dart`-ban méri, hogy akkor a gomb nincs is
/// ott).
///
/// * A1 — a koppintás a választót hívja, a választott bájtokat pedig
///   AZONNAL feltölti; a csatolmány megjelenik a szerkesztőben.
/// * A2 — a `mediaIds` a PISZKOZATBA kerül, tehát túléli az
///   újraindítást. Enélkül a felhasználó a visszatöltött szerkesztőből
///   kép nélkül posztolna, a szerveren pedig maradna egy laza feltöltés,
///   amiről nem tud.
/// * A3 — az ELUTASÍTOTT feltöltés NEM kerül a `mediaIds` listába (a
///   közzététel különben az egész poszttal együtt bukna), de LÁTSZIK, az
///   okával együtt — különben a felhasználó annyit lát, hogy „nem
///   történt semmi".
/// * A4 — a megszakított választás nem hagy nyomot.
/// * A5 — a feltöltési hiba a MÉDIA hibája, nem a közzétételé: a
///   szerkesztő `editing` marad, a szöveg érintetlen.
/// * A6 — az eltávolítás leveszi a csempét ÉS kiadja a `DELETE`-et.
/// * A7 — a négyes korlát elérésekor a gomb tiltott, nem eltűnt.
/// * A8 — a golden-semlegesség: csatolmány, hiba és korlát NÉLKÜL a
///   képernyőn egyetlen új widget sincs (a `e13_r33` képek a zászlóval
///   BEKAPCSOLVA készültek).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/design_system/public.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/core/storage/key_value_store.dart';
import 'package:strumsight/features/auth/model/auth_user.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/community/application/controllers/post_composer_controller.dart';
import 'package:strumsight/features/community/data/api/community_media_picker.dart';
import 'package:strumsight/features/community/data/local/community_draft_store.dart';
import 'package:strumsight/features/community/data/repositories/post_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_media.dart';
import 'package:strumsight/features/community/domain/entities/share_artifact.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/presentation/screens/post_composer_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

const String _mediaPublicId = '55555555-5555-4555-8555-555555555555';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

/// Hamis képválasztó: nem nyit platform-párbeszédet, és megszámolja,
/// hányszor hívták.
class _FakePicker implements CommunityMediaPicker {
  _FakePicker({this.result});

  PickedCommunityMedia? result;
  int calls = 0;

  @override
  Future<PickedCommunityMedia?> pickImage() async {
    calls++;
    return result;
  }
}

/// Hálózat NÉLKÜLI adapter. A `POST /community/media` egy előre megadott
/// leírót ad; a `DELETE` üres 200-at; minden más 201-es posztot.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({Map<String, Object?>? mediaBody, this.mediaStatus = 201})
    : mediaBodies = <Map<String, Object?>>[mediaBody ?? _mediaJson()];

  /// Egymást követő média-válaszok. Egy elem esetén minden feltöltés
  /// ugyanazt kapja; több elem esetén sorban fogynak (a négyes korlát
  /// cellája így kap négy KÜLÖNBÖZŐ azonosítót egyetlen harness-en
  /// belül, harness-újraépítés nélkül).
  _RecordingAdapter.sequence(this.mediaBodies, {this.mediaStatus = 201});

  final List<Map<String, Object?>> mediaBodies;
  final int mediaStatus;

  int _mediaCalls = 0;

  final List<RequestOptions> requests = <RequestOptions>[];

  Iterable<RequestOptions> get deletes =>
      requests.where((r) => r.method == 'DELETE');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    // A törzs elolvasása kötelező: a többrészes stream lezáratlanul
    // hagyva a Dio-t függőben tartaná.
    if (requestStream != null) {
      await requestStream.drain<void>();
    }
    if (options.method == 'DELETE') {
      return ResponseBody.fromString(
        jsonEncode(<String, Object?>{'status': 'deleted'}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.path == '/community/media') {
      final body = mediaBodies[_mediaCalls.clamp(0, mediaBodies.length - 1)];
      _mediaCalls++;
      return ResponseBody.fromString(
        jsonEncode(body),
        mediaStatus,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
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

Map<String, Object?> _mediaJson({
  String publicId = _mediaPublicId,
  String state = 'ready',
  Object? rejectionCode,
}) {
  return <String, Object?>{
    'public_id': publicId,
    'kind': 'image',
    'state': state,
    'rejection_code': rejectionCode,
    'content_type': 'image/jpeg',
    'size_bytes': 1234,
    'width': 640,
    'height': 480,
    'duration_ms': null,
    'created_at': '2026-09-08T10:00:00Z',
  };
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(this._user);
  final AuthUser _user;
  @override
  Future<AuthUser?> build() async => _user;
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

const AppConfig _mediaEnabledConfig = AppConfig(
  environment: AppEnvironment.development,
  apiBaseUrl: AppConfig.devApiBaseUrl,
  flags: FeatureFlags(
    // `accountEnabled: false` a szándék: így az `accountApiClientProvider`
    // `null`, tehát a KÉP-BÁJTOKAT hozó provider azonnal hibára fut, és a
    // csempe nem pörget végtelen spinnert a teszt alatt. A feltöltés
    // maga NEM ezen az úton megy — a szerkesztő a felülírt
    // `communityPostRepositoryProvider`-t olvassa.
    accountEnabled: false,
    diagnosticsEnabled: false,
    labModeAvailable: false,
    communityMediaEnabled: true,
  ),
  diagnosticsToken: AppConfig.devDiagnosticsToken,
  buildMode: 'test',
  appVersion: 'test',
);

Widget _harness({
  required _FakePicker picker,
  required _RecordingAdapter adapter,
  required KeyValueStore store,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..httpClientAdapter = adapter;
  return ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(_mediaEnabledConfig),
      communityKeyValueStoreProvider.overrideWithValue(store),
      communityLoggerProvider.overrideWithValue(const NoopAppLogger()),
      communityMediaPickerProvider.overrideWithValue(picker),
      communityPostRepositoryProvider.overrideWithValue(
        HttpCommunityPostRepository(ApiClient(dio)),
      ),
      composerSourceArtifactProvider.overrideWithValue(
        const <String, Object?>{},
      ),
      authControllerProvider.overrideWith(
        () => _FakeAuthController(
          const AuthUser(id: 7, email: 'composer@strumsight.app'),
        ),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const PostComposerScreen(),
    ),
  );
}

AppLocalizations _en() => lookupAppLocalizations(const Locale('en'));

PostComposerState _state(WidgetTester tester) {
  final element = tester.element(find.byType(PostComposerScreen));
  return ProviderScope.containerOf(
    element,
  ).read(postComposerControllerProvider).value!;
}

PostComposerController _controller(WidgetTester tester) {
  final element = tester.element(find.byType(PostComposerScreen));
  return ProviderScope.containerOf(
    element,
  ).read(postComposerControllerProvider.notifier);
}

/// Pumpol néhány képkockát pumpAndSettle NÉLKÜL.
///
/// A kész kép csempéje a bájtok megérkezéséig `CircularProgressIndicator`-t
/// mutat, ami folyamatosan képkockát kér — a `pumpAndSettle` ezen
/// időtúllépéssel elhasalna. A cellák a KONTROLLER állapotát és a csempék
/// kulcsait mérik, nem a dekódolt képpontokat, tehát néhány kézi pump
/// elég.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

PickedCommunityMedia _picked() => PickedCommunityMedia(
  displayName: 'IMG_20260908_gps.jpg',
  bytes: <int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A1 — a csatolás valódi feltöltés', () {
    testWidgets('a koppintás választ, feltölt, és a csempe megjelenik', (
      tester,
    ) async {
      final picker = _FakePicker(result: _picked());
      final adapter = _RecordingAdapter();
      await tester.pumpWidget(
        _harness(
          picker: picker,
          adapter: adapter,
          store: InMemoryKeyValueStore(),
        ),
      );
      await _settle(tester);

      await tester.tap(find.byKey(const Key('composer-attach-media')));
      await _settle(tester);

      expect(picker.calls, 1);
      // Egy VALÓDI multipart kérés ment ki a média-végpontra.
      final upload = adapter.requests.singleWhere(
        (r) => r.path == '/community/media',
      );
      expect(upload.method, 'POST');
      expect(_state(tester).mediaIds, <String>[_mediaPublicId]);
      expect(
        find.byKey(const Key('composer-media-$_mediaPublicId')),
        findsOneWidget,
      );
      expect(find.text(_en().communityComposerMediaSectionLabel), findsWidgets);
    });

    testWidgets('a dupla koppintás nem indít két feltöltést', (tester) async {
      final picker = _FakePicker(result: _picked());
      final adapter = _RecordingAdapter();
      await tester.pumpWidget(
        _harness(
          picker: picker,
          adapter: adapter,
          store: InMemoryKeyValueStore(),
        ),
      );
      await _settle(tester);

      final button = find.byKey(const Key('composer-attach-media'));
      await tester.tap(button);
      // Egyetlen képkocka múlva a gomb már tiltott (`isAttachingMedia`),
      // tehát a második koppintás nem indít újabb választást.
      await tester.pump();
      await tester.tap(button, warnIfMissed: false);
      await _settle(tester);

      expect(picker.calls, 1);
      expect(_state(tester).mediaIds, hasLength(1));
    });
  });

  group('A2 — a csatolmány túléli az újraindítást', () {
    testWidgets('a mediaIds a PISZKOZATBA kerül, és visszatöltődik', (
      tester,
    ) async {
      final store = InMemoryKeyValueStore();
      final picker = _FakePicker(result: _picked());

      await tester.pumpWidget(
        _harness(picker: picker, adapter: _RecordingAdapter(), store: store),
      );
      await _settle(tester);
      await tester.tap(find.byKey(const Key('composer-attach-media')));
      await _settle(tester);
      expect(_state(tester).mediaIds, <String>[_mediaPublicId]);

      // „Újraindítás": friss widget-fa, UGYANAZ a tár. A fát ELŐBB le
      // kell szerelni: egy azonos alakú `ProviderScope` újrapumpálása
      // csak a felülírásokat frissíti (`didUpdateWidget`), a KONTÉNERT
      // nem dobja el — a szerkesztő állapota a leírókkal együtt
      // életben maradna, és a teszt nem a piszkozatot mérné, hanem a
      // saját memóriáját.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        _harness(
          picker: _FakePicker(),
          adapter: _RecordingAdapter(),
          store: store,
        ),
      );
      await _settle(tester);

      expect(_state(tester).mediaIds, <String>[_mediaPublicId]);
      // A leírók NEM perzisztálnak (nincs „leíró egy azonosítóhoz"
      // végpont), tehát ez tényleg a tárból jött vissza.
      expect(_state(tester).mediaDescriptors, isEmpty);
      // A leírót NEM találjuk ki: a visszatöltött csatolmány semleges
      // csempét kap, nem hamis „kész" arcot.
      expect(
        find.byKey(const Key('composer-media-restored-$_mediaPublicId')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('composer-media-$_mediaPublicId')),
        findsNothing,
      );
    });

    test('a mediaIds a piszkozat BÁJTJAIBAN is ott van', () {
      // A fenti cella a tárból hidratál; ez a kódolást magát méri, hogy
      // egy séma-változás ne csak a lassabb, widget-szintű cellán
      // bukjon ki. A körút szándékosan valódi JSON: a tárba is bájtok
      // kerülnek, nem élő objektumok.
      final draft = CommunityDraft.fresh(
        body: '',
        audience: CommunityAudience.followers,
        sourceArtifactJson: const <String, Object?>{},
        sharePreview: SharePreview.conservative,
        now: DateTime.utc(2026, 9, 8, 10),
        mediaIds: const <String>[_mediaPublicId],
      );

      final decoded = jsonDecode(jsonEncode(draft.toJson()));
      final restored = CommunityDraft.fromJson(decoded as Map<String, Object?>);

      expect(restored.mediaIds, <String>[_mediaPublicId]);
    });
  });

  group('A3 — az elutasított feltöltés látszik, de nem csatolódik', () {
    testWidgets('rejected ⇒ nincs a mediaIds-ben, de van csempéje', (
      tester,
    ) async {
      final picker = _FakePicker(result: _picked());
      final adapter = _RecordingAdapter(
        mediaBody: _mediaJson(
          state: 'rejected',
          rejectionCode: 'scriptable_media_rejected',
        ),
      );
      await tester.pumpWidget(
        _harness(
          picker: picker,
          adapter: adapter,
          store: InMemoryKeyValueStore(),
        ),
      );
      await _settle(tester);

      await tester.tap(find.byKey(const Key('composer-attach-media')));
      await _settle(tester);

      // A közzététel nem viheti magával — a szerver 400-zal bukná az
      // egész posztot.
      expect(_state(tester).mediaIds, isEmpty);
      // De a felhasználó LÁTJA, és megtudja, miért.
      expect(
        _state(tester).mediaDescriptors[_mediaPublicId]?.state,
        CommunityMediaState.rejected,
      );
      expect(
        find.byKey(const Key('composer-media-$_mediaPublicId')),
        findsOneWidget,
      );
      expect(
        find.text(_en().communityMediaRejectedUnsupported),
        findsOneWidget,
      );
    });
  });

  group('A4/A5 — megszakítás és hiba', () {
    testWidgets('a megszakított választás nem hagy nyomot', (tester) async {
      final picker = _FakePicker();
      final adapter = _RecordingAdapter();
      await tester.pumpWidget(
        _harness(
          picker: picker,
          adapter: adapter,
          store: InMemoryKeyValueStore(),
        ),
      );
      await _settle(tester);

      await tester.tap(find.byKey(const Key('composer-attach-media')));
      await _settle(tester);

      expect(picker.calls, 1);
      expect(_state(tester).mediaIds, isEmpty);
      expect(_state(tester).mediaDescriptors, isEmpty);
      expect(_state(tester).isAttachingMedia, isFalse);
      expect(_state(tester).mediaError, isNull);
      expect(
        adapter.requests.where((r) => r.path == '/community/media'),
        isEmpty,
      );
    });

    testWidgets('a feltöltési hiba a MÉDIA hibája, nem a közzétételé', (
      tester,
    ) async {
      final picker = _FakePicker(result: _picked());
      // 413: a kaput túllépő feltöltés — valóban kivételes kimenet.
      final adapter = _RecordingAdapter(
        mediaBody: const <String, Object?>{},
        mediaStatus: 413,
      );
      await tester.pumpWidget(
        _harness(
          picker: picker,
          adapter: adapter,
          store: InMemoryKeyValueStore(),
        ),
      );
      await _settle(tester);

      await tester.enterText(find.byType(TextField).first, 'megírt szöveg');
      await _settle(tester);
      await tester.tap(find.byKey(const Key('composer-attach-media')));
      await _settle(tester);

      final state = _state(tester);
      expect(state.mediaError, isNotNull);
      expect(state.mediaIds, isEmpty);
      // A KÖZZÉTÉTELI állapot érintetlen: a poszt nem bukott el, csak a
      // kép nem ment fel.
      expect(state.status, PostComposerStatus.editing);
      expect(state.body, 'megírt szöveg');
      expect(find.byKey(const Key('composer-media-error')), findsOneWidget);
      expect(
        find.text(_en().communityComposerMediaUploadFailed),
        findsOneWidget,
      );
    });
  });

  group('A6 — eltávolítás', () {
    testWidgets('a csempe eltűnik ÉS kimegy a DELETE', (tester) async {
      final picker = _FakePicker(result: _picked());
      final adapter = _RecordingAdapter();
      await tester.pumpWidget(
        _harness(
          picker: picker,
          adapter: adapter,
          store: InMemoryKeyValueStore(),
        ),
      );
      await _settle(tester);
      await tester.tap(find.byKey(const Key('composer-attach-media')));
      await _settle(tester);
      expect(_state(tester).mediaIds, hasLength(1));

      // NEM `await`: a widget-teszt FakeAsync-zónájában a Dio-kérés csak a
      // pumpolt időben halad, a közvetlen `await` sosem térne vissza (a run
      // 561 tízperces időtúllépése). A csatolás útja is így, pumpolva fut.
      unawaited(_controller(tester).removeMedia(_mediaPublicId));
      await _settle(tester);

      expect(_state(tester).mediaIds, isEmpty);
      expect(
        find.byKey(const Key('composer-media-$_mediaPublicId')),
        findsNothing,
      );
      expect(
        adapter.deletes.map((r) => r.path),
        contains('/community/media/$_mediaPublicId'),
      );
    });
  });

  group('A7 — a négyes korlát', () {
    testWidgets('a korlát elérésekor a gomb TILTOTT, nem eltűnt', (
      tester,
    ) async {
      final picker = _FakePicker(result: _picked());
      final adapter = _RecordingAdapter.sequence(<Map<String, Object?>>[
        for (var index = 0; index < kCommunityMaxMediaPerPost; index++)
          _mediaJson(publicId: '5555555$index-5555-4555-8555-555555555555'),
      ]);
      await tester.pumpWidget(
        _harness(
          picker: picker,
          adapter: adapter,
          store: InMemoryKeyValueStore(),
        ),
      );
      await _settle(tester);

      final button = find.byKey(const Key('composer-attach-media'));
      for (var index = 0; index < kCommunityMaxMediaPerPost; index++) {
        await tester.ensureVisible(button);
        await tester.tap(button);
        await _settle(tester);
      }

      expect(_state(tester).mediaIds, hasLength(kCommunityMaxMediaPerPost));
      expect(picker.calls, kCommunityMaxMediaPerPost);
      await tester.ensureVisible(button);
      expect(tester.widget<SsButton>(button).onPressed, isNull);
      expect(find.byKey(const Key('composer-media-limit')), findsOneWidget);
    });
  });

  group('A8 — golden-semlegesség', () {
    testWidgets('csatolmány nélkül egyetlen új widget sincs a képernyőn', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          picker: _FakePicker(),
          adapter: _RecordingAdapter(),
          store: InMemoryKeyValueStore(),
        ),
      );
      await _settle(tester);

      // A gomb ott van (a `e13_r33` képek ezzel készültek)...
      expect(find.byKey(const Key('composer-attach-media')), findsOneWidget);
      // ...de a kör HÁROM új widgete közül egy sem.
      expect(find.byKey(const Key('composer-media-error')), findsNothing);
      expect(find.byKey(const Key('composer-media-limit')), findsNothing);
      expect(find.text(_en().communityComposerMediaSectionLabel), findsNothing);
    });
  });
}
