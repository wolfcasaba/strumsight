import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/logging/debug_app_logger.dart';
import 'package:strumsight/core/logging/logger_provider.dart';
import 'package:strumsight/features/auth/data/auth_repository.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/model/auth_user.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';

import '../../support/fake_auth.dart';

ProviderContainer _container(
  FakeTokenStore store,
  FakeAuthRepository repo, {
  RecordingLogSink? sink,
}) {
  final container = ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(store),
      authRepositoryProvider.overrideWithValue(repo),
      if (sink != null)
        appLoggerProvider.overrideWithValue(
          DebugAppLogger(sink: sink.call, enabled: true),
        ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
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
