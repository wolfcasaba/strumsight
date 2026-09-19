import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../foundation/app_failure.dart';
import '../foundation/app_result.dart';
import 'auth_interceptor.dart';
import 'network_failure_mapper.dart';

typedef JsonObjectDecoder<T> = T Function(Map<String, Object?> json);

/// Typed network boundary used by features instead of talking to Dio directly.
///
/// It validates JSON object responses, maps every transport exception to an
/// [AppFailure], and never automatically repeats a request.
final class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  /// GET egy JSON-objektumot adó végpontról.
  ///
  /// A [queryParameters] 2026-09-05-ig HIÁNYZOTT ebből a primitívből, és ez
  /// MÉRT hibát okozott: a `challenge_repository_impl` és a
  /// `relationship_repository_impl` felépítette a `{'limit': …, 'cursor': …}`
  /// térképet, majd NEM adta át sehova — a lapozás minden community-listán
  /// némán az első alapértelmezett oldalt kérte újra. A paraméter opcionális
  /// és `null`-alapértelmezett, tehát minden meglévő hívó viselkedése
  /// bájtra változatlan.
  ///
  /// [readsErrorDetail] opts THIS request into keeping the error-status body
  /// (R19). `DioFactory` sets `receiveDataWhenStatusError: false` globally
  /// because an error body is never needed to classify a failure and may
  /// carry credentials — but one caller does need two-value information the
  /// status alone cannot carry: `GET /community/profiles/me` answers 404
  /// `profile_missing` when the router IS mounted and the caller merely has
  /// no row, and the framework's bare 404 when `/community/**` is not
  /// mounted at all. Opting in also switches the response to
  /// [ResponseType.plain], so Dio's transformer never calls `jsonDecode`:
  /// a malformed body can therefore never become a transform exception that
  /// replaces the response — and with it the HTTP status — on the way out.
  /// A 401 on an opted-in request stays exactly as authoritative as on every
  /// other one, and [mapNetworkFailure] keeps classifying by status alone.
  /// The JSON decoding of a successful body moves here instead, into the
  /// same `try` that already turns a malformed payload into
  /// [FailureCode.networkBadResponse].
  Future<AppResult<T>> getJson<T>(
    String path, {
    required JsonObjectDecoder<T> decode,
    Map<String, Object?>? queryParameters,
    bool requiresAuthentication = true,
    bool readsErrorDetail = false,
    String unauthorizedCode = FailureCode.authSessionExpired,
    String conflictCode = FailureCode.validationInvalidInput,
  }) => _requestJson(
    method: 'GET',
    path: path,
    decode: decode,
    queryParameters: queryParameters,
    requiresAuthentication: requiresAuthentication,
    readsErrorDetail: readsErrorDetail,
    unauthorizedCode: unauthorizedCode,
    conflictCode: conflictCode,
  );

  Future<AppResult<T>> postJson<T>(
    String path, {
    required Map<String, Object?> data,
    required JsonObjectDecoder<T> decode,
    bool requiresAuthentication = true,
    String unauthorizedCode = FailureCode.authSessionExpired,
    String conflictCode = FailureCode.validationInvalidInput,
  }) => _requestJson(
    method: 'POST',
    path: path,
    data: data,
    decode: decode,
    requiresAuthentication: requiresAuthentication,
    unauthorizedCode: unauthorizedCode,
    conflictCode: conflictCode,
  );

  Future<AppResult<T>> putJson<T>(
    String path, {
    required Map<String, Object?> data,
    required JsonObjectDecoder<T> decode,
    bool requiresAuthentication = true,
    String unauthorizedCode = FailureCode.authSessionExpired,
    String conflictCode = FailureCode.validationInvalidInput,
  }) => _requestJson(
    method: 'PUT',
    path: path,
    data: data,
    decode: decode,
    requiresAuthentication: requiresAuthentication,
    unauthorizedCode: unauthorizedCode,
    conflictCode: conflictCode,
  );

  /// PATCH egy JSON-objektumot adó végpontra — a [putJson] pontos párja.
  ///
  /// A primitív 2026-09-06-ig HIÁNYZOTT, és ez MÉRT hibát okozott: a
  /// szerver HÁROM szerkesztő végpontja `PATCH` igét vár
  /// (`PATCH /community/posts/{id}`, `PATCH /community/comments/{id}`,
  /// `PATCH /community/clubs/{id}`), a kliens viszont csak
  /// `getJson` / `postJson` / `putJson` / `post` / `delete` közül
  /// választhatott. A három repository-metódus ezért dokumentált
  /// `UnimplementedError`-t dobott, és a komment szerkesztése
  /// (`comment_controller.dart` `editComment`) ÉLESEN ebbe futott bele.
  ///
  /// A `PUT` NEM helyettesíti: a FastAPI útvonalak igére illesztenek, egy
  /// `PUT /community/posts/{id}` 405-öt adna. A hibaleképezés ugyanazon a
  /// privát [_requestJson]-on megy át, mint a többi primitívé — a 401 / 403
  /// / 409 / 422 / 5xx osztályozás bájtra azonos.
  Future<AppResult<T>> patchJson<T>(
    String path, {
    required Map<String, Object?> data,
    required JsonObjectDecoder<T> decode,
    bool requiresAuthentication = true,
    String unauthorizedCode = FailureCode.authSessionExpired,
    String conflictCode = FailureCode.validationInvalidInput,
  }) => _requestJson(
    method: 'PATCH',
    path: path,
    data: data,
    decode: decode,
    requiresAuthentication: requiresAuthentication,
    unauthorizedCode: unauthorizedCode,
    conflictCode: conflictCode,
  );

  /// POST egy MULTIPART törzset, JSON-objektumot adó végpontra.
  ///
  /// A `POST /community/media` (javító sáv R27) az egyetlen felület a
  /// fában, amely nem JSON-t küld: a bájtok egy `multipart/form-data`
  /// részben utaznak. A primitív ITT él, és nem a feature adat-rétegében,
  /// két mért okból:
  ///
  /// * a `FormData` felépítése így nem szivárog ki a repository-kba (a
  ///   hívó bájtokat és egy fájlnevet ad, Dio-típust nem), és
  /// * a kérés ugyanazon a `_requestJson`-on megy át, mint a másik öt
  ///   primitív, tehát a JWT-t hozzáadó interceptor, a 401/403/409/422
  ///   osztályozás és a rossz-válasz ág bájtra azonos. Egy külön,
  ///   injektált `Dio`-t fielded feltöltő osztály mindhármat újra
  ///   megírná — és az `api_client.dart` `_dio.` hívási helyeinek
  ///   pinelt száma (`tool/check_data_inventory.dart`) is azért marad
  ///   NÉGY, mert ez a metódus nem nyit új kimenő utat.
  ///
  /// A [filename] SZÁNDÉKOSAN nem a felhasználó fájlneve: a szerver
  /// eldobja (a tárolt út a tartalom lenyomatából áll össze), a naplóba
  /// viszont bekerülhetne, ezért a hívó egy semleges nevet ad.
  ///
  /// A rész `Content-Type`-ját SZÁNDÉKOSAN nem állítjuk be. A szerver a
  /// fájl fajtáját kizárólag a magic-bytekből dönti el
  /// (`backend/app/community/media/sniff.py`) — a hívó által írt fejléc
  /// nem paramétere a döntésnek —, tehát egy itt kitalált érték
  /// legfeljebb azt a látszatot keltené, hogy számít valamit.
  Future<AppResult<T>> postMultipartJson<T>(
    String path, {
    required List<int> bytes,
    required JsonObjectDecoder<T> decode,
    String field = 'file',
    String filename = 'upload.bin',
    bool requiresAuthentication = true,
    String unauthorizedCode = FailureCode.authSessionExpired,
    String conflictCode = FailureCode.validationInvalidInput,
  }) {
    final form = FormData.fromMap(<String, Object?>{
      field: MultipartFile.fromBytes(bytes, filename: filename),
    });
    return _requestJson(
      method: 'POST',
      path: path,
      data: form,
      decode: decode,
      requiresAuthentication: requiresAuthentication,
      unauthorizedCode: unauthorizedCode,
      conflictCode: conflictCode,
    );
  }

  /// GET egy BÁJT-törzset adó végpontról (javító sáv R27).
  ///
  /// Egyetlen felület használja: a `GET /community/media/{public_id}`,
  /// amely a csatolt kép újrakódolt bájtjait adja vissza. A kérés
  /// hitelesített és közönség-ellenőrzött, tehát NEM cserélhető le egy
  /// `Image.network`-re: annak nincs JWT-je, és a szerver 404-et adna.
  ///
  /// A [ResponseType.bytes] SZÁNDÉKOSAN a kérés saját beállítása, nem a
  /// `DioFactory` globális alapértelmezése — minden más hívás JSON-t
  /// vár, és egy globális átállítás mindet elrontaná. A Dio a
  /// `bytes`/`stream` válaszfajtát meghagyja, akármi a generikus
  /// argumentum; minden MÁS válaszfajtánál viszont JSON-ra váltana.
  ///
  /// A generikus argumentum LAPOS (`Uint8List`, nem `List<int>`), és ez
  /// szándékos: a `tool/check_data_inventory.dart` kimenő-út mintája
  /// (`\.(…|request)(Uri)?\s*(<[^>]*>)?\s*\(`) az ELSŐ `>`-nél megáll,
  /// tehát egy beágyazott típus-argumentum LÁTHATATLANNÁ tenné ezt a
  /// hívási helyet az adatvédelmi leltár számára — pontosan az a
  /// vakfolt, amit a minta megjegyzése a `getJson<CommunityPage<…>>`
  /// esetén már egyszer megfizetett.
  Future<AppResult<Uint8List>> getBytes(
    String path, {
    bool requiresAuthentication = true,
    String unauthorizedCode = FailureCode.authSessionExpired,
  }) async {
    try {
      final response = await _dio.request<Uint8List>(
        path,
        options: Options(
          method: 'GET',
          responseType: ResponseType.bytes,
          extra: {
            NetworkRequestMetadata.requiresAuthentication:
                requiresAuthentication,
          },
        ),
      );
      final body = response.data;
      if (body == null) {
        throw const FormatException('Expected a byte-array response.');
      }
      return Success(body);
    } on DioException catch (error, stackTrace) {
      return Failure(
        mapNetworkFailure(
          error,
          unauthorizedCode: unauthorizedCode,
          stackTrace: stackTrace,
        ),
      );
    } catch (error, stackTrace) {
      return Failure(
        NetworkFailure(
          code: FailureCode.networkBadResponse,
          retryable: false,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Sends a request whose successful response body is intentionally ignored.
  Future<AppResult<void>> post(
    String path, {
    Object? data,
    Map<String, Object?> headers = const {},
    bool requiresAuthentication = true,
  }) async {
    try {
      await _dio.request<Object?>(
        path,
        data: data,
        options: Options(
          method: 'POST',
          headers: headers,
          extra: {
            NetworkRequestMetadata.requiresAuthentication:
                requiresAuthentication,
          },
        ),
      );
      return const Success(null);
    } on DioException catch (error, stackTrace) {
      return Failure(mapNetworkFailure(error, stackTrace: stackTrace));
    } catch (error, stackTrace) {
      return Failure(UnknownFailure(cause: error, stackTrace: stackTrace));
    }
  }

  /// Sends a DELETE request whose successful response body is
  /// intentionally ignored (E09-R07, ADR 0401 §1).
  ///
  /// Mirror of [post] — the existing four methods are untouched.
  /// The idempotency key (the Kör 7 mutation contract) travels
  /// as a query parameter because DELETE carries no JSON body —
  /// the backend counterpart ``social_graph.py`` reads it from
  /// ``?idempotency_key=...``.
  Future<AppResult<void>> delete(
    String path, {
    Map<String, Object?> headers = const {},
    bool requiresAuthentication = true,
  }) async {
    try {
      await _dio.request<Object?>(
        path,
        options: Options(
          method: 'DELETE',
          headers: headers,
          extra: {
            NetworkRequestMetadata.requiresAuthentication:
                requiresAuthentication,
          },
        ),
      );
      return const Success(null);
    } on DioException catch (error, stackTrace) {
      return Failure(mapNetworkFailure(error, stackTrace: stackTrace));
    } catch (error, stackTrace) {
      return Failure(UnknownFailure(cause: error, stackTrace: stackTrace));
    }
  }

  Future<AppResult<T>> _requestJson<T>({
    required String method,
    required String path,
    required JsonObjectDecoder<T> decode,
    required bool requiresAuthentication,
    required String unauthorizedCode,
    required String conflictCode,
    bool readsErrorDetail = false,
    // `Object?` és nem `Map<String, Object?>?`: a multipart primitív egy
    // `FormData`-t ad át ugyanezen az úton. Az öt JSON-primitív továbbra
    // is térképet küld, tehát a viselkedésük bájtra változatlan.
    Object? data,
    Map<String, Object?>? queryParameters,
  }) async {
    // A `null` értékű kulcsok kihagyása szándékos: a szerver
    // `extra="forbid"` sémái egy `cursor=null` query-paramétert
    // ismeretlen bemenetként utasítanának el.
    final query = queryParameters == null
        ? null
        : <String, Object?>{
            for (final entry in queryParameters.entries)
              if (entry.value != null) entry.key: entry.value,
          };
    final options = Options(
      method: method,
      // Both stay `null` unless the caller opted in, so every other
      // request keeps the base options byte-for-byte (see [getJson]).
      responseType: readsErrorDetail ? ResponseType.plain : null,
      receiveDataWhenStatusError: readsErrorDetail ? true : null,
      extra: {
        NetworkRequestMetadata.requiresAuthentication: requiresAuthentication,
      },
    );
    final Response<Object?> response;
    try {
      // Dio overrides `responseType` to JSON for every generic argument other
      // than `dynamic` or `String`, so the opted-in request has to be issued
      // as `request<String>` for `ResponseType.plain` to survive.
      response = readsErrorDetail
          ? await _dio.request<String>(
              path,
              data: data,
              queryParameters: query,
              options: options,
            )
          : await _dio.request<Object?>(
              path,
              data: data,
              queryParameters: query,
              options: options,
            );
    } on DioException catch (error, stackTrace) {
      return Failure(
        mapNetworkFailure(
          error,
          unauthorizedCode: unauthorizedCode,
          conflictCode: conflictCode,
          stackTrace: stackTrace,
        ),
      );
    } catch (error, stackTrace) {
      return Failure(UnknownFailure(cause: error, stackTrace: stackTrace));
    }

    try {
      var body = response.data;
      // The opted-in request asked for `ResponseType.plain`, so the SUCCESS
      // body arrives as an undecoded string; decoding it here keeps a
      // malformed payload on the existing bad-response path.
      if (readsErrorDetail && body is String) {
        body = jsonDecode(body);
      }
      if (body is! Map) {
        throw const FormatException('Expected a JSON object response.');
      }
      final json = <String, Object?>{};
      for (final entry in body.entries) {
        final key = entry.key;
        if (key is! String) {
          throw const FormatException('JSON object key is not a string.');
        }
        json[key] = entry.value;
      }
      return Success(decode(json));
    } catch (error, stackTrace) {
      return Failure(
        NetworkFailure(
          code: FailureCode.networkBadResponse,
          retryable: false,
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  void close() => _dio.close(force: true);
}
