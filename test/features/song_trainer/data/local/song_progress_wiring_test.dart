import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/song_trainer/application/song_trainer_providers.dart';

import '../../../../core/storage/in_memory_key_value_store.dart';

void main() {
  test(
    'production terminal recorder uses the public Practice History V2 bridge',
    () {
      final container = ProviderContainer(
        overrides: [
          keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        ],
      );
      addTearDown(container.dispose);

      final recorder = container.read(songProgressSessionRecorderProvider);

      expect(recorder, isA<PracticeHistoryRecorder>());
    },
  );
}
