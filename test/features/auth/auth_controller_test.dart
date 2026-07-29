import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/logging/debug_app_logger.dart';
import 'package:strumsight/core/logging/logger_provider.dart';
import 'package:strumsight/core/network/dio_factory.dart';
import 'package:strumsight/features/auth/data/auth_repository.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/model/auth_user.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';

import '../../support/fake_auth.dart';

ProviderContainer _container(
  FakeTokenStore store,
  AuthRepository repo, {
  RecordingLogSink? sink,
  bool accountEnabled = true,
  DioFactory? dioFactory,
  bool useHttpRepository = false,
}) {
  final config = AppConfig.resolve(
    environment: AppEnvironment.development,
    apiBaseUrl: AppConfig.devApiBaseUrl,
    flags: FeatureFlags.forEnvironment(
      AppEnvironment.development,
      accountEnabled: accountEnabled,
    ),
    diagnosticsToken: AppConfig.devDiagnosticsToken,
    buildMode: 'debug',
    appVersion: 'test',
  );
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(config),
      tokenStoreProvider.overrideWithValue(store),
      if (!useHttpRepository) authRepositoryProvider.overrideWithValue(repo),
      if (dioFactory != null)
        accountDioFactoryProvider.overrideWithValue(dioFactory),
      if (sink != null)
        appLoggerProvider.overrideWithValue(
          DebugAppLogger(sink: sink.call, enabled: true),
        ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

final class _DelayedUnauthorizedAdapter implements HttpClientAdapter {
  final Completer<void> requestStarted = Completer<void>();
  final Completer<void> releaseResponse = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestStarted.complete();
    await releaseResponse.future;
    return ResponseBody.fromString(
      '{"detail":"expired"}',
      401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final class _LoginAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body = switch (options.path) {
      '/auth/login' => '{"access_token":"ephemeral-token"}',
      '/auth/me' => '{"id":1,"email":"player@strumsight.app"}',
      _ => '{}',
    };
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final class _DelayedLoginRepository implements AuthRepository {
  final Completer<void> loginStarted = Completer<void>();
  final Completer<void> releaseLogin = Completer<void>();

  @override
  Future<AppResult<String>> login(String email, String password) async {
    loginStarted.complete();
    await releaseLogin.future;
    return const Success('delayed-token');
  }

  @override
  Future<AppResult<AuthUser>> me() async =>
      const Success(AuthUser(id: 1, email: 'delayed@strumsight.app'));

  @override
  Future<AppResult<String>> register(String email, String password) =>
      login(email, password);
}

final class _RacingLoginRepository implements AuthRepository {
  final Completer<void> firstLoginStarted = Completer<void>();
  final Completer<void> releaseFirstLogin = Completer<void>();
  AuthUser _nextUser = const AuthUser(id: 2, email: 'second@strumsight.app');

  @override
  Future<AppResult<String>> login(String email, String password) async {
    if (email.startsWith('first')) {
      firstLoginStarted.complete();
      await releaseFirstLogin.future;
      _nextUser = const AuthUser(id: 1, email: 'first@strumsight.app');
      return const Success('first-token');
    }
    _nextUser = const AuthUser(id: 2, email: 'second@strumsight.app');
    return const Success('second-token');
  }

  @override
  Future<AppResult<AuthUser>> me() async => Success(_nextUser);

  @override
  Future<AppResult<String>> register(String email, String password) =>
      login(email, password);
}

final class _DelayedMeRepository implements AuthRepository {
  final Completer<void> meStarted = Completer<void>();
  final Completer<void> releaseMe = Completer<void>();

  @override
  Future<AppResult<String>> login(String email, String password) async =>
      const Success('unused');

  @override
  Future<AppResult<AuthUser>> me() async {
    meStarted.complete();
    await releaseMe.future;
    return const Success(AuthUser(id: 1, email: 'restored@strumsight.app'));
  }

  @override
  Future<AppResult<String>> register(String email, String password) async =>
      const Success('unused');
}

final class _DelayedWriteTokenStore extends FakeTokenStore {
  final Completer<void> writeStarted = Completer<void>();
  final Completer<void> releaseWrite = Completer<void>();

  @override
  Future<AppResult<void>> write(String token) async {
    writes++;
    writeStarted.complete();
    await releaseWrite.future;
    this.token = token;
    return const Success(null);
  }
}

final class _DelayedClearTokenStore extends FakeTokenStore {
  _DelayedClearTokenStore(super.token);

  final Completer<void> clearStarted = Completer<void>();
  final Completer<void> releaseClear = Completer<void>();

  @override
  Future<AppResult<void>> clear() async {
    clears++;
    clearStarted.complete();
    await releaseClear.future;
    token = null;
    return const Success(null);
  }
}

void main() {
  test('account-disabled build ignores a stale stored token', () async {
    final store = FakeTokenStore('stale-token');
    final repo = FakeAuthRepository();
    final container = _container(store, repo, accountEnabled: false);

    expect(await container.read(authControllerProvider.future), isNull);
    expect(store.reads, 0);
    expect(repo.meCalls, 0);
  });

  test('starts logged out when no token is stored', () async {
    final container = _container(FakeTokenStore(), FakeAuthRepository());
    final user = await container.read(authControllerProvider.future);
    expect(user, isNull);
  });

  test('restores a session from a stored token', () async {
    final store = FakeTokenStore('stored-token');
    final container = _container(store, FakeAuthRepository());
    final user = await container.read(authControllerProvider.future);
    expect(user, isA<AuthUser>());
    expect(user!.email, 'player@strumsight.app');
  });

  test('drops an invalid stored token and starts logged out', () async {
    final store = FakeTokenStore('expired');
    final repo = FakeAuthRepository()
      ..meFailure = const AuthenticationFailure();
    final container = _container(store, repo);
    final user = await container.read(authControllerProvider.future);
    expect(user, isNull);
    expect(store.token, isNull); // cleared
  });

  test(
    'keeps the stored token when the restore fails on the network',
    () async {
      // Launching offline must not log the user out permanently — only an
      // authentication verdict proves the token is dead.
      final store = FakeTokenStore('stored-token');
      final repo = FakeAuthRepository()..meFailure = const NetworkFailure();
      final container = _container(store, repo);

      final user = await container.read(authControllerProvider.future);

      expect(user, isNull);
      expect(store.token, 'stored-token');
      expect(store.clears, 0);
    },
  );

  test('starts logged out when the secure store cannot be read', () async {
    final store = FakeTokenStore('stored-token')
      ..readFailure = const StorageFailure(code: FailureCode.storageRead);
    final container = _container(store, FakeAuthRepository());

    expect(await container.read(authControllerProvider.future), isNull);
  });

  test('login stores the token and loads the user', () async {
    final store = FakeTokenStore();
    final repo = FakeAuthRepository();
    final container = _container(store, repo);
    await container.read(authControllerProvider.future);

    await container
        .read(authControllerProvider.notifier)
        .login('player@strumsight.app', 'sixstrings');

    final state = container.read(authControllerProvider);
    expect(state.value, isA<AuthUser>());
    expect(store.token, 'fake-token');
    expect(repo.loginCalls, 1);
  });

  test('a pending login cannot sign back in after logout', () async {
    final repo = _DelayedLoginRepository();
    final store = FakeTokenStore();
    final container = _container(store, repo);
    await container.read(authControllerProvider.future);

    final pending = container
        .read(authControllerProvider.notifier)
        .login('delayed@strumsight.app', 'sixstrings');
    await repo.loginStarted.future;
    await container.read(authControllerProvider.notifier).logout();
    repo.releaseLogin.complete();
    await pending;

    expect(container.read(authControllerProvider).value, isNull);
    expect(store.token, isNull);
  });

  test('a slower first login cannot replace a newer login', () async {
    final repo = _RacingLoginRepository();
    final store = FakeTokenStore();
    final container = _container(store, repo);
    await container.read(authControllerProvider.future);
    final controller = container.read(authControllerProvider.notifier);

    final first = controller.login('first@strumsight.app', 'sixstrings');
    await repo.firstLoginStarted.future;
    await controller.login('second@strumsight.app', 'sixstrings');
    repo.releaseFirstLogin.complete();
    await first;

    expect(container.read(authControllerProvider).value?.id, 2);
    expect(store.token, 'second-token');
  });

  test('a pending session restore cannot undo logout', () async {
    final repo = _DelayedMeRepository();
    final store = FakeTokenStore('stored-token');
    final container = _container(store, repo);

    final restore = container.read(authControllerProvider.future);
    await repo.meStarted.future;
    await container.read(authControllerProvider.notifier).logout();
    repo.releaseMe.complete();
    await restore;

    expect(container.read(authControllerProvider).value, isNull);
    expect(store.token, isNull);
  });

  test('logout clears a token write that was already in flight', () async {
    final store = _DelayedWriteTokenStore();
    final container = _container(store, FakeAuthRepository());
    await container.read(authControllerProvider.future);
    final controller = container.read(authControllerProvider.notifier);

    final login = controller.login('player@strumsight.app', 'sixstrings');
    await store.writeStarted.future;
    final logout = controller.logout();
    store.releaseWrite.complete();
    await Future.wait([login, logout]);

    expect(container.read(authControllerProvider).value, isNull);
    expect(store.token, isNull);
  });

  test('a slow logout clear cannot erase a newer login token', () async {
    final store = _DelayedClearTokenStore('stored-token');
    final repo = FakeAuthRepository();
    final container = _container(store, repo);
    await container.read(authControllerProvider.future);
    final controller = container.read(authControllerProvider.notifier);

    final logout = controller.logout();
    await store.clearStarted.future;
    repo.user = const AuthUser(id: 2, email: 'new@strumsight.app');
    final login = controller.login('new@strumsight.app', 'sixstrings');
    store.releaseClear.complete();
    await Future.wait([logout, login]);

    expect(container.read(authControllerProvider).value?.id, 2);
    expect(store.token, 'fake-token');
  });

  test('login failure surfaces an AppFailure and stores no token', () async {
    final store = FakeTokenStore();
    final repo = FakeAuthRepository()
      ..loginFailure = const AuthenticationFailure();
    final container = _container(store, repo);
    await container.read(authControllerProvider.future);

    await container
        .read(authControllerProvider.notifier)
        .login('player@strumsight.app', 'wrongpass');

    final state = container.read(authControllerProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<AppFailure>());
    expect(
      (state.error! as AppFailure).code,
      FailureCode.authInvalidCredentials,
    );
    expect(store.token, isNull);
    expect(store.writes, 0);
  });

  test('network login failure is retryable and never leaks Dio', () async {
    final store = FakeTokenStore();
    final repo = FakeAuthRepository()..loginFailure = const NetworkFailure();
    final container = _container(store, repo);
    await container.read(authControllerProvider.future);

    await container
        .read(authControllerProvider.notifier)
        .login('player@strumsight.app', 'sixstrings');

    final error = container.read(authControllerProvider).error;
    expect(error, isA<NetworkFailure>());
    expect((error! as AppFailure).retryable, isTrue);
  });

  test('a token-storage failure does not fail the sign-in', () async {
    // Explicit, documented decision (§4.5): this run stays signed in; only the
    // "stay logged in across restarts" part is lost — and it is logged.
    final sink = RecordingLogSink();
    final store = FakeTokenStore()
      ..writeFailure = const StorageFailure(code: FailureCode.storageWrite);
    final container = _container(store, FakeAuthRepository(), sink: sink);
    await container.read(authControllerProvider.future);

    await container
        .read(authControllerProvider.notifier)
        .login('player@strumsight.app', 'sixstrings');

    expect(container.read(authControllerProvider).value, isA<AuthUser>());
    expect(store.token, isNull); // the write really did fail
    expect(sink.joined, contains('auth.token_write_failed'));
    expect(sink.joined, contains(FailureCode.storageWrite));
  });

  test(
    'a real account client uses the token in memory after write failure',
    () async {
      final adapter = _LoginAdapter();
      final store = FakeTokenStore()
        ..writeFailure = const StorageFailure(code: FailureCode.storageWrite);
      final container = _container(
        store,
        FakeAuthRepository(),
        useHttpRepository: true,
        dioFactory: DioFactory(
          baseUrl: 'https://api.strumsight.test',
          appVersion: 'test',
          logger: const NoopAppLogger(),
          adapter: adapter,
          correlationIdGenerator: () => 'correlation',
        ),
      );
      await container.read(authControllerProvider.future);

      await container
          .read(authControllerProvider.notifier)
          .login('player@strumsight.app', 'sixstrings');

      expect(container.read(authControllerProvider).value, isA<AuthUser>());
      expect(store.token, isNull);
      expect(adapter.requests, hasLength(2));
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer ephemeral-token',
      );
    },
  );

  test('never logs the token, the password or the e-mail', () async {
    final sink = RecordingLogSink();
    final store = FakeTokenStore('stored-token')
      ..writeFailure = const StorageFailure(code: FailureCode.storageWrite);
    final repo = FakeAuthRepository()
      ..meFailure = const AuthenticationFailure();
    final container = _container(store, repo, sink: sink);
    await container.read(authControllerProvider.future);

    await container
        .read(authControllerProvider.notifier)
        .login('player@strumsight.app', 'sup3r-secret-pass');

    expect(sink.lines, isNotEmpty);
    expect(sink.joined, isNot(contains('fake-token')));
    expect(sink.joined, isNot(contains('stored-token')));
    expect(sink.joined, isNot(contains('sup3r-secret-pass')));
    expect(sink.joined, isNot(contains('player@strumsight.app')));
  });

  test(
    'an unknown repository failure is reported, never treated as a session',
    () async {
      final store = FakeTokenStore();
      final repo = FakeAuthRepository()..meFailure = const UnknownFailure();
      final container = _container(store, repo);
      await container.read(authControllerProvider.future);

      await container
          .read(authControllerProvider.notifier)
          .login('player@strumsight.app', 'sixstrings');

      final state = container.read(authControllerProvider);
      expect(state.hasError, isTrue);
      expect(state.value, isNull);
      // The unusable token is dropped so the next launch starts clean.
      expect(store.token, isNull);
      expect(store.clears, 1);
    },
  );

  test('register logs the user in', () async {
    final store = FakeTokenStore();
    final repo = FakeAuthRepository();
    final container = _container(store, repo);
    await container.read(authControllerProvider.future);

    await container
        .read(authControllerProvider.notifier)
        .register('new@strumsight.app', 'sixstrings');

    expect(container.read(authControllerProvider).value, isA<AuthUser>());
    expect(repo.registerCalls, 1);
    expect(store.token, 'fake-token');
  });

  test('register conflict surfaces the email-taken code', () async {
    final repo = FakeAuthRepository()
      ..registerFailure = const ValidationFailure(
        code: FailureCode.validationEmailTaken,
      );
    final container = _container(FakeTokenStore(), repo);
    await container.read(authControllerProvider.future);

    await container
        .read(authControllerProvider.notifier)
        .register('taken@strumsight.app', 'sixstrings');

    final error = container.read(authControllerProvider).error;
    expect((error! as AppFailure).code, FailureCode.validationEmailTaken);
  });

  test('logout clears the token and returns to logged out', () async {
    final store = FakeTokenStore('stored-token');
    final container = _container(store, FakeAuthRepository());
    await container.read(authControllerProvider.future);

    await container.read(authControllerProvider.notifier).logout();

    expect(container.read(authControllerProvider).value, isNull);
    expect(store.token, isNull);
    expect(store.clears, greaterThan(0));
  });

  test(
    'session invalidation clears a live session without reentrancy',
    () async {
      final store = FakeTokenStore('stored-token');
      final container = _container(store, FakeAuthRepository());
      await container.read(authControllerProvider.future);

      await container.read(authControllerProvider.notifier).invalidateSession();

      expect(container.read(authControllerProvider).value, isNull);
      expect(store.token, isNull);
    },
  );

  test('concurrent session invalidations clear the token only once', () async {
    final store = FakeTokenStore('stored-token');
    final container = _container(store, FakeAuthRepository());
    await container.read(authControllerProvider.future);
    final notifier = container.read(authControllerProvider.notifier);

    await Future.wait([
      notifier.invalidateSession(),
      notifier.invalidateSession(),
    ]);

    expect(container.read(authControllerProvider).value, isNull);
    expect(store.clears, 1);
  });

  test('a late 401 from an old token cannot expire a new session', () async {
    final adapter = _DelayedUnauthorizedAdapter();
    final store = FakeTokenStore('old-session-token');
    final repo = FakeAuthRepository();
    final container = _container(
      store,
      repo,
      dioFactory: DioFactory(
        baseUrl: 'https://api.strumsight.test',
        appVersion: 'test',
        logger: const NoopAppLogger(),
        adapter: adapter,
        correlationIdGenerator: () => 'correlation',
      ),
    );
    await container.read(authControllerProvider.future);

    final oldRequest = container
        .read(accountApiClientProvider)!
        .getJson<bool>('/settings', decode: (_) => true);
    await adapter.requestStarted.future;

    final controller = container.read(authControllerProvider.notifier);
    await controller.logout();
    repo.user = const AuthUser(id: 2, email: 'new@strumsight.app');
    await controller.login('new@strumsight.app', 'sixstrings');
    expect(store.token, 'fake-token');

    adapter.releaseResponse.complete();
    expect(
      (await oldRequest).failureOrNull?.code,
      FailureCode.authSessionExpired,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(container.read(authControllerProvider).value?.id, 2);
    expect(store.token, 'fake-token');
  });

  test('logout still logs out when the secure store fails to clear', () async {
    final sink = RecordingLogSink();
    final store = FakeTokenStore('stored-token')
      ..clearFailure = const StorageFailure();
    final container = _container(store, FakeAuthRepository(), sink: sink);
    await container.read(authControllerProvider.future);

    await container.read(authControllerProvider.notifier).logout();

    expect(container.read(authControllerProvider).value, isNull);
    expect(sink.joined, contains('auth.token_clear_failed'));
  });
}
