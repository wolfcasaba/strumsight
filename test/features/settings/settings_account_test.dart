import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/auth/data/auth_repository.dart';
import 'package:music_theory/features/auth/data/token_store.dart';
import 'package:music_theory/features/live/providers/live_providers.dart';
import 'package:music_theory/main.dart';

import '../../support/fake_auth.dart';
import '../../support/fake_engines.dart';

/// Boot the app with fake auth and open the Settings tab. [token] non-null =>
/// a session is restored via the fake repository (logged in).
Future<void> _openSettings(WidgetTester tester, {String? token}) async {
  final engine = FakeStrumEngine();
  addTearDown(engine.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        strumEngineProvider.overrideWithValue(engine),
        tokenStoreProvider.overrideWithValue(FakeTokenStore(token)),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      ],
      child: const StrumSightApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Account section shows Sign in when logged out', (tester) async {
    await _openSettings(tester);

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.textContaining('sync your settings'), findsOneWidget);
  });

  testWidgets('Account section shows the email + Sign out when logged in',
      (tester) async {
    await _openSettings(tester, token: 'stored-token');

    expect(find.textContaining('player@strumsight.app'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });
}
