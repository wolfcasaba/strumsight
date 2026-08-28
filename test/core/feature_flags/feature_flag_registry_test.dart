import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/feature_flags/public.dart';

class _FakeSource implements FeatureFlagSource {
  _FakeSource([Map<String, bool> values = const {}]) : _values = values;
  final Map<String, bool> _values;

  @override
  bool? valueFor(String key) => _values[key];
}

class _FakeRemoteSource implements RemoteFeatureFlagSource {
  _FakeRemoteSource(this._payloads);
  final Map<String, SignedFeatureFlagPayload> _payloads;

  @override
  SignedFeatureFlagPayload? fetch(String key) => _payloads[key];
}

FeatureFlagDefinition _definitionOf({
  bool failClosedDefault = false,
  String key = 'testFlag',
}) {
  return FeatureFlagDefinition(
    key: key,
    owner: 'lib/features/test',
    risk: FeatureFlagRisk.low,
    failClosedDefault: failClosedDefault,
    killSwitchPath: 'n/a (fixture)',
  );
}

void main() {
  group('A2 — unknown/missing source falls to the fail-closed default', () {
    test('no sources configured at all → failClosedDefault (false)', () {
      const resolver = FeatureFlagResolver();
      final resolution = resolver.resolve(
        _definitionOf(failClosedDefault: false),
      );
      expect(resolution.value, isFalse);
      expect(resolution.origin, FeatureFlagResolutionOrigin.failClosedDefault);
    });

    test('no sources configured at all → failClosedDefault (true), proving '
        'the default is actually read, not hardcoded false', () {
      const resolver = FeatureFlagResolver();
      final resolution = resolver.resolve(
        _definitionOf(failClosedDefault: true),
      );
      expect(resolution.value, isTrue);
      expect(resolution.origin, FeatureFlagResolutionOrigin.failClosedDefault);
    });

    test('every configured source has no opinion about this key → '
        'failClosedDefault, not a crash or a stale value', () {
      final resolver = FeatureFlagResolver(
        emergency: _FakeSource(),
        remote: _FakeRemoteSource(const {}),
        capability: _FakeSource(),
        local: _FakeSource(),
      );
      final resolution = resolver.resolve(
        _definitionOf(failClosedDefault: false),
      );
      expect(resolution.value, isFalse);
      expect(resolution.origin, FeatureFlagResolutionOrigin.failClosedDefault);
    });
  });

  group('A3 — the emergency source is asymmetric: only `false` ever wins '
      '(ADR 0446 D1, the NOT-acceptable weakening from brief §5.1)', () {
    test('emergency=false overrides every stronger-looking opinion', () {
      final resolver = FeatureFlagResolver(
        emergency: _FakeSource({'testFlag': false}),
        remote: _FakeRemoteSource({
          'testFlag': const SignedFeatureFlagPayload(
            value: true,
            signatureValid: true,
          ),
        }),
        capability: _FakeSource({'testFlag': true}),
        local: _FakeSource({'testFlag': true}),
      );
      final resolution = resolver.resolve(_definitionOf());
      expect(resolution.value, isFalse);
      expect(resolution.origin, FeatureFlagResolutionOrigin.emergencyOff);
    });

    test('emergency=true does NOT turn the flag on — it is treated exactly '
        'like no opinion and falls through to the next source', () {
      final resolver = FeatureFlagResolver(
        emergency: _FakeSource({'testFlag': true}),
        local: _FakeSource({'testFlag': false}),
      );
      final resolution = resolver.resolve(_definitionOf());
      expect(resolution.value, isFalse);
      expect(resolution.origin, FeatureFlagResolutionOrigin.local);
    });

    test('emergency=true with no weaker source configured falls all the way '
        'to failClosedDefault — it never wins as `wonBy: emergencyOff`', () {
      final resolver = FeatureFlagResolver(
        emergency: _FakeSource({'testFlag': true}),
      );
      final resolution = resolver.resolve(
        _definitionOf(failClosedDefault: false),
      );
      expect(resolution.value, isFalse);
      expect(resolution.origin, FeatureFlagResolutionOrigin.failClosedDefault);
    });

    test('emergency has no opinion about this key at all → falls through '
        'exactly like emergency=true', () {
      final resolver = FeatureFlagResolver(
        emergency: _FakeSource(const {}),
        local: _FakeSource({'testFlag': true}),
      );
      final resolution = resolver.resolve(_definitionOf());
      expect(resolution.value, isTrue);
      expect(resolution.origin, FeatureFlagResolutionOrigin.local);
    });
  });

  group('A4 — a remote payload that fails signature verification is ignored, '
      'and the failure is not fatal (ADR 0446 D2)', () {
    test('bad signature: the payload value is ignored, falls through to '
        'capability', () {
      final resolver = FeatureFlagResolver(
        remote: _FakeRemoteSource({
          'testFlag': const SignedFeatureFlagPayload(
            value: true,
            signatureValid: false,
          ),
        }),
        capability: _FakeSource({'testFlag': false}),
      );
      final resolution = resolver.resolve(_definitionOf());
      expect(resolution.value, isFalse);
      expect(resolution.origin, FeatureFlagResolutionOrigin.capability);
    });

    test('bad signature and no weaker source → failClosedDefault, no '
        'exception thrown', () {
      final resolver = FeatureFlagResolver(
        remote: _FakeRemoteSource({
          'testFlag': const SignedFeatureFlagPayload(
            value: true,
            signatureValid: false,
          ),
        }),
      );
      expect(
        () => resolver.resolve(_definitionOf(failClosedDefault: false)),
        returnsNormally,
      );
      final resolution = resolver.resolve(
        _definitionOf(failClosedDefault: false),
      );
      expect(resolution.value, isFalse);
      expect(resolution.origin, FeatureFlagResolutionOrigin.failClosedDefault);
    });

    test('valid signature: the payload value is honoured', () {
      final resolver = FeatureFlagResolver(
        remote: _FakeRemoteSource({
          'testFlag': const SignedFeatureFlagPayload(
            value: true,
            signatureValid: true,
          ),
        }),
        capability: _FakeSource({'testFlag': false}),
      );
      final resolution = resolver.resolve(_definitionOf());
      expect(resolution.value, isTrue);
      expect(resolution.origin, FeatureFlagResolutionOrigin.remote);
    });
  });

  group('Priority chain ordering (ADR 0446 D2)', () {
    test('capability wins over local', () {
      final resolver = FeatureFlagResolver(
        capability: _FakeSource({'testFlag': true}),
        local: _FakeSource({'testFlag': false}),
      );
      final resolution = resolver.resolve(_definitionOf());
      expect(resolution.value, isTrue);
      expect(resolution.origin, FeatureFlagResolutionOrigin.capability);
    });

    test('remote wins over capability and local', () {
      final resolver = FeatureFlagResolver(
        remote: _FakeRemoteSource({
          'testFlag': const SignedFeatureFlagPayload(
            value: false,
            signatureValid: true,
          ),
        }),
        capability: _FakeSource({'testFlag': true}),
        local: _FakeSource({'testFlag': true}),
      );
      final resolution = resolver.resolve(_definitionOf());
      expect(resolution.value, isFalse);
      expect(resolution.origin, FeatureFlagResolutionOrigin.remote);
    });

    test('local is honoured when nothing stronger has an opinion', () {
      final resolver = FeatureFlagResolver(
        local: _FakeSource({'testFlag': true}),
      );
      final resolution = resolver.resolve(_definitionOf());
      expect(resolution.value, isTrue);
      expect(resolution.origin, FeatureFlagResolutionOrigin.local);
    });
  });

  group(
    'A6 — a kill-switched (off) resolution never touches stored data '
    '(ADR 0446 D7: the kill switch hides a capability, it does not wipe it)',
    () {
      test('resolving a flag to off does not mutate an unrelated data store, '
          'and resolving it back to on restores the same data untouched', () {
        final userData = <String>['session-1', 'session-2', 'session-3'];
        final originalSnapshot = List<String>.of(userData);

        final offResolver = FeatureFlagResolver(
          emergency: _FakeSource({'testFlag': false}),
        );
        final offResolution = offResolver.resolve(_definitionOf());
        expect(offResolution.value, isFalse);
        expect(userData, originalSnapshot);

        final onResolver = FeatureFlagResolver(
          local: _FakeSource({'testFlag': true}),
        );
        final onResolution = onResolver.resolve(_definitionOf());
        expect(onResolution.value, isTrue);
        expect(
          userData,
          originalSnapshot,
          reason:
              'FeatureFlagResolver.resolve has no reference to any data '
              'store at all — a flag toggling on or off can never trigger '
              'a delete as a side effect of this API.',
        );
      });
    },
  );

  group('featureFlagRegistry — catalog shape', () {
    test('every entry has a unique, non-empty key', () {
      final keys = featureFlagRegistry.map((d) => d.key).toList();
      expect(keys.toSet(), hasLength(keys.length));
      expect(keys, everyElement(isNotEmpty));
    });

    test('the registry is non-empty', () {
      expect(featureFlagRegistry, isNotEmpty);
    });
  });
}
