import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/logging/debug_app_logger.dart';

void main() {
  late List<String> lines;
  DebugAppLogger logger({LogLevel minLevel = LogLevel.debug, bool on = true}) =>
      DebugAppLogger(sink: lines.add, minLevel: minLevel, enabled: on);

  setUp(() => lines = <String>[]);

  test('emits an event with its fields', () {
    logger().info('auth.sign_in', fields: {'code': 'ok', 'attempt': 1});
    expect(lines.single, '[info] auth.sign_in {code=ok, attempt=1}');
  });

  test('redacts field values before they reach the sink', () {
    logger().warning(
      'auth.sign_in_failed',
      fields: {'token': 'abc123', 'email': 'player@strumsight.app'},
    );
    expect(lines.single, isNot(contains('abc123')));
    expect(lines.single, isNot(contains('player@strumsight.app')));
    expect(lines.single, contains('[redacted]'));
  });

  test('redacts the event name itself', () {
    logger().info('login for player@strumsight.app');
    expect(lines.single, isNot(contains('player@strumsight.app')));
  });

  test('logs only the type of an error object, never its message', () {
    logger().warning(
      'diagnostics.upload_failed',
      error: StateError('POST https://api.example/x?token=abc123 failed'),
    );
    expect(lines.single, isNot(contains('abc123')));
    expect(lines.single, contains('StateError'));
  });

  test('drops records below the minimum level', () {
    final log = logger(minLevel: LogLevel.warning);
    log.debug('a');
    log.info('b');
    log.warning('c');
    log.error('d', error: 'boom', stackTrace: StackTrace.empty);
    expect(
      lines.where((l) => l.startsWith('[')).map((l) => l.split(' ').first),
      ['[warning]', '[error]'],
    );
  });

  test('emits nothing at all when disabled (release default)', () {
    final log = logger(on: false);
    log.info('x');
    log.error('y', error: 'boom', stackTrace: StackTrace.current);
    expect(lines, isEmpty);
  });

  test('the no-op logger swallows everything without a sink', () {
    const log = NoopAppLogger();
    log.debug('a');
    log.info('b');
    log.warning('c');
    log.error('d', error: 'e', stackTrace: StackTrace.empty);
    expect(lines, isEmpty);
  });
}
