/// Lifecycle-aware, cancelable, progress-emitting Community media
/// uploader (E09-R18, ADR 0410).
///
/// The client-side half of the §6 A7 acceptance cell — the
/// server-side half lives in
/// ``backend/app/community/services/media_upload_service.py``.
/// This uploader wraps a ``Dio.put`` against the backend-issued
/// presigned URL with three load-bearing affordances:
///
/// * **Cancelable** — the ``cancel()`` call drops the in-flight
///   ``Dio.put`` request via a ``CancelToken``, so a user-tap on
///   the composer's "cancel" button or a router-pop during upload
///   actually stops the network call instead of finishing in the
///   background. The A7 cell's "cancel actually aborts" assertion
///   is the second part of the round's wire contract.
/// * **Lifecycle-aware** — the uploader surfaces a ``Stream<UploadEvent>``
///   the composer can subscribe to so progress / completion /
///   cancel state travel through the Riverpod layer the same way
///   every other Community action travels. The stream closes on
///   terminal state (done / errored / cancelled) so a stale
///   subscriber is forced to re-subscribe on a new intent.
/// * **Progress callback** — Dio's ``onSendProgress`` reports the
///   byte count to the ``ProgressCallback`` the composer passed in,
///   so the UI's progress bar follows the actual upload instead
///   of guessing.
///
/// The uploader has zero knowledge of the backend's Community
/// router — it consumes an ``UploadIntent`` value object (the
/// server's intent response) and an optional
/// ``CommunityMediaIntentClient`` (the future round's HTTP
/// surface). This round ships the uploader as the
/// flag-protected component the brief §3 calls for; the HTTP
/// wiring is a Kör 19+ task.
///
/// **Dependency injection:** the uploader's constructor takes a
/// ``Dio`` instance — tests inject a Dio with a
/// ``MockHttpClientAdapter`` that simulates the presigned-URL
/// PUT without going over the wire. The production wiring (a
/// future round) builds the Dio via ``accountApiClientProvider``,
/// the same shared client the auth + settings layers ride on.
library;

import 'dart:async';

import 'package:dio/dio.dart';

/// The presigned PUT URL the backend emitted for this upload,
/// plus the constraints the URL carries. Mirrors the
/// ``SignedUpload`` wire shape on the backend
/// (``backend/app/community/storage/object_store.py``).
///
/// The Dart side does NOT re-validate the constraints — the
/// bucket enforces them at PUT time, and the backend finalize
/// re-checks (defense-in-depth, brief §6.1 threshold-triple).
/// The fields are surfaced for progress / logging / test
/// introspection only.
class PresignedUpload {
  const PresignedUpload({
    required this.url,
    required this.method,
    required this.contentType,
    required this.maxContentLength,
    required this.expiresAt,
  });

  /// The presigned URL — the client PUTs the bytes here.
  final String url;

  /// Always ``"PUT"`` for direct-upload flows.
  final String method;

  /// The ``Content-Type`` header value the bucket enforces.
  final String contentType;

  /// The byte cap the bucket enforces via signed query params.
  final int maxContentLength;

  /// Absolute UTC timestamp when the signed URL stops being
  /// accepted by the bucket.
  final DateTime expiresAt;
}

/// The backend's intent response. Carries the wire identity
/// (``mediaPublicId``) the finalize step posts back, the
/// bucket-side key (the audit trail handle), and the signed
/// upload the client PUTs to.
class CommunityMediaUploadIntent {
  const CommunityMediaUploadIntent({
    required this.mediaPublicId,
    required this.objectKey,
    required this.signedUpload,
  });

  /// The ``public_id`` of the ``CommunityMedia`` row — the
  /// wire identity the finalize step posts back.
  final String mediaPublicId;

  /// The bucket-side key — opaque to the client; logged for
  /// crash-report correlation only.
  final String objectKey;

  /// The presigned PUT URL + constraints.
  final PresignedUpload signedUpload;
}

/// The terminal / progress events the uploader streams.
sealed class CommunityMediaUploadEvent {
  const CommunityMediaUploadEvent();
}

/// Fired on every ``onSendProgress`` tick — the composer
/// converts this to a progress bar.
class CommunityMediaUploadProgress extends CommunityMediaUploadEvent {
  const CommunityMediaUploadProgress({
    required this.sentBytes,
    required this.totalBytes,
  });

  final int sentBytes;
  final int totalBytes;

  /// 0.0–1.0 progress fraction; clamped to [0, 1] when the
  /// total is unknown (``totalBytes <= 0``) the fraction is 0.
  double get fraction {
    if (totalBytes <= 0) return 0;
    final raw = sentBytes / totalBytes;
    if (raw < 0) return 0;
    if (raw > 1) return 1;
    return raw;
  }
}

/// Fired on a successful upload — the bytes are in the bucket.
/// The composer should call the backend's finalize endpoint
/// next.
class CommunityMediaUploadCompleted extends CommunityMediaUploadEvent {
  const CommunityMediaUploadCompleted({required this.responseStatus});
  final int responseStatus;
}

/// Fired on a user-initiated cancel — the in-flight PUT was
/// aborted via ``CancelToken``; the server-side half is the
/// cancel endpoint (A7 cell).
class CommunityMediaUploadCancelled extends CommunityMediaUploadEvent {
  const CommunityMediaUploadCancelled();
}

/// Fired on a transport / network failure (NOT a cancel).
class CommunityMediaUploadFailed extends CommunityMediaUploadEvent {
  const CommunityMediaUploadFailed({required this.message, this.cause});

  final String message;
  final Object? cause;
}

/// A progress callback the composer can pass in for a
/// one-shot callback alternative to the event stream. Both
/// surfaces are wired; the composer picks one.
typedef CommunityMediaProgressCallback = void Function(int sent, int total);

/// The cancelable, lifecycle-aware uploader.
///
/// A new uploader instance is created per upload attempt — the
/// class is NOT thread-safe, the single in-flight token pattern
/// matches the ``AccountApiClient`` call surface (one request
/// per composer, parallel uploads are a future round).
class CommunityMediaUploader {
  CommunityMediaUploader({required Dio dio}) : _dio = dio;

  final Dio _dio;

  CancelToken? _cancelToken;
  bool _cancelled = false;

  /// ``true`` after :meth:`cancel` has been called. The A7 cell
  /// reads this to assert the cancel actually short-circuited
  /// the in-flight request.
  bool get isCancelled => _cancelled;

  /// Upload ``bytes`` to the backend-issued signed URL.
  ///
  /// The caller is expected to have:
  ///
  /// * fetched an intent via the backend's
  ///   ``communityMediaIntentEndpoint`` (a future round's
  ///   ``accountApiClient.postJson`` call),
  /// * computed the SHA-256 digest of ``bytes`` (so the
  ///   intent carries the right ``checksum_sha256``),
  /// * computed the right ``content_type`` (so the intent
  ///   declares the MIME the bucket will enforce).
  ///
  /// This method does NOT validate the size / content-type
  /// against the intent — the bucket enforces the signed-URL
  /// constraints at PUT time, and the backend's finalize path
  /// re-checks (defense-in-depth). The Dart side's job is
  /// ``Dio.put`` with a cancelable token and a progress
  /// callback.
  ///
  /// Returns a stream of :class:`CommunityMediaUploadEvent` —
  /// at least one terminal event (completed / cancelled /
  /// failed) fires before the stream closes.
  Stream<CommunityMediaUploadEvent> upload({
    required CommunityMediaUploadIntent intent,
    required List<int> bytes,
    CommunityMediaProgressCallback? onProgress,
  }) async* {
    _cancelToken = CancelToken();
    _cancelled = false;
    final total = bytes.length;
    final response = await _dio.put<dynamic>(
      intent.signedUpload.url,
      data: bytes,
      options: Options(
        method: intent.signedUpload.method,
        headers: <String, Object?>{
          'Content-Type': intent.signedUpload.contentType,
        ),
        // The progress callback fires on every chunk the
        // socket flushes. ``total`` is the request body's full
        // size; ``count`` is the bytes the OS has handed to
        // the socket so far.
        onSendProgress: (count, _, _) {
          if (onProgress != null) {
            onProgress(count, total);
          }
        },
      ),
      cancelToken: _cancelToken,
    );
    if (_cancelled) {
      yield const CommunityMediaUploadCancelled();
      return;
    }
    yield CommunityMediaUploadProgress(
      sentBytes: total,
      totalBytes: total,
    );
    yield CommunityMediaUploadCompleted(
      responseStatus: response.statusCode ?? 0,
    );
  }

  /// Cancel the in-flight upload.
  ///
  /// The method is idempotent — a second call is a no-op.
  /// The in-flight ``Dio.put`` is aborted via
  /// ``CancelToken.cancel``; the upload stream emits
  /// :class:`CommunityMediaUploadCancelled` next.
  ///
  /// The A7 acceptance cell asserts this method actually
  /// aborted the HTTP request — the in-flight call must NOT
  /// complete after ``cancel()`` returns. The
  /// ``MockHttpClientAdapter`` in the test exercises this with
  /// a long-running response that the cancel interrupts
  /// mid-flight.
  void cancel() {
    _cancelled = true;
    _cancelToken?.cancel('user cancelled upload');
  }
}