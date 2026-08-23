/// E09-R18 — Community media uploader acceptance tests.
///
/// Covers the Flutter-side half of the brief §6 A7 cell: the
/// cancel actually aborts an in-flight PUT request. The
/// backend-side half lives in
/// ``backend/tests/community/test_media_upload.py``.
///
/// * **A7** — the uploader's :meth:`CommunityMediaUploader.cancel`
///   drops the in-flight ``Dio.put`` via ``CancelToken``. The
///   mock adapter records the cancelled state — the test
///   asserts the response stream emits
///   :class:`CommunityMediaUploadCancelled` and no
///   ``CommunityMediaUploadCompleted` follows.
///
/// * **progress** — a normal upload emits progress events
///   from the ``onSendProgress`` callback, and the terminal
///   event is ``CommunityMediaUploadCompleted`` carrying the
///   mock response status.
///
/// The test runs against a ``Dio`` configured with a
/// ``MockHttpClientAdapter`` — no real network I/O, no
/// production backend dependency.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/community/data/api/community_media_uploader.dart';

/// A long-running response that the test cancels mid-flight.
/// The controller lets the test resume / cancel the upload
/// from the outside.
class _CancellableMockAdapter implements HttpClientAdapter {
  _CancellableMockAdapter(this.respondAfter);

  final Duration respondAfter;

  final List<RequestOptions> started = <RequestOptions>[];
  final List<RequestOptions> cancelled = <RequestOptions>[];
  Completer<ResponseBody>? _inflight;

  @override
  void close({bool force = false}) {
    if (_inflight != null && !_inflight!.isCompleted) {
      _inflight!.complete(ResponseBody.fromString('cancelled', 499));
    }
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    started.add(options);
    _inflight = Completer<ResponseBody>();
    try {
      await Future<void>.delayed(respondAfter);
      if (cancelFuture != null) {
        // Honour a cancelled future — Dio hands us a future
        // that completes when the caller's CancelToken fires.
        await cancelFuture;
      }
    } catch (_) {
      cancelled.add(options);
      _inflight!.complete(ResponseBody.fromString('cancelled', 499));
      rethrow;
    }
    if (cancelFuture != null) {
      // Already cancelled — don't return a 200.
      cancelled.add(options);
      throw DioException.requestCancelled(
        requestOptions: options,
        reason: 'cancelled',
      );
    }
    final bytes = List<int>.filled(8, 0);
    final body = ResponseBody.fromBytes(
      bytes,
      200,
      headers: <String, List<String>>{
        'content-type': <String>['application/octet-stream'],
      },
    );
    _inflight!.complete(body);
    return body;
  }
}

void main() {
  group('CommunityMediaUploader', () {
    test('happy path: upload emits progress + completed events', () async {
      final adapter = _CancellableMockAdapter(const Duration(milliseconds: 5));
      final dio = Dio(BaseOptions(headers: <String, Object?>{}));
      dio.httpClientAdapter = adapter;
      final uploader = CommunityMediaUploader(dio: dio);

      final progressTicks = <double>[];
      final events = <CommunityMediaUploadEvent>[];
      final completer = Completer<void>();
      final stream = uploader.upload(
        intent: CommunityMediaUploadIntent(
          mediaPublicId: 'mp-1',
          objectKey: 'community-media/1/mp-1',
          signedUpload: PresignedUpload(
            url: 'https://bucket.example/upload',
            method: 'PUT',
            contentType: 'audio/mpeg',
            maxContentLength: 1024,
            expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
          ),
        ),
        bytes: List<int>.filled(8, 0x42),
        onProgress: (sent, total) {
          progressTicks.add(total == 0 ? 0 : sent / total);
        },
      );
      final sub = stream.listen(
        events.add,
        onError: (_) => completer.complete(),
        onDone: () => completer.complete(),
      );
      await completer.future;
      await sub.cancel();

      expect(
        events.whereType<CommunityMediaUploadProgress>().isNotEmpty,
        isTrue,
        reason: 'progress events should fire from onSendProgress',
      );
      expect(
        events.whereType<CommunityMediaUploadCompleted>().length,
        1,
        reason: 'happy path emits exactly one completed event',
      );
      expect(progressTicks, isNotEmpty);
    });

    test('A7 — cancel() drops the in-flight request via CancelToken', () async {
      final adapter = _CancellableMockAdapter(const Duration(seconds: 30));
      final dio = Dio(BaseOptions(headers: <String, Object?>{}));
      dio.httpClientAdapter = adapter;
      final uploader = CommunityMediaUploader(dio: dio);

      final events = <CommunityMediaUploadEvent>[];
      final completer = Completer<void>();
      // Kick off the upload, then cancel mid-flight.
      final stream = uploader.upload(
        intent: CommunityMediaUploadIntent(
          mediaPublicId: 'mp-2',
          objectKey: 'community-media/1/mp-2',
          signedUpload: PresignedUpload(
            url: 'https://bucket.example/upload',
            method: 'PUT',
            contentType: 'audio/mpeg',
            maxContentLength: 1024,
            expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
          ),
        ),
        bytes: List<int>.filled(8, 0x42),
      );
      final sub = stream.listen(
        events.add,
        onError: (_) => completer.complete(),
        onDone: () => completer.complete(),
      );

      // Give the request a moment to register on the adapter
      // (its delay timer starts on fetch()).
      await Future<void>.delayed(const Duration(milliseconds: 20));
      uploader.cancel();

      await completer.future;
      await sub.cancel();

      // The cancel cell — the in-flight call must NOT have
      // completed.
      expect(uploader.isCancelled, isTrue);
      expect(
        events.whereType<CommunityMediaUploadCompleted>().isEmpty,
        isTrue,
        reason: 'cancelled upload must NOT emit a completed event',
      );
      expect(
        events.whereType<CommunityMediaUploadCancelled>().length,
        1,
        reason: 'cancelled upload emits exactly one cancel event',
      );
    });

    test('cancel is idempotent', () async {
      final adapter = _CancellableMockAdapter(const Duration(seconds: 30));
      final dio = Dio(BaseOptions(headers: <String, Object?>{}));
      dio.httpClientAdapter = adapter;
      final uploader = CommunityMediaUploader(dio: dio);

      final events = <CommunityMediaUploadEvent>[];
      final completer = Completer<void>();
      final stream = uploader.upload(
        intent: CommunityMediaUploadIntent(
          mediaPublicId: 'mp-3',
          objectKey: 'community-media/1/mp-3',
          signedUpload: PresignedUpload(
            url: 'https://bucket.example/upload',
            method: 'PUT',
            contentType: 'audio/mpeg',
            maxContentLength: 1024,
            expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
          ),
        ),
        bytes: List<int>.filled(8, 0x42),
      );
      final sub = stream.listen(
        events.add,
        onError: (_) => completer.complete(),
        onDone: () => completer.complete(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      uploader.cancel();
      uploader.cancel();
      uploader.cancel();
      await completer.future;
      await sub.cancel();

      expect(uploader.isCancelled, isTrue);
      expect(
        events.whereType<CommunityMediaUploadCancelled>().length,
        1,
        reason: 'idempotent cancel emits exactly one cancel event',
      );
    });

    test('progress fraction clamps to [0, 1]', () {
      const p1 = CommunityMediaUploadProgress(sentBytes: 5, totalBytes: 10);
      expect(p1.fraction, 0.5);
      const p2 = CommunityMediaUploadProgress(sentBytes: 15, totalBytes: 10);
      expect(p2.fraction, 1.0);
      const p3 = CommunityMediaUploadProgress(sentBytes: -1, totalBytes: 10);
      expect(p3.fraction, 0.0);
      const p4 = CommunityMediaUploadProgress(sentBytes: 0, totalBytes: 0);
      expect(p4.fraction, 0.0);
    });
  });
}
