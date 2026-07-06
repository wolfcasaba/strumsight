import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/auth/data/auth_repository.dart';
import 'package:music_theory/features/auth/data/token_store.dart';
import 'package:music_theory/features/auth/model/auth_user.dart';
import 'package:music_theory/features/auth/providers/auth_providers.dart';

import '../../support/fake_auth.dart';

ProviderContainer _container(FakeTokenStore store, FakeAuthRepository repo) {
  final container = ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(store),
      authRepositoryProvider.overrideWithValue(repo),
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
      ..meError = const AuthException(AuthErrorKind.invalidCredentials);
    final container = _container(store, repo);
    final user = await container.read(authControllerProvider.future);
    expect(user, isNull);
    expect(store.token, isNull); // cleared
  });

  test('login stores the token and loads the user', () async {
    final store = FakeTokenStore();
    final repo = FakeAuthRepository();
    final container = _container(store, repo);
    await container.read(authControllerProvider.future);

    await container.read(authControllerProvider.notifier).login(
          'player@strumsight.app',
          'sixstrings',
        );

    final state = container.read(authControllerProvider);
    expect(state.value, isA<AuthUser>());
    expect(store.token, 'fake-token');
    expect(repo.loginCalls, 1);
  });

  test('login failure surfaces an AuthException and stores no token', () async {
    final store = FakeTokenStore();
    final repo = FakeAuthRepository()
      ..loginError = const AuthException(AuthErrorKind.invalidCredentials);
    final container = _container(store, repo);
    await container.read(authControllerProvider.future);

    await container
        .read(authControllerProvider.notifier)
        .login('player@strumsight.app', 'wrongpass');

    final state = container.read(authControllerProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<AuthException>());
    expect((state.error as AuthException).kind,
        AuthErrorKind.invalidCredentials);
    expect(store.token, isNull);
  });

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

  test('logout clears the token and returns to logged out', () async {
    final store = FakeTokenStore('stored-token');
    final container = _container(store, FakeAuthRepository());
    await container.read(authControllerProvider.future);

    await container.read(authControllerProvider.notifier).logout();

    expect(container.read(authControllerProvider).value, isNull);
    expect(store.token, isNull);
    expect(store.clears, greaterThan(0));
  });
}
