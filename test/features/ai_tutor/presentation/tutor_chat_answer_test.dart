// E-R29a (2026-09-08 re-audit) — B1 and M2, measured on the PRODUCTION
// controller over a real `TutorOrchestrator` and a scripted stream
// transport. No widget, no socket: the seam under test is the one between
// the orchestrator's terminal state and what the conversation then holds.
//
// B1 (BLOCKER, functional half): a turn could complete without the student
// ever seeing the answer. The tutor's text was rendered ONLY by the
// streaming bubble, which the chat screen builds from
// `TutorTurnStatus.streaming` alone — so the moment the turn reached
// `completed`, the reply vanished and the conversation held nothing but the
// student's own question. `DefaultTutorChatController` now decodes the
// validated v1 envelope and appends it as a tutor message.
//
// M2 (MAJOR): the error banner's "Retry" was a silent no-op. `send()`
// clears `draft` the instant a turn is dispatched, and every terminal
// status is reached after that — so the old `retry()`'s `send()` fell
// straight through its own `text.isEmpty` guard: the button did nothing,
// said nothing, forever. The controller now remembers the submitted text.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/ai_tutor/application/context/context_purpose.dart';
import 'package:strumsight/features/ai_tutor/application/context/tutor_context_assembler.dart';
import 'package:strumsight/features/ai_tutor/application/controller/tutor_state.dart';
import 'package:strumsight/features/ai_tutor/application/orchestration/tutor_orchestrator.dart';
import 'package:strumsight/features/ai_tutor/application/prompts/prompt_template.dart';
import 'package:strumsight/features/ai_tutor/application/prompts/prompt_version.dart';
import 'package:strumsight/features/ai_tutor/application/prompts/tutor_prompt_builder.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_index.dart';
import 'package:strumsight/features/ai_tutor/data/knowledge/knowledge_retriever.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/fake_tutor_model_gateway.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/local_tutor_model_gateway_stub.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/tutor_model_event.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/tutor_model_gateway.dart';
import 'package:strumsight/features/ai_tutor/data/model_gateway/tutor_model_request.dart';
import 'package:strumsight/features/ai_tutor/data/repositories/local_tutor_conversation_repository.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_content_block.dart';
import 'package:strumsight/features/ai_tutor/domain/models/tutor_message.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_gateway_providers.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_privacy_providers.dart';
import 'package:strumsight/features/ai_tutor/presentation/providers/tutor_providers.dart';

import '../../../support/preference_store.dart';

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

const _bulletItems = <String>['Anchor the ring finger', 'Change on the and'];
const _question = 'Why is my G chord buzzing?';

/// One structurally valid v1 answer, in the three block shapes the schema's
/// own `answerBlocks` uses. `TutorOutputValidator` accepts it, so the turn
/// really does reach `TutorTurnStatus.completed` — the state whose answer
/// used to disappear.
String _answerOutput() => jsonEncode(<String, Object?>{
  'answerBlocks': <Object?>[
    <String, Object?>{'type': 'heading', 'text': 'Chord changes', 'level': 2},
    <String, Object?>{'type': 'text', 'text': 'Drop the metronome to 60.'},
    <String, Object?>{'type': 'bulletList', 'items': _bulletItems},
  ],
  'claims': <Object?>[],
  'actions': <Object?>[],
  'followUpSuggestions': <Object?>[],
  'safetyNotices': <Object?>[],
  'memoryCandidates': <Object?>[],
});

String _emptyAnswerOutput() => jsonEncode(<String, Object?>{
  'answerBlocks': <Object?>[],
  'claims': <Object?>[],
  'actions': <Object?>[],
  'followUpSuggestions': <Object?>[],
  'safetyNotices': <Object?>[],
  'memoryCandidates': <Object?>[],
});

/// The decoded form of [_answerOutput], as the bubble receives it.
List<TutorContentBlock> _expectedAnswerBlocks() => <TutorContentBlock>[
  TutorHeadingBlock(text: 'Chord changes', level: 2),
  TutorTextBlock(text: 'Drop the metronome to 60.'),
  TutorBulletListBlock(items: _bulletItems),
];

/// The production provider graph with two seams overridden: the boot
/// orchestrator (whose collaborators the turn orchestrator re-uses) and the
/// gateway factory, which stands in for the cloud transport with a script.
final class _Harness {
  _Harness({required this.scripts}) {
    orchestrator = TutorOrchestrator(
      contextAssembler: const TutorContextAssembler(),
      knowledgeRetriever: KnowledgeRetriever(
        index: const KnowledgeIndex.empty(),
      ),
      promptBuilder: TutorPromptBuilder(templateLoader: _TemplateLoader()),
      // Never used: the chat controller runs `withGatewayFactory` over this.
      gatewayForAttempt: (_) => LocalTutorModelGatewayStub(),
    );
    container = ProviderContainer(
      overrides: [
        ...preferenceOverrides(),
        tutorOrchestratorProvider.overrideWithValue(orchestrator),
        tutorModelGatewayFactoryProvider.overrideWithValue(_gateway),
        tutorConversationRepositoryProvider.overrideWithValue(
          LocalTutorConversationRepository(
            keyValueStore: InMemoryKeyValueStore(),
          ),
        ),
      ],
    );
    // The student granted model use — the request path is consent-gated by
    // construction (R9/1), so nothing dispatches without it.
    container.read(tutorConsentControllerProvider.notifier).grantModelUse();
    controller = container.read(tutorChatControllerProvider);
    _subscription = controller.states.listen((state) => lastState = state);
  }

  /// One script per gateway START, in call order — so a failing first turn
  /// and a succeeding retry are two entries, not one branchy script. The
  /// last entry repeats for any further attempt.
  final List<List<FakeGatewayStep>> scripts;

  late final TutorOrchestrator orchestrator;
  late final ProviderContainer container;
  late final TutorChatController controller;
  late final StreamSubscription<TutorChatState> _subscription;

  final List<FakeClock> clocks = <FakeClock>[];

  /// The prompt text each started turn actually carried — the one place the
  /// student's question becomes an outbound message.
  final List<String> startedMessages = <String>[];

  int gatewayCalls = 0;
  TutorChatState? lastState;

  TutorModelGateway _gateway(int attempt) {
    final clock = FakeClock();
    clocks.add(clock);
    final last = scripts.length - 1;
    final index = gatewayCalls < last ? gatewayCalls : last;
    gatewayCalls++;
    return _RecordingGateway(
      FakeTutorModelGateway(clock: clock, script: scripts[index]),
      startedMessages,
    );
  }

  /// Lets the dispatch chain reach the gateway, fires every scheduled model
  /// event, then lets validation and the terminal transition land.
  Future<void> drive() async {
    await _settle();
    for (final clock in clocks) {
      clock.advance(Duration.zero);
    }
    await _settle();
  }

  List<String> get userMessageTexts {
    return controller.messages
        .where((message) => message.role == TutorMessageRole.user)
        .map(_textOf)
        .toList();
  }

  void dispose() {
    unawaited(_subscription.cancel());
    container.dispose();
    unawaited(orchestrator.dispose());
  }
}

void main() {
  group('B1 — a completed turn actually appends the answer', () {
    test('the validated envelope becomes a tutor message with its '
        'blocks', () async {
      final harness = _Harness(
        scripts: <List<FakeGatewayStep>>[
          <FakeGatewayStep>[
            FakeGatewayDelta(_answerOutput(), sequence: 1),
            const FakeGatewayDone(sequence: 2),
          ],
        ],
      );
      addTearDown(harness.dispose);

      harness.controller.setDraft('How do I clean up my chord changes?');
      harness.controller.send();
      await harness.drive();

      expect(harness.controller.status, TutorTurnStatus.completed);
      expect(
        harness.controller.messages,
        hasLength(2),
        reason:
            'the question AND the answer — before E-R29a the conversation '
            "held only the student's own message",
      );

      final answer = harness.controller.messages.last;
      expect(answer.role, TutorMessageRole.tutor);
      expect(answer.deliveryState, TutorMessageDeliveryState.complete);
      expect(answer.blocks, _expectedAnswerBlocks());
      expect(
        harness.lastState?.messages,
        harness.controller.messages,
        reason: 'the emitted snapshot carries the answer, not just the field',
      );
    });

    test('an empty answerBlocks appends nothing rather than an empty '
        'bubble', () async {
      final harness = _Harness(
        scripts: <List<FakeGatewayStep>>[
          <FakeGatewayStep>[
            FakeGatewayDelta(_emptyAnswerOutput(), sequence: 1),
            const FakeGatewayDone(sequence: 2),
          ],
        ],
      );
      addTearDown(harness.dispose);

      harness.controller.setDraft('Anything?');
      harness.controller.send();
      await harness.drive();

      expect(harness.controller.status, TutorTurnStatus.completed);
      expect(harness.controller.messages, hasLength(1));
    });

    // `setOnline` replays the orchestrator's CURRENT state through the same
    // consume path, so one completed turn is consumed more than once. The
    // answer must not be appended again for that.
    test('re-consuming the same completed state does not duplicate the '
        'answer', () async {
      final harness = _Harness(
        scripts: <List<FakeGatewayStep>>[
          <FakeGatewayStep>[
            FakeGatewayDelta(_answerOutput(), sequence: 1),
            const FakeGatewayDone(sequence: 2),
          ],
        ],
      );
      addTearDown(harness.dispose);

      harness.controller.setDraft('How do I clean up my chord changes?');
      harness.controller.send();
      await harness.drive();
      expect(harness.controller.messages, hasLength(2));

      harness.controller.setOnline(false);
      harness.controller.setOnline(true);

      expect(harness.controller.messages, hasLength(2));
    });

    // A second turn in the same conversation must ask the SECOND question.
    // The orchestrator cached the rendered prompt in `_prompt ??=` — a cache
    // built for the ONE bounded repair attempt, which then outlived its
    // turn: every question after the first reached the model carrying the
    // FIRST question's prompt, so the student was answered about something
    // they had already asked. Measured at the gateway boundary, which is the
    // last place the text exists before it would leave the device.
    test('a second, different question is the one that actually reaches '
        'the gateway', () async {
      final harness = _Harness(
        scripts: <List<FakeGatewayStep>>[
          <FakeGatewayStep>[
            FakeGatewayDelta(_answerOutput(), sequence: 1),
            const FakeGatewayDone(sequence: 2),
          ],
        ],
      );
      addTearDown(harness.dispose);

      harness.controller.setDraft('How do I clean up my chord changes?');
      harness.controller.send();
      await harness.drive();

      harness.controller.setDraft('What is a barre chord?');
      harness.controller.send();
      await harness.drive();

      expect(harness.startedMessages, hasLength(2));
      expect(
        harness.startedMessages.first,
        contains('clean up my chord changes'),
      );
      expect(
        harness.startedMessages.last,
        contains('What is a barre chord'),
        reason: 'the second turn must not re-send the first turn\'s prompt',
      );
      expect(
        harness.startedMessages.last,
        isNot(contains('clean up my chord changes')),
      );
      expect(harness.controller.messages, hasLength(4));
    });

    // What the student saw in EVERY shipped build before E-R29a: the local
    // stub's `start()` fails, and the orchestrator turns that failure into
    // exactly this `TutorModelError` input. The honest state it produces is
    // `fallback` — the error banner plus the chat's own fallback AI-mode
    // notice. Not an answer, but never silence either.
    test('a gateway that cannot start ends in the visible fallback '
        'state', () async {
      final harness = _Harness(
        scripts: <List<FakeGatewayStep>>[
          const <FakeGatewayStep>[
            FakeGatewayError('tutor.model_gateway.unavailable', ''),
          ],
        ],
      );
      addTearDown(harness.dispose);

      harness.controller.setDraft(_question);
      harness.controller.send();
      await harness.drive();

      expect(harness.controller.status, TutorTurnStatus.fallback);
      expect(
        harness.controller.banners,
        contains(TutorBannerKind.error),
        reason: 'the failure is surfaced, not swallowed',
      );
      expect(
        tutorAiModeFor(status: harness.controller.status, isOnline: true),
        TutorAiMode.fallback,
        reason:
            'the chat AppBar indicator reads this mode and renders the '
            'explicit fallback notice next to the local badge',
      );
      expect(harness.controller.messages, hasLength(1));
    });
  });

  group('M2 — Retry re-sends the question that failed', () {
    test('a failed turn retried with an empty draft dispatches the same '
        'text', () async {
      final harness = _Harness(
        scripts: <List<FakeGatewayStep>>[
          const <FakeGatewayStep>[FakeGatewayError('tutor.model.boom', '')],
          <FakeGatewayStep>[
            FakeGatewayDelta(_answerOutput(), sequence: 1),
            const FakeGatewayDone(sequence: 2),
          ],
        ],
      );
      addTearDown(harness.dispose);

      harness.controller.setDraft(_question);
      harness.controller.send();
      await harness.drive();

      expect(harness.controller.status, TutorTurnStatus.fallback);
      expect(
        harness.controller.draft,
        isEmpty,
        reason: 'send() cleared it — this is exactly why retry did nothing',
      );

      harness.controller.retry();
      await harness.drive();

      expect(
        harness.gatewayCalls,
        greaterThan(1),
        reason: 'retry must actually dispatch a turn, not fall through',
      );
      expect(harness.controller.status, TutorTurnStatus.completed);
      expect(
        harness.userMessageTexts,
        <String>[_question, _question],
        reason: 'the re-sent question is the SAME question',
      );
    });

    test('a draft typed since the failure wins over the remembered '
        'text', () async {
      final harness = _Harness(
        scripts: <List<FakeGatewayStep>>[
          const <FakeGatewayStep>[FakeGatewayError('tutor.model.boom', '')],
          <FakeGatewayStep>[
            FakeGatewayDelta(_answerOutput(), sequence: 1),
            const FakeGatewayDone(sequence: 2),
          ],
        ],
      );
      addTearDown(harness.dispose);

      harness.controller.setDraft(_question);
      harness.controller.send();
      await harness.drive();

      harness.controller.setDraft('Actually: how do I mute string six?');
      harness.controller.retry();
      await harness.drive();

      expect(
        harness.userMessageTexts.last,
        'Actually: how do I mute string six?',
      );
    });

    test('retry before anything was ever sent stays a no-op', () async {
      final harness = _Harness(
        scripts: <List<FakeGatewayStep>>[const <FakeGatewayStep>[]],
      );
      addTearDown(harness.dispose);

      harness.controller.retry();
      await harness.drive();

      expect(harness.gatewayCalls, 0);
      expect(harness.controller.messages, isEmpty);
    });
  });

  // The decoder itself, without the pipeline: it is the one place a
  // provider's output shape meets the bubble's block model, so its edges
  // are worth pinning directly.
  group('tutorAnswerBlocksFrom', () {
    test('maps the three schema block shapes structurally', () {
      expect(tutorAnswerBlocksFrom(_answerOutput()), _expectedAnswerBlocks());
    });

    test('a bare string block is answer text', () {
      final blocks = tutorAnswerBlocksFrom(
        jsonEncode(<String, Object?>{
          'answerBlocks': <Object?>['Try a lighter touch.'],
        }),
      );

      expect(blocks, <TutorContentBlock>[
        TutorTextBlock(text: 'Try a lighter touch.'),
      ]);
    });

    // Preserved, never dropped: the bubble already renders unknown blocks
    // verbatim in a monospaced panel, which beats showing the student
    // nothing at all when a provider adds a shape we have not seen.
    test('an unknown block type is preserved as an unknown block', () {
      final blocks = tutorAnswerBlocksFrom(
        jsonEncode(<String, Object?>{
          'answerBlocks': <Object?>[
            <String, Object?>{
              'type': 'tablature',
              'frets': <int>[3, 2, 0],
            },
          ],
        }),
      );

      expect(blocks, hasLength(1));
      final block = blocks.single;
      expect(block, isA<TutorUnknownContentBlock>());
      expect((block as TutorUnknownContentBlock).originalType, 'tablature');
    });

    test('a heading with an out-of-range level degrades, it does not '
        'throw', () {
      final blocks = tutorAnswerBlocksFrom(
        jsonEncode(<String, Object?>{
          'answerBlocks': <Object?>[
            <String, Object?>{'type': 'heading', 'text': 'Nope', 'level': 9},
          ],
        }),
      );

      expect(blocks, hasLength(1));
      expect(blocks.single, isA<TutorUnknownContentBlock>());
    });

    test('plain prose that is not the envelope is still shown to the '
        'student', () {
      final blocks = tutorAnswerBlocksFrom('Just play it slower.');

      expect(blocks, <TutorContentBlock>[
        TutorTextBlock(text: 'Just play it slower.'),
      ]);
    });

    test('empty or block-less output appends nothing', () {
      expect(tutorAnswerBlocksFrom('   '), isEmpty);
      expect(tutorAnswerBlocksFrom(_emptyAnswerOutput()), isEmpty);
      expect(tutorAnswerBlocksFrom(jsonEncode(<String, Object?>{})), isEmpty);
    });
  });
}

String _textOf(TutorMessage message) =>
    (message.blocks.single as TutorTextBlock).text;

/// Delegates to the scripted gateway while recording what each turn started
/// with, so "which question actually went out" is measurable.
final class _RecordingGateway implements TutorModelGateway {
  _RecordingGateway(this._inner, this._starts);

  final TutorModelGateway _inner;
  final List<String> _starts;

  @override
  Future<AppResult<Stream<TutorModelEvent>>> start(TutorModelRequest request) {
    _starts.add(request.message);
    return _inner.start(request);
  }

  @override
  void cancel() => _inner.cancel();

  @override
  Future<AppResult<void>> health() => _inner.health();
}

final class _TemplateLoader implements PromptTemplateLoader {
  @override
  Future<PromptTemplate> load(ContextPurpose purpose) async => PromptTemplate(
    id: 'test.${purpose.name}',
    version: PromptVersion.v1,
    locale: 'en',
    intent: purpose,
    template: 'Return structured tutor output.',
    outputSchemaVersion: PromptVersion.v1,
  );
}
