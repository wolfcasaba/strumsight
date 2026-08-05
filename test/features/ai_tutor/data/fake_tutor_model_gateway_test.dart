import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/fake_tutor_model_gateway.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/tutor_model_event.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/tutor_model_request.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_ids.dart';

import 'tutor_model_gateway_contract_test.dart';

TutorModelRequest _makeRequest({
  String id = 'req-1',
  int sequence = 0,
  String conversationId = 'conv-1',
  String message = 'Hello',
}) {
  return TutorModelRequest(
    requestId: TutorRequestId(id),
    sequence: sequence,
    conversationId: TutorConversationId(conversationId),
    message: message,
  );
}

void main() {
  group('FakeTutorModelGateway timeout matrix', () {
    group('first-event timeout', () {
      test('below — event arrives before timeout', () async {
        final clock = FakeClock();
        final gateway = FakeTutorModelGateway(
          clock: clock,
          script: const [
            FakeGatewayDelay(Duration(seconds: 4)),
            FakeGatewayDelta('Hello', sequence: 1),
            FakeGatewayDone(sequence: 2),
          ],
        );
        final result = await gateway.start(_makeRequest());
        final stream = withTimeouts(
          result.valueOrNull!,
          clock,
          firstEventTimeout: const Duration(seconds: 5),
        );

        final future = expectLater(
          stream,
          emitsInOrder(<dynamic>[
            isA<TutorModelDelta>(),
            isA<TutorModelDone>(),
          ]),
        );
        clock.advance(const Duration(seconds: 4));
        await future;
      });

      test('above — timeout fires before first event', () async {
        final clock = FakeClock();
        final gateway = FakeTutorModelGateway(
          clock: clock,
          script: const [
            FakeGatewayDelay(Duration(seconds: 6)),
            FakeGatewayDelta('Hello', sequence: 1),
            FakeGatewayDone(sequence: 2),
          ],
        );
        final result = await gateway.start(_makeRequest());
        final stream = withTimeouts(
          result.valueOrNull!,
          clock,
          firstEventTimeout: const Duration(seconds: 5),
        );

        final future = expectLater(stream, emitsError(isA<TimeoutException>()));
        clock.advance(const Duration(seconds: 5));
        await future;
      });
    });

    group('inactivity timeout', () {
      test('below — events arrive within inactivity window', () async {
        final clock = FakeClock();
        final gateway = FakeTutorModelGateway(
          clock: clock,
          script: const [
            FakeGatewayDelay(Duration(seconds: 3)),
            FakeGatewayDelta('Hello', sequence: 1),
            FakeGatewayDelay(Duration(seconds: 4)),
            FakeGatewayDelta('World', sequence: 2),
            FakeGatewayDone(sequence: 3),
          ],
        );
        final result = await gateway.start(_makeRequest());
        final stream = withTimeouts(
          result.valueOrNull!,
          clock,
          inactivityTimeout: const Duration(seconds: 5),
          totalTimeout: const Duration(minutes: 1),
        );

        final future = expectLater(
          stream,
          emitsInOrder(<dynamic>[
            isA<TutorModelDelta>(),
            isA<TutorModelDelta>(),
            isA<TutorModelDone>(),
          ]),
        );
        clock.advance(const Duration(seconds: 3));
        clock.advance(const Duration(seconds: 4));
        await future;
      });

      test('above — inactivity timeout fires between events', () async {
        final clock = FakeClock();
        final gateway = FakeTutorModelGateway(
          clock: clock,
          script: const [
            FakeGatewayDelay(Duration(seconds: 3)),
            FakeGatewayDelta('Hello', sequence: 1),
            FakeGatewayDelay(Duration(seconds: 7)),
            FakeGatewayDelta('World', sequence: 2),
            FakeGatewayDone(sequence: 3),
          ],
        );
        final result = await gateway.start(_makeRequest());
        final stream = withTimeouts(
          result.valueOrNull!,
          clock,
          inactivityTimeout: const Duration(seconds: 5),
          totalTimeout: const Duration(minutes: 1),
        );

        final future = expectLater(stream, emitsError(isA<TimeoutException>()));
        clock.advance(const Duration(seconds: 3));
        await Future<void>.delayed(Duration.zero);
        clock.advance(const Duration(seconds: 5));
        await future;
      });
    });

    group('total timeout', () {
      test('below — completes before total timeout', () async {
        final clock = FakeClock();
        final gateway = FakeTutorModelGateway(
          clock: clock,
          script: const [
            FakeGatewayDelay(Duration(seconds: 5)),
            FakeGatewayDelta('Hello', sequence: 1),
            FakeGatewayDelay(Duration(seconds: 5)),
            FakeGatewayDelta('World', sequence: 2),
            FakeGatewayDone(sequence: 3),
          ],
        );
        final result = await gateway.start(_makeRequest());
        final stream = withTimeouts(
          result.valueOrNull!,
          clock,
          inactivityTimeout: const Duration(seconds: 20),
          totalTimeout: const Duration(seconds: 25),
        );

        final future = expectLater(
          stream,
          emitsInOrder(<dynamic>[
            isA<TutorModelDelta>(),
            isA<TutorModelDelta>(),
            isA<TutorModelDone>(),
          ]),
        );
        clock.advance(const Duration(seconds: 5));
        clock.advance(const Duration(seconds: 5));
        await future;
      });

      test('above — total timeout fires', () async {
        final clock = FakeClock();
        final gateway = FakeTutorModelGateway(
          clock: clock,
          script: const [
            FakeGatewayDelay(Duration(seconds: 5)),
            FakeGatewayDelta('Hello', sequence: 1),
            FakeGatewayDelay(Duration(seconds: 5)),
            FakeGatewayDelta('World', sequence: 2),
            FakeGatewayDelay(Duration(seconds: 10)),
            FakeGatewayDone(sequence: 3),
          ],
        );
        final result = await gateway.start(_makeRequest());
        final stream = withTimeouts(
          result.valueOrNull!,
          clock,
          inactivityTimeout: const Duration(seconds: 20),
          totalTimeout: const Duration(seconds: 15),
        );

        final future = expectLater(stream, emitsError(isA<TimeoutException>()));
        clock.advance(const Duration(seconds: 5));
        await Future<void>.delayed(Duration.zero);
        clock.advance(const Duration(seconds: 10));
        await future;
      });
    });
  });

  group('FakeTutorModelGateway edge cases', () {
    test('late event after terminal is silently dropped', () async {
      final clock = FakeClock();
      final gateway = FakeTutorModelGateway(
        clock: clock,
        script: const [
          FakeGatewayDelta('Hello', sequence: 1),
          FakeGatewayDone(sequence: 2),
          FakeGatewayDelay(Duration(seconds: 10)),
          FakeGatewayDelta('Late', sequence: 3),
        ],
      );
      final result = await gateway.start(_makeRequest());
      final stream = result.valueOrNull!;

      final future = expectLater(
        stream,
        emitsInOrder(<dynamic>[isA<TutorModelDelta>(), isA<TutorModelDone>()]),
      );
      clock.advance(Duration.zero);
      await future;

      clock.advance(const Duration(seconds: 10));
      await Future<void>.delayed(Duration.zero);
    });

    test('duplicate terminal emits only first', () async {
      final clock = FakeClock();
      final gateway = FakeTutorModelGateway(
        clock: clock,
        script: const [
          FakeGatewayDelta('Hello', sequence: 1),
          FakeGatewayDone(sequence: 2),
          FakeGatewayDelay(Duration(seconds: 5)),
          FakeGatewayDone(sequence: 3),
        ],
      );
      final result = await gateway.start(_makeRequest());
      final stream = result.valueOrNull!;

      final future = expectLater(
        stream,
        emitsInOrder(<dynamic>[isA<TutorModelDelta>(), isA<TutorModelDone>()]),
      );
      clock.advance(Duration.zero);
      await future;
    });

    test('malformed events pass through', () async {
      final clock = FakeClock();
      final gateway = FakeTutorModelGateway(
        clock: clock,
        script: const [
          FakeGatewayDelta('', sequence: 0),
          FakeGatewayDelta('ok', sequence: 0),
          FakeGatewayDone(sequence: 1),
        ],
      );
      final result = await gateway.start(_makeRequest());
      final stream = result.valueOrNull!;

      final future = expectLater(
        stream,
        emitsInOrder(<dynamic>[
          isA<TutorModelDelta>().having((e) => e.delta, 'delta', ''),
          isA<TutorModelDelta>().having((e) => e.delta, 'delta', 'ok'),
          isA<TutorModelDone>(),
        ]),
      );
      clock.advance(Duration.zero);
      await future;
    });
  });

  group('FakeClock', () {
    test('starts at epoch', () {
      final clock = FakeClock();
      expect(clock.now(), DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('advance moves time forward', () {
      final clock = FakeClock();
      clock.advance(const Duration(seconds: 5));
      expect(clock.now(), DateTime.fromMillisecondsSinceEpoch(5000));
    });

    test('fires scheduled callbacks when deadline reached', () {
      final clock = FakeClock();
      var fired = false;
      clock.createTimer(
        DateTime.fromMillisecondsSinceEpoch(5000),
        () => fired = true,
      );
      clock.advance(const Duration(seconds: 5));
      expect(fired, isTrue);
    });

    test('does not fire callbacks before deadline', () {
      final clock = FakeClock();
      var fired = false;
      clock.createTimer(
        DateTime.fromMillisecondsSinceEpoch(10000),
        () => fired = true,
      );
      clock.advance(const Duration(seconds: 5));
      expect(fired, isFalse);
    });

    test('cancelled timer does not fire', () {
      final clock = FakeClock();
      var fired = false;
      final timer = clock.createTimer(
        DateTime.fromMillisecondsSinceEpoch(5000),
        () => fired = true,
      );
      timer.cancel();
      clock.advance(const Duration(seconds: 5));
      expect(fired, isFalse);
    });
  });
}
