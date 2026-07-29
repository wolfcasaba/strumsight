import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/features/progress/model/practice_entry.dart';
import 'package:strumsight/features/progress/providers/practice_log_provider.dart';

import '../../support/preference_store.dart';

/// Round 149 probe finding: a [PracticeLogController.record] at cold start (an
/// immediate Live/Learn practice moment) must not wipe the stored history —
/// the old `_dirty` guard skipped the loaded list and the following persist
/// overwrote it with just the new entry.
///
/// E01-R07 removed the async load the bug lived in: the log is read
/// synchronously in `build()`. The test keeps proving the invariant — the
/// stored history survives an immediate record, in state AND on disk.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PracticeEntry entry(int day, int seconds) => PracticeEntry(
    day: day,
    source: PracticeSource.live,
    seconds: seconds,
    strokes: 10,
  );

  test('an immediate record MERGES with the stored history', () async {
    final old = entry(20000, 300);
    final store = InMemoryKeyValueStore({
      StorageKeys.practiceLog: storedCollection([old.toJson()]),
    });
    final c = ProviderContainer(overrides: [preferenceStoreOverride(store)]);
    addTearDown(c.dispose);

    // Touch the provider and record IMMEDIATELY.
    await c.read(practiceLogProvider.notifier).record(entry(20001, 60));

    expect(
      c.read(practiceLogProvider).map((e) => e.day),
      containsAll([20000, 20001]),
      reason: 'the stored history must survive an immediate record',
    );

    // The persisted document must also carry BOTH entries.
    final document =
        jsonDecode(store.readString(StorageKeys.practiceLog)!)
            as Map<String, dynamic>;
    final persisted = (document['items'] as List)
        .map((e) => PracticeEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    expect(
      persisted.map((e) => e.day),
      containsAll([20000, 20001]),
      reason: 'the disk write must not clobber prior history',
    );
  });
}
