// MEASUREMENT: does a base URL with a PATH PREFIX survive into the request?
//
// The hosted backend is not at the root of its host. It sits behind a Kong gateway
// at `https://casaba.app/strumsight`, so `STRUMSIGHT_API_URL` carries a path
// component for the first time — every previous value was an origin
// (`http://10.0.2.2:8000`, a tunnel host).
//
// That is a silent-failure shape worth measuring rather than assuming: HTTP clients
// differ on how they join a base URL that has a path with a request path that starts
// with `/`. URI resolution semantics (RFC 3986) say an absolute path REPLACES the
// base path, which would turn `/auth/me` into `https://casaba.app/auth/me` — and the
// gateway answers that with 401 at every path. The app would then show "sign-in
// failed" against a backend that is up, healthy and correct, and the cause would look
// like a credentials problem.
//
// This cell pins the behaviour the configuration relies on. If a Dio upgrade ever
// changes it, this fails here instead of in the field.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// The URI Dio would actually request for [path] under [baseUrl].
String composed(String baseUrl, String path) {
  final options = RequestOptions(baseUrl: baseUrl, path: path);
  return options.uri.toString();
}

void main() {
  group('a base URL with a path prefix', () {
    test('MEASURE: the prefix is kept, so the gateway mount point works', () {
      const base = 'https://casaba.app/strumsight';
      for (final path in const ['/auth/login', '/auth/me', '/settings']) {
        final uri = composed(base, path);
        // ignore: avoid_print
        print('$base + $path -> $uri');
        expect(
          uri,
          'https://casaba.app/strumsight$path',
          reason:
              'the prefix carries the gateway mount point; dropping it sends every '
              'request to a path the gateway answers with 401, and the app would '
              'report a credentials failure against a healthy backend',
        );
      }
    });

    test('a trailing slash on the base does not double up', () {
      expect(
        composed('https://casaba.app/strumsight/', '/auth/me'),
        'https://casaba.app/strumsight/auth/me',
      );
    });

    test(
      'a bare origin still works, so dev and tunnel builds are unaffected',
      () {
        expect(
          composed('http://10.0.2.2:8000', '/auth/me'),
          'http://10.0.2.2:8000/auth/me',
        );
      },
    );
  });
}
