import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/network/network_failure_mapper.dart';

DioException _error({
  DioExceptionType type = DioExceptionType.badResponse,
  int? status,
  Object? error,
}) {
  final request = RequestOptions(path: '/resource');
  return DioException(
    requestOptions: request,
    response: status == null
        ? null
        : Response<void>(requestOptions: request, statusCode: status),
    type: type,
    error: error,
  );
}

void main() {
  test('maps every specified HTTP response to a controlled failure', () {
    expect(
      mapNetworkFailure(_error(status: 401)),
      isA<AuthenticationFailure>().having(
        (failure) => failure.code,
        'code',
        FailureCode.authSessionExpired,
      ),
    );
    expect(mapNetworkFailure(_error(status: 409)), isA<ValidationFailure>());
    expect(
      mapNetworkFailure(_error(status: 422)),
      isA<ValidationFailure>().having(
        (failure) => failure.code,
        'code',
        FailureCode.validationInvalidInput,
      ),
    );
    expect(
      mapNetworkFailure(_error(status: 500)),
      isA<NetworkFailure>().having(
        (failure) => failure.code,
        'code',
        FailureCode.networkServer,
      ),
    );
    expect(
      mapNetworkFailure(_error(status: 418)),
      isA<NetworkFailure>().having(
        (failure) => failure.code,
        'code',
        FailureCode.networkBadResponse,
      ),
    );
  });

  test('lets an operation specialize 401 and 409 without leaking Dio', () {
    final unauthorized = mapNetworkFailure(
      _error(status: 401),
      unauthorizedCode: FailureCode.authInvalidCredentials,
    );
    final conflict = mapNetworkFailure(
      _error(status: 409),
      conflictCode: FailureCode.validationEmailTaken,
    );

    expect(unauthorized.code, FailureCode.authInvalidCredentials);
    expect(conflict.code, FailureCode.validationEmailTaken);
  });

  test('maps timeout, certificate, and refused connection failures', () {
    expect(
      mapNetworkFailure(_error(type: DioExceptionType.receiveTimeout)).code,
      FailureCode.networkTimeout,
    );
    expect(
      mapNetworkFailure(_error(type: DioExceptionType.badCertificate)).code,
      FailureCode.networkTls,
    );
    expect(
      mapNetworkFailure(_error(type: DioExceptionType.connectionError)).code,
      FailureCode.networkUnavailable,
    );
    expect(
      mapNetworkFailure(
        _error(
          type: DioExceptionType.unknown,
          error: const HandshakeException('certificate verify failed'),
        ),
      ).code,
      FailureCode.networkTls,
    );
    expect(
      mapNetworkFailure(
        _error(
          type: DioExceptionType.unknown,
          error: const SocketException('Connection refused'),
        ),
      ).code,
      FailureCode.networkUnavailable,
    );
  });

  test('preserves a controlled failure raised before transport', () {
    const storage = StorageFailure(code: FailureCode.storageRead);
    final mapped = mapNetworkFailure(
      _error(type: DioExceptionType.unknown, error: storage),
    );

    expect(identical(mapped, storage), isTrue);
  });
}
