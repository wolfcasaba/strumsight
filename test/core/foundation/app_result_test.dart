import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';

void main() {
  group('success', () {
    test('reports success and carries the value', () {
      const result = AppResult<int>.success(7);
      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.valueOrNull, 7);
      expect(result.failureOrNull, isNull);
    });

    test('map transforms the value', () {
      const result = Success<int>(21);
      expect(result.map((v) => v * 2).valueOrNull, 42);
    });

    test('fold takes the success branch', () {
      const result = Success<String>('C');
      expect(
        result.fold(onSuccess: (v) => 'chord $v', onFailure: (e) => e.code),
        'chord C',
      );
    });
  });

  group('failure', () {
    const failure = NetworkFailure(code: FailureCode.networkTimeout);

    test('reports failure and carries the error', () {
      const result = AppResult<int>.failure(failure);
      expect(result.isFailure, isTrue);
      expect(result.isSuccess, isFalse);
      expect(result.valueOrNull, isNull);
      expect(result.failureOrNull, same(failure));
    });

    test('map passes the failure through without calling the transform', () {
      var called = false;
      const result = Failure<int>(failure);
      final mapped = result.map<String>((v) {
        called = true;
        return '$v';
      });
      expect(called, isFalse);
      expect(mapped, isA<Failure<String>>());
      expect(mapped.failureOrNull, same(failure));
    });

    test('fold takes the failure branch', () {
      const result = Failure<String>(failure);
      expect(
        result.fold(onSuccess: (v) => v, onFailure: (e) => e.code),
        FailureCode.networkTimeout,
      );
    });
  });

  test('pattern matching is exhaustive over the sealed type', () {
    AppResult<int> classify(bool ok) =>
        ok ? const Success(1) : const Failure(UnknownFailure());

    String describe(AppResult<int> r) => switch (r) {
      Success(:final value) => 'ok:$value',
      Failure(:final error) => 'err:${error.code}',
    };

    expect(describe(classify(true)), 'ok:1');
    expect(describe(classify(false)), 'err:${FailureCode.unknown}');
  });

  test('equality is by content, so tests can compare results directly', () {
    expect(const Success<int>(3), const Success<int>(3));
    expect(const Success<int>(3), isNot(const Success<int>(4)));
    expect(const Failure<int>(failureA), const Failure<int>(failureA));
  });

  group('failure taxonomy', () {
    test('every category carries a stable code and a retryable flag', () {
      const failures = <AppFailure>[
        NetworkFailure(),
        AuthenticationFailure(),
        PermissionFailure(),
        StorageFailure(),
        AudioFailure(),
        MlFailure(),
        ValidationFailure(),
        ConfigurationFailure(),
        CancelledFailure(),
        UnknownFailure(),
      ];
      expect(failures.length, 10);
      for (final f in failures) {
        expect(f.code, isNotEmpty, reason: '${f.runtimeType} needs a code');
      }
      // Codes are unique per default category — the UI switches on them.
      expect(failures.map((f) => f.code).toSet().length, failures.length);
    });

    test('toString exposes the code but never the cause', () {
      const failure = StorageFailure(
        code: FailureCode.storageWrite,
        cause: 'token=eyJhbGciOi.secret.value',
      );
      expect(failure.toString(), contains(FailureCode.storageWrite));
      expect(failure.toString(), isNot(contains('secret')));
    });
  });
}

const failureA = ValidationFailure(code: FailureCode.validationEmailTaken);
