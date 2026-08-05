import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/ai_tutor/data/dto/tutor_stream_dto.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/remote_tutor_model_gateway.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/tutor_model_event.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/tutor_model_request.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_ids.dart';

String _frame(Map<String, Object?> frame) => jsonEncode(frame);

TutorModelRequest _request({
  String requestId = 'req-1',
  int sequence = 0,
  String conversationId = 'conv-1',
  String message = 'Hello',
}) {
  return TutorModelRequest(
    requestId: TutorRequestId(requestId),
    sequence: sequence,
    conversationId: TutorConversationId(conversationId),
    message: message,
  );
}

TutorStreamFrame _accept(TutorStreamFrameParser parser, String payload) {
  final outcome = parser.parse(payload);
  expect(outcome, isA<TutorFrameAccepted>());
  return (outcome as TutorFrameAccepted).frame;
}

TutorFrameRejected _reject(TutorStreamFrameParser parser, String payload) {
  final outcome = parser.parse(payload);
  expect(outcome, isA<TutorFrameRejected>());
  return outcome as TutorFrameRejected;
}

void _expectDropped(TutorStreamFrameParser parser, String payload) {
  expect(parser.parse(payload), isA<TutorFrameDropped>());
}

final class _FakeTransport implements TutorStreamTransport {
  Stream<String>? streamToServe;
  AppResult<Stream<String>>? openFailure;
  AppResult<void> healthResult = const Success(null);
  int openCalls = 0;
  int cancelCalls = 0;
  ({String conversationId, String message, String requestId, int sequence})?
  lastRequest;

  @override
  Future<AppResult<Stream<String>>> openTurnStream({
    required String requestId,
    required int sequence,
    required String conversationId,
    required String message,
  }) async {
    openCalls++;
    lastRequest = (
      requestId: requestId,
      sequence: sequence,
      conversationId: conversationId,
      message: message,
    );
    if (openFailure case final failure?) {
      return failure;
    }
    return Success(streamToServe ?? const Stream.empty());
  }

  @override
  void cancelActiveStream() {
    cancelCalls++;
  }

  @override
  Future<AppResult<void>> health() async => healthResult;
}

void main() {
  group('TutorStreamFrameParser', () {
    test('accepts strictly sequential frames and tracks the next seq', () {
      final parser = TutorStreamFrameParser();
      expect(parser.nextSequence, 0);
      expect(
        _accept(parser, _frame({'type': 'started', 'seq': 0})),
        isA<TutorStreamStarted>(),
      );
      expect(parser.nextSequence, 1);
      final delta = _accept(
        parser,
        _frame({'type': 'delta', 'seq': 1, 'text': 'a'}),
      );
      expect(delta, isA<TutorStreamDelta>());
      expect((delta as TutorStreamDelta).text, 'a');
      expect(parser.nextSequence, 2);
      expect(
        _accept(parser, _frame({'type': 'complete', 'seq': 2})),
        isA<TutorStreamComplete>(),
      );
      expect(parser.isClosed, isTrue);
    });

    test('rejects a sequence gap', () {
      final parser = TutorStreamFrameParser();
      _accept(parser, _frame({'type': 'started', 'seq': 0}));
      _accept(parser, _frame({'type': 'delta', 'seq': 1, 'text': 'a'}));
      final rejected = _reject(
        parser,
        _frame({'type': 'delta', 'seq': 3, 'text': 'b'}),
      );
      expect(rejected.code, TutorTransportErrorCode.sequenceGap);
      // After a rejection the parser stays closed — no frame is processed.
      _expectDropped(parser, _frame({'type': 'complete', 'seq': 4}));
    });

    test('rejects a gap in the very first frame', () {
      final parser = TutorStreamFrameParser();
      final rejected = _reject(
        parser,
        _frame({'type': 'delta', 'seq': 1, 'text': 'a'}),
      );
      expect(rejected.code, TutorTransportErrorCode.sequenceGap);
    });

    test('drops an adjacent duplicate with an identical payload', () {
      final parser = TutorStreamFrameParser();
      _accept(parser, _frame({'type': 'started', 'seq': 0}));
      final payload = _frame({'type': 'delta', 'seq': 1, 'text': 'a'});
      _accept(parser, payload);
      _expectDropped(parser, payload);
      // The stream continues normally after the dropped duplicate.
      _accept(parser, _frame({'type': 'complete', 'seq': 2}));
    });

    test('rejects a repeated seq carrying a different payload', () {
      final parser = TutorStreamFrameParser();
      _accept(parser, _frame({'type': 'started', 'seq': 0}));
      _accept(parser, _frame({'type': 'delta', 'seq': 1, 'text': 'a'}));
      final rejected = _reject(
        parser,
        _frame({'type': 'delta', 'seq': 1, 'text': 'DIFFERENT'}),
      );
      expect(rejected.code, TutorTransportErrorCode.sequenceGap);
    });

    test('rejects a stale seq that is not an adjacent duplicate', () {
      final parser = TutorStreamFrameParser();
      _accept(parser, _frame({'type': 'started', 'seq': 0}));
      final firstDelta = _frame({'type': 'delta', 'seq': 1, 'text': 'a'});
      _accept(parser, firstDelta);
      _accept(parser, _frame({'type': 'delta', 'seq': 2, 'text': 'b'}));
      // Same payload as the original seq-1 frame, but not adjacent to the
      // last processed frame: out-of-order delivery is a controlled failure.
      final rejected = _reject(parser, firstDelta);
      expect(rejected.code, TutorTransportErrorCode.sequenceGap);
    });

    test('rejects malformed JSON', () {
      final parser = TutorStreamFrameParser();
      expect(
        _reject(parser, 'this is not json').code,
        TutorTransportErrorCode.malformed,
      );
    });

    test('rejects non-object JSON payloads', () {
      for (final payload in const ['[1, 2]', '"text"', '42']) {
        final parser = TutorStreamFrameParser();
        expect(
          _reject(parser, payload).code,
          TutorTransportErrorCode.malformed,
        );
      }
    });

    test('rejects unknown frame types', () {
      final parser = TutorStreamFrameParser();
      final rejected = _reject(parser, _frame({'type': 'bogus', 'seq': 0}));
      expect(rejected.code, TutorTransportErrorCode.malformed);
    });

    test('rejects missing or invalid type/seq fields', () {
      for (final payload in [
        _frame({'seq': 0}), // missing type
        _frame({'type': 'delta'}), // missing seq
        _frame({'type': 'delta', 'seq': 'one', 'text': 'a'}),
        _frame({'type': 'delta', 'seq': -1, 'text': 'a'}),
      ]) {
        final parser = TutorStreamFrameParser();
        expect(
          _reject(parser, payload).code,
          TutorTransportErrorCode.malformed,
        );
      }
    });

    test('rejects type-specific field violations', () {
      for (final payload in [
        _frame({'type': 'delta', 'seq': 0}), // missing text
        _frame({'type': 'delta', 'seq': 0, 'text': 5}),
        _frame({'type': 'tool_call', 'seq': 0, 'name': 'n'}), // missing ids
        _frame({'type': 'usage', 'seq': 0, 'tokens': 'many'}),
        _frame({'type': 'failure', 'seq': 0, 'code': 'x'}), // missing message
      ]) {
        final parser = TutorStreamFrameParser();
        expect(
          _reject(parser, payload).code,
          TutorTransportErrorCode.malformed,
        );
      }
    });

    test('accepts tool_call, usage and failure frames', () {
      final parser = TutorStreamFrameParser();
      final toolCall = _accept(
        parser,
        _frame({
          'type': 'tool_call',
          'seq': 0,
          'tool_call_id': 'tc-1',
          'name': 'metronome',
          'arguments': '{"bpm":60}',
        }),
      );
      expect(toolCall, isA<TutorStreamToolCall>());
      expect((toolCall as TutorStreamToolCall).toolCallId, 'tc-1');
      expect(toolCall.name, 'metronome');
      expect(toolCall.arguments, '{"bpm":60}');
      final usage = _accept(
        parser,
        _frame({'type': 'usage', 'seq': 1, 'tokens': 12}),
      );
      expect((usage as TutorStreamUsage).tokens, 12);
      final failure = _accept(
        parser,
        _frame({
          'type': 'failure',
          'seq': 2,
          'code': 'provider_error',
          'message': 'redacted',
        }),
      );
      expect(failure, isA<TutorStreamFailure>());
      expect((failure as TutorStreamFailure).code, 'provider_error');
      expect(parser.isClosed, isTrue);
    });

    test('frame size matrix: under, at and over the limit', () {
      const limit = 64;
      // A fresh parser expects seq 0; the matrix varies only the payload
      // size, so every probe frame carries seq 0.
      final overhead = _frame({'type': 'delta', 'seq': 0, 'text': ''}).length;
      String payloadOf(int totalBytes) => _frame({
        'type': 'delta',
        'seq': 0,
        'text': 'a' * (totalBytes - overhead),
      });

      final parser = TutorStreamFrameParser(maxFrameBytes: limit);
      // Under the limit.
      expect(parser.parse(payloadOf(limit - 1)), isA<TutorFrameAccepted>());
      // Exactly at the limit.
      final parserAtLimit = TutorStreamFrameParser(maxFrameBytes: limit);
      expect(parserAtLimit.parse(payloadOf(limit)), isA<TutorFrameAccepted>());
      // Over the limit.
      final parserOver = TutorStreamFrameParser(maxFrameBytes: limit);
      expect(
        parserOver.parse(payloadOf(limit + 1)),
        isA<TutorFrameRejected>().having(
          (r) => r.code,
          'code',
          TutorTransportErrorCode.frameTooLarge,
        ),
      );
    });

    test('drops every frame after the terminal one', () {
      final parser = TutorStreamFrameParser();
      _accept(parser, _frame({'type': 'started', 'seq': 0}));
      _accept(parser, _frame({'type': 'complete', 'seq': 1}));
      _expectDropped(parser, _frame({'type': 'complete', 'seq': 1}));
      _expectDropped(parser, _frame({'type': 'delta', 'seq': 2, 'text': 'x'}));
    });
  });

  group('RemoteTutorModelGateway', () {
    test('maps happy-path frames onto the R13 event hierarchy', () async {
      final transport = _FakeTransport()
        ..streamToServe = Stream.fromIterable([
          _frame({'type': 'started', 'seq': 0}),
          _frame({'type': 'delta', 'seq': 1, 'text': 'Hel'}),
          _frame({'type': 'delta', 'seq': 2, 'text': 'lo'}),
          _frame({
            'type': 'tool_call',
            'seq': 3,
            'tool_call_id': 'tc-1',
            'name': 'metronome',
            'arguments': '{"bpm":60}',
          }),
          _frame({'type': 'usage', 'seq': 4, 'tokens': 12}),
          _frame({'type': 'complete', 'seq': 5}),
        ]);
      final gateway = RemoteTutorModelGateway(transport: transport);

      final result = await gateway.start(_request());
      final stream = result.valueOrNull;
      expect(stream, isNotNull);
      // started/usage are control frames: they never surface as events.
      await expectLater(
        stream,
        emitsInOrder(const [
          TutorModelDelta(sequence: 1, delta: 'Hel'),
          TutorModelDelta(sequence: 2, delta: 'lo'),
          TutorModelToolCall(
            sequence: 3,
            toolCallId: 'tc-1',
            name: 'metronome',
            arguments: '{"bpm":60}',
          ),
          TutorModelDone(sequence: 5),
        ]),
      );
      expect(transport.openCalls, 1);
      expect(transport.lastRequest, (
        requestId: 'req-1',
        sequence: 0,
        conversationId: 'conv-1',
        message: 'Hello',
      ));
      expect(gateway.isRunning, isFalse);
    });

    test('a sequence gap becomes a controlled transport failure', () async {
      // Reviewer mutation: disabling the gap detection emits the seq-3 delta
      // instead of the error and turns this test red.
      final transport = _FakeTransport()
        ..streamToServe = Stream.fromIterable([
          _frame({'type': 'started', 'seq': 0}),
          _frame({'type': 'delta', 'seq': 1, 'text': 'a'}),
          _frame({'type': 'delta', 'seq': 3, 'text': 'b'}),
          _frame({'type': 'complete', 'seq': 4}),
        ]);
      final gateway = RemoteTutorModelGateway(transport: transport);

      final result = await gateway.start(_request());
      await expectLater(
        result.valueOrNull,
        emitsInOrder([
          const TutorModelDelta(sequence: 1, delta: 'a'),
          isA<TutorModelError>()
              .having(
                (e) => e.code,
                'code',
                TutorTransportErrorCode.sequenceGap,
              )
              .having((e) => e.sequence, 'sequence', 2),
          emitsDone,
        ]),
      );
    });

    test(
      'an out-of-order frame becomes a controlled transport failure',
      () async {
        final transport = _FakeTransport()
          ..streamToServe = Stream.fromIterable([
            _frame({'type': 'started', 'seq': 0}),
            _frame({'type': 'delta', 'seq': 1, 'text': 'a'}),
            _frame({'type': 'delta', 'seq': 2, 'text': 'b'}),
            _frame({'type': 'delta', 'seq': 1, 'text': 'a'}),
          ]);
        final gateway = RemoteTutorModelGateway(transport: transport);

        final result = await gateway.start(_request());
        await expectLater(
          result.valueOrNull,
          emitsInOrder([
            const TutorModelDelta(sequence: 1, delta: 'a'),
            const TutorModelDelta(sequence: 2, delta: 'b'),
            isA<TutorModelError>().having(
              (e) => e.code,
              'code',
              TutorTransportErrorCode.sequenceGap,
            ),
            emitsDone,
          ]),
        );
      },
    );

    test('a duplicate frame is dropped idempotently', () async {
      final duplicate = _frame({'type': 'delta', 'seq': 1, 'text': 'a'});
      final transport = _FakeTransport()
        ..streamToServe = Stream.fromIterable([
          _frame({'type': 'started', 'seq': 0}),
          duplicate,
          duplicate,
          _frame({'type': 'delta', 'seq': 2, 'text': 'b'}),
          _frame({'type': 'complete', 'seq': 3}),
        ]);
      final gateway = RemoteTutorModelGateway(transport: transport);

      final result = await gateway.start(_request());
      await expectLater(
        result.valueOrNull,
        emitsInOrder(const [
          TutorModelDelta(sequence: 1, delta: 'a'),
          TutorModelDelta(sequence: 2, delta: 'b'),
          TutorModelDone(sequence: 3),
        ]),
      );
    });

    test('a malformed frame becomes a controlled transport failure', () async {
      final transport = _FakeTransport()
        ..streamToServe = Stream.fromIterable([
          _frame({'type': 'started', 'seq': 0}),
          'this is not json',
        ]);
      final gateway = RemoteTutorModelGateway(transport: transport);

      final result = await gateway.start(_request());
      await expectLater(
        result.valueOrNull,
        emitsInOrder([
          isA<TutorModelError>().having(
            (e) => e.code,
            'code',
            TutorTransportErrorCode.malformed,
          ),
          emitsDone,
        ]),
      );
    });

    test('an oversized frame becomes a controlled transport failure', () async {
      const limit = 64;
      final overhead = _frame({'type': 'delta', 'seq': 1, 'text': ''}).length;
      final oversized = _frame({
        'type': 'delta',
        'seq': 1,
        'text': 'a' * (limit + 1 - overhead),
      });
      final transport = _FakeTransport()
        ..streamToServe = Stream.fromIterable([
          _frame({'type': 'started', 'seq': 0}),
          oversized,
        ]);
      final gateway = RemoteTutorModelGateway(
        transport: transport,
        maxFrameBytes: limit,
      );

      final result = await gateway.start(_request());
      await expectLater(
        result.valueOrNull,
        emitsInOrder([
          isA<TutorModelError>()
              .having(
                (e) => e.code,
                'code',
                TutorTransportErrorCode.frameTooLarge,
              )
              .having((e) => e.sequence, 'sequence', 1),
          emitsDone,
        ]),
      );
    });

    test('server failure frames pass through with their own code', () async {
      final transport = _FakeTransport()
        ..streamToServe = Stream.fromIterable([
          _frame({'type': 'started', 'seq': 0}),
          _frame({
            'type': 'failure',
            'seq': 1,
            'code': 'provider_error',
            'message': 'The AI service returned an error',
          }),
        ]);
      final gateway = RemoteTutorModelGateway(transport: transport);

      final result = await gateway.start(_request());
      await expectLater(
        result.valueOrNull,
        emitsInOrder(const [
          TutorModelError(
            sequence: 1,
            code: 'provider_error',
            message: 'The AI service returned an error',
          ),
        ]),
      );
    });

    test('a stream ending without a terminal frame is truncated', () async {
      final transport = _FakeTransport()
        ..streamToServe = Stream.fromIterable([
          _frame({'type': 'started', 'seq': 0}),
          _frame({'type': 'delta', 'seq': 1, 'text': 'a'}),
        ]);
      final gateway = RemoteTutorModelGateway(transport: transport);

      final result = await gateway.start(_request());
      await expectLater(
        result.valueOrNull,
        emitsInOrder([
          const TutorModelDelta(sequence: 1, delta: 'a'),
          isA<TutorModelError>()
              .having((e) => e.code, 'code', TutorTransportErrorCode.truncated)
              .having((e) => e.sequence, 'sequence', 2),
          emitsDone,
        ]),
      );
    });

    test('a raw stream error becomes a transport_stream_error event', () async {
      final controller = StreamController<String>();
      final transport = _FakeTransport()..streamToServe = controller.stream;
      final gateway = RemoteTutorModelGateway(transport: transport);

      final result = await gateway.start(_request());
      final events = <TutorModelEvent>[];
      result.valueOrNull!.listen(events.add);
      controller.add(_frame({'type': 'started', 'seq': 0}));
      controller.addError(Exception('boom'));
      await pumpEventQueue();

      expect(events, [
        isA<TutorModelError>()
            .having((e) => e.code, 'code', TutorTransportErrorCode.streamError)
            .having((e) => e.sequence, 'sequence', 1),
      ]);
      await controller.close();
    });

    test('cancel closes the event stream and aborts the transport', () async {
      final controller = StreamController<String>();
      final transport = _FakeTransport()..streamToServe = controller.stream;
      final gateway = RemoteTutorModelGateway(transport: transport);

      final result = await gateway.start(_request());
      final events = <TutorModelEvent>[];
      var done = false;
      result.valueOrNull!.listen(events.add, onDone: () => done = true);

      controller.add(_frame({'type': 'started', 'seq': 0}));
      controller.add(_frame({'type': 'delta', 'seq': 1, 'text': 'a'}));
      await pumpEventQueue();
      // The started control frame is not surfaced.
      expect(events, [const TutorModelDelta(sequence: 1, delta: 'a')]);

      gateway.cancel();
      await pumpEventQueue();
      expect(done, isTrue);
      expect(transport.cancelCalls, 1);
      expect(gateway.isRunning, isFalse);
      // Cancelling again is a no-op.
      gateway.cancel();
      expect(transport.cancelCalls, 1);
      await controller.close();
    });

    test('start fails while a session is already running', () async {
      final transport = _FakeTransport()
        ..streamToServe = StreamController<String>().stream;
      final gateway = RemoteTutorModelGateway(transport: transport);

      final first = await gateway.start(_request());
      expect(first.isSuccess, isTrue);
      final second = await gateway.start(_request());
      expect(second.isFailure, isTrue);
      expect(transport.openCalls, 1);
    });

    test('transport open failures pass through untouched', () async {
      final transport = _FakeTransport()
        ..openFailure = const Failure(
          NetworkFailure(code: FailureCode.networkUnavailable),
        );
      final gateway = RemoteTutorModelGateway(transport: transport);

      final result = await gateway.start(_request());
      expect(result.isFailure, isTrue);
      expect(result.failureOrNull!.code, FailureCode.networkUnavailable);
    });

    test('a retry after completion starts a fresh, complete stream', () async {
      List<String> lines() => [
        _frame({'type': 'started', 'seq': 0}),
        _frame({'type': 'delta', 'seq': 1, 'text': 'x'}),
        _frame({'type': 'complete', 'seq': 2}),
      ];

      final transport = _FakeTransport()
        ..streamToServe = Stream.fromIterable(lines());
      final gateway = RemoteTutorModelGateway(transport: transport);
      final request = _request(requestId: 'req-9', sequence: 4);

      final first = await gateway.start(request);
      await expectLater(
        first.valueOrNull,
        emitsInOrder(const [
          TutorModelDelta(sequence: 1, delta: 'x'),
          TutorModelDone(sequence: 2),
        ]),
      );

      // Same requestId/sequence: a retry opens a fresh stream with a fresh
      // parser state — nothing is duplicated or leaked from the first run.
      transport.streamToServe = Stream.fromIterable(lines());
      final second = await gateway.start(request);
      expect(second.isSuccess, isTrue);
      await expectLater(
        second.valueOrNull,
        emitsInOrder(const [
          TutorModelDelta(sequence: 1, delta: 'x'),
          TutorModelDone(sequence: 2),
        ]),
      );
      expect(transport.openCalls, 2);
      expect(transport.lastRequest!.requestId, 'req-9');
      expect(transport.lastRequest!.sequence, 4);
    });

    test('health delegates to the transport', () async {
      final transport = _FakeTransport();
      final gateway = RemoteTutorModelGateway(transport: transport);
      expect((await gateway.health()).isSuccess, isTrue);

      transport.healthResult = const Failure(NetworkFailure());
      expect((await gateway.health()).isFailure, isTrue);
    });
  });
}
