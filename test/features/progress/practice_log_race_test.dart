import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/progress/model/practice_entry.dart';
import 'package:music_theory/features/progress/providers/practice_log_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Round 149 probe finding: a [record] that lands BEFORE the async prefs load
/// completes (cold start → an immediate Live/Learn practice moment) must not
/// wipe the on-disk history — the old `_dirty` guard skipped the disk list
/// entirely and the subsequent persist overwrote it with just the new entry.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PracticeEntry entry(int day, int seconds) => PracticeEntry(
        day: day,
        source: PracticeSource.live,
        seconds: seconds,
        strokes: 10,
      );

  test('a record racing the initial load MERGES with disk history', () async {
    final old = entry(20000, 300);
    SharedPreferences.setMockInitialValues({
      'practice_log_v1': jsonEncode([old.toJson()]),
    });
    final c = ProviderContainer();
    addTearDown(c.dispose);

    // Touch the provider (starts the async load) and record IMMEDIATELY —
    // before the load's continuation has run.
    final ctrl = c.read(practiceLogProvider.notifier);
    final fresh = entry(20001, 60);
    final write = ctrl.record(fresh);
    await write;
    await Future<void>.delayed(Duration.zero); // let the load settle too

    final state = c.read(practiceLogProvider);
    expect(state.map((e) => e.day), containsAll([20000, 20001]),
        reason: 'the disk history must survive a racing record');

    // The persisted blob must also carry BOTH entries.
    final prefs = await SharedPreferences.getInstance();
    final persisted = (jsonDecode(prefs.getString('practice_log_v1')!) as List)
        .map((e) => PracticeEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    expect(persisted.map((e) => e.day), containsAll([20000, 20001]),
        reason: 'the disk write must not clobber prior history');
  });
}
