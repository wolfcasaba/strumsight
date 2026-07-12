import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/model/analyze_result.dart';
import 'package:music_theory/features/library/model/analyzed_session.dart';
import 'package:music_theory/features/library/providers/library_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round 161 lock — the 100-session cap: the OLDEST session falls off, the
/// newest stays, and boundary rename/delete keep working.
AnalyzedSession _s(int i) => AnalyzedSession(
      id: 's$i',
      title: 'Take $i',
      createdAt: DateTime.utc(2026, 1, 1).add(Duration(minutes: i)),
      result: AnalyzeResult.empty,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the 101st add drops the oldest, boundary ops still work', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final lib = c.read(libraryProvider.notifier);

    for (var i = 0; i < 101; i++) {
      await lib.add(_s(i));
    }
    var list = c.read(libraryProvider).value!;
    expect(list, hasLength(100));
    expect(list.first.id, 's100', reason: 'newest-first head');
    expect(list.map((s) => s.id), isNot(contains('s0')),
        reason: 'the oldest falls off');

    await lib.rename('s100', 'Renamed');
    await lib.delete('s1');
    list = c.read(libraryProvider).value!;
    expect(list, hasLength(99));
    expect(list.first.title, 'Renamed');
  });
}
