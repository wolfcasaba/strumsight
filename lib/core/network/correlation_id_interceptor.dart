import 'package:dio/dio.dart';

typedef CorrelationIdGenerator = String Function();

/// Adds one opaque correlation ID to every outgoing request.
final class CorrelationIdInterceptor extends Interceptor {
  CorrelationIdInterceptor(this._generate);

  static const String headerName = 'X-Correlation-ID';

  final CorrelationIdGenerator _generate;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // The transport owns this value. Accepting a caller-supplied ID would let
    // arbitrary data (including a secret) reach otherwise metadata-only logs.
    options.headers.removeWhere(
      (name, _) => name.toLowerCase() == headerName.toLowerCase(),
    );
    options.headers[headerName] = _generate();
    handler.next(options);
  }
}
