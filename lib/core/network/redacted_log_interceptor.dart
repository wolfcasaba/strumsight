import 'package:dio/dio.dart';

import '../logging/app_logger.dart';
import 'correlation_id_interceptor.dart';

/// Emits transport metadata without ever logging headers, queries, or bodies.
///
/// The app logger applies a second redaction layer, but this interceptor keeps
/// sensitive values out of the record in the first place.
final class RedactedLogInterceptor extends Interceptor {
  RedactedLogInterceptor(this._logger);

  static const String _startedAtKey = 'strumsight.network_started_at_us';

  final AppLogger _logger;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedAtKey] = DateTime.now().microsecondsSinceEpoch;
    _logger.debug(
      'network.request',
      fields: {
        'method': options.method,
        'path': options.uri.path,
        'correlation_id': options.headers[CorrelationIdInterceptor.headerName],
      },
    );
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final options = response.requestOptions;
    _logger.debug(
      'network.response',
      fields: {
        'method': options.method,
        'path': options.uri.path,
        'status': response.statusCode,
        'elapsed_ms': _elapsedMilliseconds(options),
        'correlation_id': options.headers[CorrelationIdInterceptor.headerName],
      },
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final options = err.requestOptions;
    _logger.debug(
      'network.failure',
      fields: {
        'method': options.method,
        'path': options.uri.path,
        'status': err.response?.statusCode,
        'type': err.type.name,
        'elapsed_ms': _elapsedMilliseconds(options),
        'correlation_id': options.headers[CorrelationIdInterceptor.headerName],
      },
    );
    handler.next(err);
  }

  static int? _elapsedMilliseconds(RequestOptions options) {
    final startedAt = options.extra[_startedAtKey];
    if (startedAt is! int) return null;
    final elapsed = DateTime.now().microsecondsSinceEpoch - startedAt;
    return elapsed < 0 ? 0 : elapsed ~/ Duration.microsecondsPerMillisecond;
  }
}
