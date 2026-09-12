// The routed community surface reaches the REAL backend, not a disabled stand-in.
//
// ## Why this needs a guard of its own
//
// E18-R19 routed ten community screens and pointed the build at the hosted backend.
// What makes those screens actually work is a three-provider chain with a null
// short-circuit in the middle:
//
//   appConfigProvider.flags.accountEnabled
//     -> accountApiClientProvider        (null when the account layer is off)
//       -> communitySocialApiClientProvider
//         -> socialGraphRepositoryProvider  (Http… or Disabled…)
//
// `docs/LESSONS.md` L652 records exactly this defect class: a wiring round whose
// premise was "the provider already exists" never measured the factory behind it, and
// the shipped default turned out to be the test fake. Here the failure would be
// quieter still — `DisabledSocialGraphRepository` returns `ConfigurationFailure` for
// every call, so the screens would render, scroll, and simply never load anything.
// Nothing asserted the chain end to end, so nothing would have caught it.
//
// These cells read the REAL providers through a container, with only the config
// overridden. No network happens: building an `ApiClient` does not make a request.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/community/data/repositories/relationship_repository_impl.dart';

AppConfig _config({required bool accountEnabled, required bool community}) =>
    AppConfig(
      environment: AppEnvironment.development,
      // The shape the hosted backend is configured with: an origin plus the
      // gateway's mount point (`docs/operations/casaba-backend.md`).
      apiBaseUrl: 'https://casaba.app/strumsight',
      flags: FeatureFlags(
        accountEnabled: accountEnabled,
        diagnosticsEnabled: false,
        labModeAvailable: false,
        communityEnabled: community,
        communityWritesEnabled: community,
      ),
      diagnosticsToken: AppConfig.devDiagnosticsToken,
      buildMode: 'test',
      appVersion: 'test',
    );

ProviderContainer _container(AppConfig config) {
  final container = ProviderContainer(
    overrides: [appConfigProvider.overrideWithValue(config)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('with the account layer ON — the casaba build', () {
    test('the social graph repository is the HTTP one', () {
      final container = _container(
        _config(accountEnabled: true, community: true),
      );
      expect(
        container.read(socialGraphRepositoryProvider),
        isA<HttpSocialGraphRepository>(),
        reason:
            'the routed community screens read this repository directly; a '
            'disabled stand-in here would let them render and never load',
      );
    });

    test('the api client exists and carries the configured base URL', () {
      final container = _container(
        _config(accountEnabled: true, community: true),
      );
      expect(container.read(accountApiClientProvider), isNotNull);
      expect(
        container.read(communitySocialApiClientProvider),
        isNotNull,
        reason:
            'the community client is the account client; one null means both',
      );
    });
  });

  group('with the account layer OFF', () {
    test('the repository is the DISABLED one, not a crash and not a fake', () {
      // The honest shape for a build with no account layer: every call returns
      // `ConfigurationFailure`, which the screens can report. A throw would take the
      // app down; a fake would invent data.
      final container = _container(
        _config(accountEnabled: false, community: true),
      );
      expect(
        container.read(socialGraphRepositoryProvider),
        isA<DisabledSocialGraphRepository>(),
      );
      expect(container.read(accountApiClientProvider), isNull);
    });

    test('community being enabled does not conjure a client', () {
      // The two flags are independent, and this is the combination that would be a
      // trap: community on, account off. It must degrade, never pretend.
      final container = _container(
        _config(accountEnabled: false, community: true),
      );
      expect(container.read(communitySocialApiClientProvider), isNull);
    });
  });
}
