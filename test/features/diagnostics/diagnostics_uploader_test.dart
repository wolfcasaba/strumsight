import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/core/api/api_config.dart';
import 'package:music_theory/features/diagnostics/data/diagnostics_uploader.dart';
import 'package:music_theory/features/diagnostics/model/diagnostics_session.dart';

/// A Dio adapter that records the request and returns a canned status (or
/// throws a transport error) so the uploader can be exercised without a server.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({this.status = 200, this.throwError = false});

  final int status;
  final bool throwError;

  int calls = 0;
  RequestOptions? lastOptions;
  Uint8List? lastBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    lastOptions = options;
    if (requestStream != null) {
      final chunks = await requestStream.toList();
      lastBody = Uint8List.fromList(
          chunks.expand((c) => c).toList(growable: false));
    }
    if (throwError) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString(
      '{"ok":true}',
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DiagnosticsSession _session() => const DiagnosticsSession(
      sessionId: 'sid-1',
      appVersion: '1.0.0+1',
      device: 'android',
      startedAt: '2026-07-14T00:00:00.000Z',
      events: [
        DiagnosticsEvent(tSec: 0, mlChord: 'C', dspChord: 'C', agree: true),
      ],
    );

Dio _dioWith(_FakeAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));
  dio.httpClientAdapter = adapter;
  return dio;
}

void main() {
  test('success (2xx) → uploaded, sends token + gzip headers', () async {
    final adapter = _FakeAdapter(status: 200);
    final uploader = DiagnosticsUploader(dio: _dioWith(adapter));

    final status = await uploader.upload(_session(),
        appVersion: '1.0.0+1', device: 'android');

    expect(status, DiagnosticsUploadStatus.uploaded);
    expect(adapter.calls, 1);
    final headers = adapter.lastOptions!.headers;
    expect(headers['X-Diag-Token'], ApiConfig.diagToken);
    expect(headers['Content-Encoding'], 'gzip');
    expect(headers['X-App-Version'], '1.0.0+1');
    expect(headers['X-Device'], 'android');
    // Body is really gzipped (magic bytes 0x1f 0x8b).
    expect(adapter.lastBody, isNotNull);
    expect(adapter.lastBody!.length, greaterThan(2));
    expect(adapter.lastBody![0], 0x1f);
    expect(adapter.lastBody![1], 0x8b);
  });

  test('network error → failed, never throws, retries then gives up', () async {
    final adapter = _FakeAdapter(throwError: true);
    final uploader = DiagnosticsUploader(dio: _dioWith(adapter), maxRetries: 2);

    final status = await uploader.upload(_session());

    expect(status, DiagnosticsUploadStatus.failed);
    // First attempt + 2 retries = 3 calls.
    expect(adapter.calls, 3);
  });

  test('non-2xx server response → failed', () async {
    final adapter = _FakeAdapter(status: 401);
    final uploader = DiagnosticsUploader(dio: _dioWith(adapter));

    // Dio throws on 4xx by default; the uploader catches it as a failure.
    final status = await uploader.upload(_session());
    expect(status, DiagnosticsUploadStatus.failed);
  });

  group('clipFromPcm', () {
    test('null on empty / invalid input', () {
      expect(DiagnosticsUploader.clipFromPcm(const [], 44100), isNull);
      expect(DiagnosticsUploader.clipFromPcm(const [0.1, 0.2], 0), isNull);
    });

    test('encodes a base64 WAV within the byte cap', () {
      // A big clip forces decimation; the resulting WAV must stay under the cap.
      final pcm = List<double>.filled(4 * 1024 * 1024, 0.5);
      final clip = DiagnosticsUploader.clipFromPcm(pcm, 44100);
      expect(clip, isNotNull);
      expect(clip!.tSec, 0);
      expect(clip.wavBase64, isNotEmpty);
      // base64 decodes to at most ~maxWavBytes.
      final rawBytes = clip.wavBase64.length * 3 ~/ 4;
      expect(rawBytes, lessThanOrEqualTo(DiagnosticsUploader.maxWavBytes + 64));
    });
  });
}
