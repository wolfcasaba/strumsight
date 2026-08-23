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
///   ``CommunityMediaUploadCompleted`` follows.
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
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/community/data/api/community_media_uploader.dart';

/// Minimal Dio mock adapter that returns a 200 OK with a
/// payload after the (configurable) delay, OR throws
/// ``DioException.requestCancelled`` when the Dio
/// ``CancelToken`` fires while the request is in flight.
///
/// This is what the §6 A7 cell needs: a request that stays
/// in-flight until either the delay elapses (happy path) or
/// the cancel token fires (cancel cell). A long ``respondAfter``
/// gives the test time to call ``uploader.cancel()`` mid-flight.
class _DelayedMockAdapter implements HttpClientAdapter {
  _DelayedMockAdapter({this.respondAfter = const Duration(seconds: 30)});

  final Duration respondAfter;

  bool wasCancelled = false;
  bool wasCompleted = false;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    final completer = Completer<ResponseBody>();
    final timer = Timer(respondAfter, () {
      if (!completer.isCompleted) {
        wasCompleted = true;
        completer.complete(
          ResponseBody.fromBytes(
            Uint8List(8),
            200,
            headers: <String, List<String>>{
              'content-type': <String>['application/octet-stream'],
            },
          ),
        );
      }
    });
    cancelFuture?.then((_) {
      if (!completer.isCompleted) {
        wasCancelled = true;
        completer.completeError(
          DioException.requestCancelled(
            requestOptions: options,
            reason: 'cancelled',
          ),
        );
      }
    });
    try {
      return await completer.future;
    } finally {
      timer.cancel();
    }
  }
}

CommunityMediaUploadIntent _buildIntent({String id = 'mp-1'}) {
  return CommunityMediaUploadIntent(
    mediaPublicId: id,
    objectKey: 'community-media/1/$id',
    signedUpload: PresignedUpload(
      url: 'https://bucket.example/upload',
      method: 'PUT',
      contentType: 'audio/mpeg',
      maxContentLength: 1024,
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    ),
  );
}

void main() {
  group('CommunityMediaUploader', () {
    test('happy path: upload emits a completed event', () async {
      final adapter = _DelayedMockAdapter(
        respondAfter: const Duration(milliseconds: 5),
      );
      final dio = Dio(BaseOptions(headers: <String, Object?>{}));
      dio.httpClientAdapter = adapter;
      final uploader = CommunityMediaUploader(dio: dio);

      final events = <CommunityMediaUploadEvent>[];
      final completer = Completer<void>();
      final stream = uploader.upload(
        intent: _buildIntent(),
        bytes: List<int>.filled(8, 0x42),
      );
      final sub = stream.listen(
        events.add,
        onError: (_) {
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );
      await completer.future;
      await sub.cancel();

      expect(adapter.wasCancelled, isFalse);
      expect(adapter.wasCompleted, isTrue);
      expect(
        events.whereType<CommunityMediaUploadCompleted>().length,
        1,
        reason: 'happy path emits exactly one completed event',
      );
    });

    test('A7 — cancel() drops the in-flight request via CancelToken', () async {
      final adapter = _DelayedMockAdapter(
        respondAfter: const Duration(seconds: 30),
      );
      final dio = Dio(BaseOptions(headers: <String, Object?>{}));
      dio.httpClientAdapter = adapter;
      final uploader = CommunityMediaUploader(dio: dio);

      final events = <CommunityMediaUploadEvent>[];
      final completer = Completer<void>();
      final stream = uploader.upload(
        intent: _buildIntent(id: 'mp-2'),
        bytes: List<int>.filled(8, 0x42),
      );
      final sub = stream.listen(
        events.add,
        onError: (_) {
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      // Give the request a moment to register on the adapter.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      uploader.cancel();

      await completer.future;
      await sub.cancel();

      expect(uploader.isCancelled, isTrue);
      expect(adapter.wasCancelled, isTrue);
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
      final adapter = _DelayedMockAdapter(
        respondAfter: const Duration(seconds: 30),
      );
      final dio = Dio(BaseOptions(headers: <String, Object?>{}));
      dio.httpClientAdapter = adapter;
      final uploader = CommunityMediaUploader(dio: dio);

      final events = <CommunityMediaUploadEvent>[];
      final completer = Completer<void>();
      final stream = uploader.upload(
        intent: _buildIntent(id: 'mp-3'),
        bytes: List<int>.filled(8, 0x42),
      );
      final sub = stream.listen(
        events.add,
        onError: (_) {
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
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
