import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart' show MessageHandler;
import 'package:flutter_test/flutter_test.dart';

/// Thrown by every [FakeNetworkGuard]-blocked path — a distinct type so a
/// test can assert the guard itself tripped, not some unrelated failure.
final class NetworkGuardViolation implements Exception {
  NetworkGuardViolation(this.channel);

  /// Which of the three guarded paths was attempted: `'dio'`,
  /// `'http-overrides'`, or the platform-channel name.
  final String channel;

  @override
  String toString() =>
      'NetworkGuardViolation: fake_network_guard blocked "$channel"';
}

/// Blocks every outgoing path a StrumSight build can reach — the Dio
/// `HttpClientAdapter`, `dart:io`'s `HttpOverrides`, and platform channels —
/// and records each attempt (E12-R11, ADR 0472 D2).
///
/// A single named channel mock only proves that one channel stayed quiet
/// ([L453](../../docs/LESSONS.md#l453)); this guard's platform-channel path
/// is a process-wide catch-all instead, so a plugin reaching for a channel
/// nobody anticipated is still caught.
final class FakeNetworkGuard {
  /// Every blocked attempt, in order.
  final List<NetworkGuardViolation> violations = <NetworkGuardViolation>[];

  bool _installed = false;
  HttpOverrides? _previousOverrides;

  /// True once any of the three paths has recorded a violation.
  bool get tripped => violations.isNotEmpty;

  void _record(String channel) =>
      violations.add(NetworkGuardViolation(channel));

  /// The Dio adapter to inject wherever the app builds an `HttpClientAdapter`
  /// (`accountDioFactoryProvider` and any sibling). Every `fetch` records a
  /// violation and throws instead of returning a response.
  HttpClientAdapter get dioAdapter => _GuardedHttpClientAdapter(this);

  /// The `dart:io` override to inject wherever the app builds a real
  /// `HttpClient` bypassing Dio. Every `createHttpClient` records a
  /// violation and throws.
  HttpOverrides get httpOverrides => _GuardedHttpOverrides(this);

  /// Installs the `dart:io` and platform-channel guards process-wide. Call
  /// once per test (`setUp`); pair with [uninstall] (`tearDown`).
  void install() {
    if (_installed) return;
    _installed = true;
    _previousOverrides = HttpOverrides.current;
    HttpOverrides.global = httpOverrides;
    TestDefaultBinaryMessengerBinding
            .instance
            .defaultBinaryMessenger
            .allMessagesHandler =
        _handleOutgoingMessage;
  }

  /// Restores the ambient `HttpOverrides` and clears the platform-channel
  /// catch-all. Idempotent.
  void uninstall() {
    if (!_installed) return;
    _installed = false;
    HttpOverrides.global = _previousOverrides;
    TestDefaultBinaryMessengerBinding
            .instance
            .defaultBinaryMessenger
            .allMessagesHandler =
        null;
  }

  /// Sees every outgoing platform message before the per-channel mock that
  /// would otherwise answer it (the [handler] argument). A channel the test
  /// binding — or another fixture — already mocked keeps working unchanged.
  ///
  /// The engine's own embedder channels (`flutter/platform`,
  /// `flutter/mousecursor`, `flutter/restoration`, …) are UNMOCKED by
  /// default and fire on every boot regardless of the app under test (a
  /// bare `MaterialApp` alone triggers `flutter/platform` for
  /// `SystemChrome.setApplicationSwitcherDescription`) — they are reserved,
  /// engine-internal, and never reach a plugin or a network. Dart/Flutter's
  /// own naming convention keeps that whole namespace under the `flutter/`
  /// prefix; every *plugin* channel (secure storage, package info, share,
  /// permission handler, …) uses its own distinct namespace instead. This
  /// is a structural boundary on a whole reserved namespace, not one named
  /// channel picked by hand ([L453](../../docs/LESSONS.md#l453)) — any
  /// plugin channel, anticipated or not, still trips the guard.
  Future<ByteData?>? _handleOutgoingMessage(
    String channel,
    MessageHandler? handler,
    ByteData? message,
  ) {
    if (handler != null) return handler(message);
    if (channel.startsWith('flutter/')) {
      return TestDefaultBinaryMessengerBinding
          .instance
          .defaultBinaryMessenger
          .delegate
          .send(channel, message);
    }
    _record(channel);
    return Future<ByteData?>.error(NetworkGuardViolation(channel));
  }
}

final class _GuardedHttpClientAdapter implements HttpClientAdapter {
  _GuardedHttpClientAdapter(this._guard);

  final FakeNetworkGuard _guard;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    _guard._record('dio');
    throw NetworkGuardViolation('dio');
  }

  @override
  void close({bool force = false}) {}
}

final class _GuardedHttpOverrides extends HttpOverrides {
  _GuardedHttpOverrides(this._guard);

  final FakeNetworkGuard _guard;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    _guard._record('http-overrides');
    throw NetworkGuardViolation('http-overrides');
  }
}
