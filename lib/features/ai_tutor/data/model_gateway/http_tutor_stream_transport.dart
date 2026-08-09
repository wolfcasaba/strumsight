import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../dto/tutor_stream_dto.dart';

/// HTTP/SSE implementation of [TutorStreamTransport].
///
/// This boundary deliberately only removes the SSE envelope. Frame parsing,
/// sequencing and normalization belong to [RemoteTutorModelGateway].
final class HttpTutorStreamTransport implements TutorStreamTransport {
  HttpTutorStreamTransport({required Dio dio}) : this._(dio);

  HttpTutorStreamTransport._(this._dio);

  final Dio _dio;
  CancelToken? _activeCancelToken;

  @override
  Future<AppResult<Stream<String>>> openTurnStream({
    required String requestId,
    required int sequence,
    required String conversationId,
    required String message,
  }) async {
    cancelActiveStream();
    final cancelToken = CancelToken();
    _activeCancelToken = cancelToken;
    try {
      final response = await _dio.post<ResponseBody>(
        '/tutor/stream',
        data: <String, Object?>{
          'request_id': requestId,
          'sequence': sequence,
          'conversation_id': conversationId,
          'message': message,
        },
        cancelToken: cancelToken,
        options: Options(responseType: ResponseType.stream),
      );
      final body = response.data;
      if (body == null || !_isSuccessful(response.statusCode)) {
        _clearActiveToken(cancelToken);
        return const AppResult.failure(
          NetworkFailure(code: FailureCode.networkServer),
        );
      }
      return AppResult.success(_payloads(body.stream, cancelToken));
    } on DioException catch (error, stackTrace) {
      _clearActiveToken(cancelToken);
      return AppResult.failure(_failureFor(error, stackTrace));
    } on Object catch (error, stackTrace) {
      _clearActiveToken(cancelToken);
      return AppResult.failure(
        NetworkFailure(cause: error, stackTrace: stackTrace),
      );
    }
  }

  @override
  void cancelActiveStream() {
    final cancelToken = _activeCancelToken;
    _activeCancelToken = null;
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel();
    }
  }

  @override
  Future<AppResult<void>> health() async {
    try {
      final response = await _dio.get<Object?>('/tutor/capability');
      if (!_isSuccessful(response.statusCode)) {
        return const AppResult.failure(
          NetworkFailure(code: FailureCode.networkServer),
        );
      }
      return const AppResult.success(null);
    } on DioException catch (error, stackTrace) {
      return AppResult.failure(_failureFor(error, stackTrace));
    } on Object catch (error, stackTrace) {
      return AppResult.failure(
        NetworkFailure(cause: error, stackTrace: stackTrace),
      );
    }
  }

  Stream<String> _payloads(Stream<Uint8List> bytes, CancelToken cancelToken) {
    return utf8.decoder
        .bind(bytes)
        .transform(const LineSplitter())
        .transform(
          StreamTransformer<String, String>.fromHandlers(
            handleData: (line, sink) {
              if (line.isEmpty || line.startsWith(':')) return;
              if (!line.startsWith('data:')) return;
              sink.add(line.substring('data:'.length).trimLeft());
            },
            handleError: (error, stackTrace, sink) {
              _clearActiveToken(cancelToken);
              sink.addError(error, stackTrace);
            },
            handleDone: (sink) {
              _clearActiveToken(cancelToken);
              sink.close();
            },
          ),
        );
  }

  void _clearActiveToken(CancelToken cancelToken) {
    if (identical(_activeCancelToken, cancelToken)) {
      _activeCancelToken = null;
    }
  }

  static bool _isSuccessful(int? statusCode) =>
      statusCode != null && statusCode >= 200 && statusCode < 300;

  static NetworkFailure _failureFor(DioException error, StackTrace stackTrace) {
    final code = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => FailureCode.networkTimeout,
      DioExceptionType.badCertificate => FailureCode.networkTls,
      DioExceptionType.badResponse => FailureCode.networkServer,
      _ => FailureCode.networkUnavailable,
    };
    return NetworkFailure(code: code, cause: error, stackTrace: stackTrace);
  }
}
