import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/components/feedback/failure_presentation.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/platform/microphone_permission.dart';
import 'package:strumsight/l10n/app_localizations.dart';

void main() {
  late AppLocalizations en;
  late AppLocalizations hu;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    hu = await AppLocalizations.delegate.load(const Locale('hu'));
  });

  group('§6.1 retry-visibility matrix (D5) — real, measured inputs', () {
    test('below the threshold: a permanently denied microphone permission '
        '(retryable: false) shows no retry, only the settings action (A4)', () {
      final failure = MicrophonePermissionState.permanentlyDenied.failure!;
      expect(failure.code, FailureCode.permissionMicrophoneDenied);
      expect(failure.retryable, isFalse);

      final presentation = SsFailurePresentation.from(en, failure);

      expect(presentation.hasAction(SsFailureActionKind.retry), isFalse);
      expect(presentation.hasAction(SsFailureActionKind.openSettings), isTrue);
    });

    test('at the threshold: an unmapped code with retryable: true shows retry, '
        'and the text is a human ARB string (A1)', () {
      const failure = NetworkFailure(
        code: 'diagnostics.unmapped_probe',
        retryable: true,
      );

      final presentation = SsFailurePresentation.from(en, failure);

      expect(presentation.hasAction(SsFailureActionKind.retry), isTrue);
      expect(presentation.message, en.dsFailureUnknownMessage);
    });

    test('above the threshold: network.unavailable with retryable: true shows '
        'retry AND a continue-offline action', () {
      const failure = NetworkFailure(
        code: FailureCode.networkUnavailable,
        retryable: true,
      );

      final presentation = SsFailurePresentation.from(en, failure);

      expect(presentation.hasAction(SsFailureActionKind.retry), isTrue);
      expect(
        presentation.hasAction(SsFailureActionKind.continueOffline),
        isTrue,
      );
    });

    test(
      'the same permission code with opposite retryable flags gives opposite '
      'retry decisions — proves the decision is NOT code-only',
      () {
        final denied = MicrophonePermissionState.denied.failure!;
        final permanentlyDenied =
            MicrophonePermissionState.permanentlyDenied.failure!;

        expect(denied.code, permanentlyDenied.code);
        expect(denied.retryable, isTrue);
        expect(permanentlyDenied.retryable, isFalse);

        final deniedPresentation = SsFailurePresentation.from(en, denied);
        final permanentPresentation = SsFailurePresentation.from(
          en,
          permanentlyDenied,
        );

        expect(deniedPresentation.hasAction(SsFailureActionKind.retry), isTrue);
        expect(
          permanentPresentation.hasAction(SsFailureActionKind.retry),
          isFalse,
        );
      },
    );
  });

  group('A3 — retry only for a retryable failure', () {
    test('retryable: false never produces a retry action', () {
      for (final failure in <AppFailure>[
        const AuthenticationFailure(),
        const StorageFailure(),
        const ConfigurationFailure(),
        const UnknownFailure(),
      ]) {
        final presentation = SsFailurePresentation.from(en, failure);
        expect(
          presentation.hasAction(SsFailureActionKind.retry),
          isFalse,
          reason: failure.code,
        );
      }
    });

    test('retryable: true always produces a retry action', () {
      for (final failure in <AppFailure>[
        const NetworkFailure(),
        const AudioFailure(),
        const CameraFailure(),
        const CancelledFailure(),
      ]) {
        final presentation = SsFailurePresentation.from(en, failure);
        expect(
          presentation.hasAction(SsFailureActionKind.retry),
          isTrue,
          reason: failure.code,
        );
      }
    });
  });

  group('A1 — no raw exception/toString reaches the presentation', () {
    test('an unrecognised code gets a human message, not the code itself', () {
      const failure = NetworkFailure(
        code: 'diagnostics.unmapped_probe',
        retryable: true,
      );

      final presentation = SsFailurePresentation.from(en, failure);

      expect(presentation.title, isNot(contains(failure.code)));
      expect(presentation.message, isNot(contains(failure.code)));
      expect(presentation.message, isNot(contains('Exception')));
      expect(presentation.message, isNot(contains('#0 ')));
      expect(presentation.message, isNot(contains('retryable:')));
      expect(presentation.message, isNot(equals(failure.toString())));
    });

    test('the FailureCode.unknown fallback is human, not the raw code', () {
      const failure = UnknownFailure();

      final presentation = SsFailurePresentation.from(en, failure);

      expect(presentation.message, isNot(contains(FailureCode.unknown)));
      expect(presentation.message, en.dsFailureUnknownMessage);
    });
  });

  group('A7 — every new string is localised (en != hu)', () {
    test('the same failure renders different text per locale', () {
      const failure = NetworkFailure(code: FailureCode.networkUnavailable);

      final enPresentation = SsFailurePresentation.from(en, failure);
      final huPresentation = SsFailurePresentation.from(hu, failure);

      expect(huPresentation.title, isNot(equals(enPresentation.title)));
      expect(huPresentation.message, isNot(equals(enPresentation.message)));
      expect(huPresentation.title, hu.dsFailureNetworkUnavailableTitle);
      expect(huPresentation.message, hu.dsFailureNetworkUnavailableMessage);
    });

    test('the permanently-denied settings action label is localised', () {
      final failure = MicrophonePermissionState.permanentlyDenied.failure!;

      final enPresentation = SsFailurePresentation.from(en, failure);
      final huPresentation = SsFailurePresentation.from(hu, failure);

      final enLabel = enPresentation.actions
          .firstWhere((a) => a.kind == SsFailureActionKind.openSettings)
          .label;
      final huLabel = huPresentation.actions
          .firstWhere((a) => a.kind == SsFailureActionKind.openSettings)
          .label;

      expect(huLabel, isNot(equals(enLabel)));
      expect(huLabel, hu.dsFailureOpenSettingsAction);
    });
  });

  group('§5.1 — cause and stackTrace never influence the presentation', () {
    test(
      'two failures that differ only in cause/stackTrace present identically',
      () {
        final withCause = NetworkFailure(
          code: FailureCode.networkUnavailable,
          cause: Exception('leaked internal detail: /api/v9/secret-path'),
          stackTrace: StackTrace.current,
        );
        const withoutCause = NetworkFailure(
          code: FailureCode.networkUnavailable,
        );

        final withCausePresentation = SsFailurePresentation.from(en, withCause);
        final withoutCausePresentation = SsFailurePresentation.from(
          en,
          withoutCause,
        );

        expect(withCausePresentation.title, withoutCausePresentation.title);
        expect(withCausePresentation.message, withoutCausePresentation.message);
        expect(withCausePresentation.message, isNot(contains('secret-path')));
      },
    );
  });

  test('every failure resolves to at least one action', () {
    for (final failure in <AppFailure>[
      const NetworkFailure(),
      const AuthenticationFailure(),
      const PermissionFailure(),
      const StorageFailure(),
      const AudioFailure(),
      const CameraFailure(),
      const MlFailure(),
      const ValidationFailure(),
      const ConfigurationFailure(),
      const CancelledFailure(),
      const UnknownFailure(),
    ]) {
      final presentation = SsFailurePresentation.from(en, failure);
      expect(presentation.actions, isNotEmpty, reason: failure.code);
    }
  });
}
