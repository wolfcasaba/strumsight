import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/fake_tutor_model_gateway.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/local_tutor_model_gateway_stub.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/tutor_model_event.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/tutor_model_request.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_ids.dart';

/// Wraps a source event stream with first-event, inactivity, and total
/// timeouts using an injected [FakeClock] for deterministic testing.
Stream<TutorModelEvent> withTimeouts(
  Stream<TutorModelEvent> source,
  FakeClock clock, {
  Duration firstEventTimeout = const Duration(seconds: 30),
  Duration inactivityTimeout = const Duration(seconds: 10),
  Duration totalTimeout = const Duration(minutes: 5),
}) {
  final wrapper = StreamController<TutorModelEvent>();
  var wrapperClosed = false;
  Timer? firstEventTimer;
  Timer? inactivityTimer;
  Timer? totalTimer;
  StreamSubscription<TutorModelEvent>? sourceSub;
  var firstEventReceived = false;

  void closeWrapper() {
    if (wrapperClosed) return;
    wrapperClosed = true;
    firstEventTimer?.cancel();
    inactivityTimer?.cancel();
    totalTimer?.cancel();
    sourceSub?.cancel();
    wrapper.close();
  }

  void resetInactivity() {
    inactivityTimer?.cancel();
    inactivityTimer = clock.createTimer(clock.now().add(inactivityTimeout), () {
      if (wrapperClosed) return;
      wrapper.addError(TimeoutException('Inactivity timeout'));
      closeWrapper();
    });
  }

  // Start the first-event timer
  firstEventTimer = clock.createTimer(clock.now().add(firstEventTimeout), () {
    if (wrapperClosed || firstEventReceived) return;
    wrapper.addError(TimeoutException('First event timeout'));
    closeWrapper();
  });

  // Start the total timeout timer
  totalTimer = clock.createTimer(clock.now().add(totalTimeout), () {
    if (wrapperClosed) return;
    wrapper.addError(TimeoutException('Total timeout'));
    closeWrapper();
  });

  sourceSub = source.listen(
    (event) {
      if (wrapperClosed) return;

      // Cancel the first-event timer when the first event arrives
      if (!firstEventReceived) {
        firstEventReceived = true;
        firstEventTimer?.cancel();
      }

      wrapper.add(event);
      resetInactivity();

      if (event is TutorModelDone) {
        closeWrapper();
      }
    },
    onError: (Object error, StackTrace stack) {
      if (wrapperClosed) return;
      wrapper.addError(error, stack);
      closeWrapper();
    },
    onDone: closeWrapper,
  );

  return wrapper.stream;
}

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
  group('TutorModelGateway contract', () {
    test('ordered events arrive in sequence', () async {
      final clock = FakeClock();
      final gateway = FakeTutorModelGateway(
        clock: clock,
        script: const [
          FakeGatewayDelta('Hello', sequence: 1),
          FakeGatewayDelta('World', sequence: 2),
          FakeGatewayDone(sequence: 3),
        ],
      );

      final result = await gateway.start(_makeRequest());
      final stream = result.valueOrNull!;

      final future = expectLater(
        stream,
        emitsInOrder(<dynamic>[
          isA<TutorModelDelta>().having((e) => e.delta, 'delta', 'Hello'),
          isA<TutorModelDelta>().having((e) => e.delta, 'delta', 'World'),
          isA<TutorModelDone>(),
        ]),
      );
      clock.advance(Duration.zero);
      await future;
    });

    test('duplicate terminal event is ignored', () async {
      final clock = FakeClock();
      final gateway = FakeTutorModelGateway(
        clock: clock,
        script: const [
          FakeGatewayDelta('Hello', sequence: 1),
          FakeGatewayDone(sequence: 2),
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

    test('cancel closes the stream', () async {
      final clock = FakeClock();
      final gateway = FakeTutorModelGateway(
        clock: clock,
        script: const [
          FakeGatewayDelta('Hello', sequence: 1),
          FakeGatewayDelay(Duration(seconds: 10)),
          FakeGatewayDelta('World', sequence: 2),
          FakeGatewayDone(sequence: 3),
        ],
      );

      final result = await gateway.start(_makeRequest());
      final stream = result.valueOrNull!;

      final events = <TutorModelEvent>[];
      final sub = stream.listen(events.add);

      clock.advance(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      gateway.cancel();
      await sub.asFuture<void>();

      expect(events, hasLength(1));
      expect(events.first, isA<TutorModelDelta>());
    });

    test('tool-call event is emitted', () async {
      final clock = FakeClock();
      final gateway = FakeTutorModelGateway(
        clock: clock,
        script: const [
          FakeGatewayToolCall('tc-1', 'get_chord_diagram', '{}', sequence: 1),
          FakeGatewayDone(sequence: 2),
        ],
      );

      final result = await gateway.start(_makeRequest());
      final stream = result.valueOrNull!;

      final future = expectLater(
        stream,
        emitsInOrder(<dynamic>[
          isA<TutorModelToolCall>().having(
            (e) => e.name,
            'name',
            'get_chord_diagram',
          ),
          isA<TutorModelDone>(),
        ]),
      );
      clock.advance(Duration.zero);
      await future;
    });

    test('malformed event is emitted without crash', () async {
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

    test('health returns success when operational', () async {
      final gateway = FakeTutorModelGateway(script: const []);
      final health = await gateway.health();
      expect(health, isA<Success<void>>());
    });
  });

  group('LocalTutorModelGatewayStub', () {
    test('start returns capability-unavailable failure', () async {
      final stub = LocalTutorModelGatewayStub();
      final result = await stub.start(_makeRequest());
      expect(result, isA<Failure<Stream<TutorModelEvent>>>());
      final failure = result.failureOrNull!;
      expect(failure.code, 'tutor.model_gateway.unavailable');
    });

    test('health returns capability-unavailable failure', () async {
      final stub = LocalTutorModelGatewayStub();
      final result = await stub.health();
      expect(result, isA<Failure<void>>());
      final failure = result.failureOrNull!;
      expect(failure.code, 'tutor.model_gateway.unavailable');
    });
  });
}
