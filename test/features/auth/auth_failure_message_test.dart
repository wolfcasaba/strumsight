import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/features/auth/presentation/auth_failure_message.dart';
import 'package:strumsight/l10n/app_localizations.dart';

void main() {
  late AppLocalizations en;
  late AppLocalizations hu;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    hu = await AppLocalizations.delegate.load(const Locale('hu'));
  });

  test('auth codes map to the credentials message', () {
    for (final code in [
      FailureCode.authInvalidCredentials,
      FailureCode.authSessionExpired,
      FailureCode.authForbidden,
    ]) {
      expect(
        authFailureMessage(en, AuthenticationFailure(code: code)),
        en.authErrorInvalidCredentials,
        reason: code,
      );
    }
  });

  test('the conflict code maps to the e-mail-taken message', () {
    expect(
      authFailureMessage(
        en,
        const ValidationFailure(code: FailureCode.validationEmailTaken),
      ),
      en.authErrorEmailTaken,
    );
  });

  test('every network code maps to the connectivity message', () {
    for (final code in [
      FailureCode.networkUnavailable,
      FailureCode.networkTimeout,
      FailureCode.networkServer,
      FailureCode.networkTls,
    ]) {
      expect(
        authFailureMessage(en, NetworkFailure(code: code)),
        en.authErrorNetwork,
        reason: code,
      );
    }
  });

  test('anything unmapped falls back to the generic message', () {
    expect(authFailureMessage(en, const UnknownFailure()), en.authErrorUnknown);
    expect(authFailureMessage(en, const StorageFailure()), en.authErrorUnknown);
    // Not even an AppFailure — the UI must still show a localised sentence.
    expect(authFailureMessage(en, Exception('boom')), en.authErrorUnknown);
    expect(authFailureMessage(en, null), en.authErrorUnknown);
  });

  test('the message is localised, not a hardcoded English string', () {
    final message = authFailureMessage(hu, const AuthenticationFailure());
    expect(message, hu.authErrorInvalidCredentials);
    expect(message, isNot(en.authErrorInvalidCredentials));
  });

  test('the failure code itself never reaches the user', () {
    for (final failure in <AppFailure>[
      const NetworkFailure(),
      const AuthenticationFailure(),
      const UnknownFailure(),
    ]) {
      expect(authFailureMessage(en, failure), isNot(contains(failure.code)));
    }
  });
}
