import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/log_redactor.dart';

void main() {
  group('sensitive field names', () {
    test('drops the value of anything token/password/secret shaped', () {
      final out = LogRedactor.fields({
        'password': 'sup3r-secret',
        'access_token': 'eyJhbGciOiJIUzI1NiJ9.body.sig',
        'X-Diag-Token': 'strumsight-lab-dev',
        'Authorization': 'Bearer abc.def.ghi',
        'apiKey': 'k-123',
        'refreshToken': 'r-123',
      });
      for (final entry in out.entries) {
        expect(entry.value, LogRedactor.redacted, reason: entry.key);
      }
    });

    test('keeps ordinary diagnostic fields intact', () {
      final out = LogRedactor.fields({
        'code': 'auth.invalid_credentials',
        'status': 401,
        'retryable': false,
        'attempt': 2,
      });
      expect(out['code'], 'auth.invalid_credentials');
      expect(out['status'], 401);
      expect(out['retryable'], false);
      expect(out['attempt'], 2);
    });

    test('matching ignores case and separators', () {
      expect(LogRedactor.isSensitiveKey('DIAG_TOKEN'), isTrue);
      expect(LogRedactor.isSensitiveKey('x-diag-token'), isTrue);
      expect(LogRedactor.isSensitiveKey('user.password'), isTrue);
      expect(LogRedactor.isSensitiveKey('chordLabel'), isFalse);
    });
  });

  group('free text', () {
    test('masks e-mail addresses', () {
      expect(
        LogRedactor.text('login failed for player@strumsight.app'),
        'login failed for ${LogRedactor.redactedEmail}',
      );
    });

    test('masks a JWT even in an unnamed field', () {
      final out =
          LogRedactor.fields({
                'note': 'got eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sIgNaTuRe ok',
              })['note']
              as String;
      expect(out, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
      expect(out, contains(LogRedactor.redactedToken));
    });

    test('masks a bearer header value', () {
      expect(
        LogRedactor.text('Authorization: Bearer abc123.def'),
        'Authorization: Bearer ${LogRedactor.redactedToken}',
      );
    });

    test('replaces oversized strings wholesale (base64 WAV guard)', () {
      final wav = 'UklGR' * 200; // ~1000 chars, base64-looking
      final out = LogRedactor.text(wav);
      expect(out, isNot(contains('UklGR')));
      expect(out, contains('chars]'));
    });
  });

  group('structured values', () {
    test('summarises long number lists instead of printing raw audio', () {
      final pcm = List<double>.filled(4096, 0.123);
      final out = LogRedactor.fields({'buffer': pcm})['buffer'];
      expect(out, '[redacted:4096 numbers]');
    });

    test('recurses into nested maps and lists', () {
      final out =
          LogRedactor.fields({
                'request': {
                  'headers': {'authorization': 'Bearer xyz'},
                  'user': 'player@strumsight.app',
                },
              })['request']
              as Map<String, Object?>;
      final headers = out['headers']! as Map<String, Object?>;
      expect(headers['authorization'], LogRedactor.redacted);
      expect(out['user'], LogRedactor.redactedEmail);
    });

    test('prints only the type of an arbitrary object', () {
      final out = LogRedactor.fields({
        'error': Exception('boom at /auth/login'),
      });
      expect(out['error'], '<_Exception>');
    });

    test('stops recursing past the depth cap', () {
      Object? nested = 'leaf';
      for (var i = 0; i < 8; i++) {
        nested = {'inner': nested};
      }
      // Must not throw or recurse without bound.
      expect(LogRedactor.fields({'root': nested}), isA<Map<String, Object?>>());
    });
  });
}
