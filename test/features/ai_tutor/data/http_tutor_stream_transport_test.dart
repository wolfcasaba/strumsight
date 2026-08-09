import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/http_tutor_stream_transport.dart';

final class _SseAdapter implements HttpClientAdapter {
  _SseAdapter({this.body = '', this.statusCode = 200, this.errorType});

  final String body;
  final int statusCode;
  final DioExceptionType? errorType;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (errorType case final type?) {
      throw DioException(requestOptions: options, type: type);
    }
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: const <String>['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

HttpTutorStreamTransport _transport(_SseAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.strumsight.test'));
  dio.httpClientAdapter = adapter;
  return HttpTutorStreamTransport(dio: dio);
}

Future<AppResult<Stream<String>>> _open(HttpTutorStreamTransport transport) {
  return transport.openTurnStream(
    requestId: 'request-1',
    sequence: 4,
    conversationId: 'conversation-1',
    message: 'How do I improve my strumming?',
  );
}

void main() {
  group('HttpTutorStreamTransport', () {
    test(
      'forwards raw data payloads and discards blank and comment lines',
      () async {
        final adapter = _SseAdapter(
          body:
              'data: {"type":"started","seq":0}\n'
              '\n'
              ': keepalive\n'
              'data: {"type":"delta","seq":1,"text":"Hi"}\n'
              'data: {"type":"complete","seq":2}\n',
        );
        final transport = _transport(adapter);

        final result = await _open(transport);

        expect(result, isA<Success<Stream<String>>>());
        await expectLater(
          result.valueOrNull!,
          emitsInOrder(<String>[
            '{"type":"started","seq":0}',
            '{"type":"delta","seq":1,"text":"Hi"}',
            '{"type":"complete","seq":2}',
          ]),
        );
        final request = adapter.requests.single;
        expect(request.method, 'POST');
        expect(request.path, '/tutor/stream');
        expect(request.responseType, ResponseType.stream);
        expect(request.data, <String, Object?>{
          'request_id': 'request-1',
          'sequence': 4,
          'conversation_id': 'conversation-1',
          'message': 'How do I improve my strumming?',
        });
      },
    );

    test(
      'returns a controlled failure when opening the stream cannot connect',
      () async {
        final result = await _open(
          _transport(_SseAdapter(errorType: DioExceptionType.connectionError)),
        );

        expect(result, isA<Failure<Stream<String>>>());
      },
    );

    test('returns a controlled failure for an HTTP server error', () async {
      final result = await _open(_transport(_SseAdapter(statusCode: 500)));

      expect(result, isA<Failure<Stream<String>>>());
    });

    test('returns a controlled failure when health cannot connect', () async {
      final transport = _transport(
        _SseAdapter(errorType: DioExceptionType.connectionError),
      );

      final result = await transport.health();

      expect(result, isA<Failure<void>>());
    });

    test('cancelling without an active stream is a no-op', () {
      final transport = _transport(_SseAdapter());

      expect(transport.cancelActiveStream, returnsNormally);
    });
  });
}
