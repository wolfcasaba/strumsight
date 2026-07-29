import 'transport_error_classifier_stub.dart'
    if (dart.library.io) 'transport_error_classifier_io.dart'
    as platform;

/// Platform-aware classification for errors Dio reports as `unknown`.
bool isTlsTransportError(Object? error) => platform.isTlsTransportError(error);

/// Some adapters wrap a socket failure as `unknown` rather than
/// `connectionError`; keep that case in the controlled network taxonomy.
bool isConnectionTransportError(Object? error) =>
    platform.isConnectionTransportError(error);
