import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/model/analyze_result.dart';
import 'package:music_theory/features/library/data/library_repository.dart';
import 'package:music_theory/features/library/model/analyzed_session.dart';
import 'package:music_theory/features/library/providers/library_providers.dart';
import 'package:music_theory/features/live/model/strum.dart';
import 'package:music_theory/features/live/providers/live_providers.dart';
import 'package:music_theory/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_engines.dart';

AnalyzedSession _session(String id, String title) => AnalyzedSession(
      id: id,
      createdAt: DateTime(2026, 7, 7, 10, 30),
      title: title,
      result: const AnalyzeResult(
        durationSec: 4,
        bpm: 120,
        chords: [TimelineChord(label: 'C', startSec: 0, endSec: 2)],
        strums: [
          TimelineStrum(
              direction: StrumDirection.down, timeSec: 0.5, confidence: 0.8),
        ],
      ),
    );

/// A fake repo preloaded with [initial] (no platform channel).
class FakeLibraryRepository implements LibraryRepository {
  FakeLibraryRepository([List<AnalyzedSession>? initial])
      : _store = [...?initial];
  List<AnalyzedSession> _store;

  @override
  Future<List<AnalyzedSession>> load() async => _store;

  @override
  Future<void> save(List<AnalyzedSession> sessions) async => _store = sessions;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  test('add persists across a fresh container (real prefs repo)', () async {
    final c1 = ProviderContainer();
    addTearDown(c1.dispose);
    await c1.read(libraryProvider.future);
    await c1.read(libraryProvider.notifier).add(_session('1', 'C · G'));

    // A brand-new container reloads from persistence.
    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    final loaded = await c2.read(libraryProvider.future);
    expect(loaded.map((s) => s.id), contains('1'));
    expect(loaded.first.title, 'C · G');
  });

  test('newest is first and delete removes by id', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(libraryProvider.future);
    final ctrl = container.read(libraryProvider.notifier);

    await ctrl.add(_session('a', 'first'));
    await ctrl.add(_session('b', 'second'));
    expect(container.read(libraryProvider).value!.first.id, 'b'); // newest first

    await ctrl.delete('a');
    final ids = container.read(libraryProvider).value!.map((s) => s.id);
    expect(ids, ['b']);
  });

  testWidgets('Library tab lists a saved session (no more "coming soon")',
      (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          strumEngineProvider.overrideWithValue(engine),
          libraryRepositoryProvider.overrideWithValue(
            FakeLibraryRepository([_session('1', 'C · G · Am')]),
          ),
        ],
        child: const StrumSightApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();

    expect(find.text('C · G · Am'), findsOneWidget);
    expect(find.textContaining('Coming in'), findsNothing);
  });
}
