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
  Future<AppResult<T>> getJson<T>(
    String path, {
    required JsonObjectDecoder<T> decode,
    Map<String, Object?>? queryParameters,
    bool requiresAuthentication = true,
    String unauthorizedCode = FailureCode.authSessionExpired,
    String conflictCode = FailureCode.validationInvalidInput,
  }) => _requestJson(
    method: 'GET',
    path: path,
    decode: decode,
    queryParameters: queryParameters,
    requiresAuthentication: requiresAuthentication,
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
    Map<String, Object?>? data,
    Map<String, Object?>? queryParameters,
  }) async {
    final Response<Object?> response;
    try {
      response = await _dio.request<Object?>(
        path,
        data: data,
        // A `null` értékű kulcsok kihagyása szándékos: a szerver
        // `extra="forbid"` sémái egy `cursor=null` query-paramétert
        // ismeretlen bemenetként utasítanának el.
        queryParameters: queryParameters == null
            ? null
            : <String, Object?>{
                for (final entry in queryParameters.entries)
                  if (entry.value != null) entry.key: entry.value,
              },
        options: Options(
          method: method,
          extra: {
            NetworkRequestMetadata.requiresAuthentication:
                requiresAuthentication,
          },
        ),
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
      final body = response.data;
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
