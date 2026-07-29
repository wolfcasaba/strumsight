import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/progress/providers/daily_goal_provider.dart';

import '../../support/preference_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = InMemoryKeyValueStore();

  setUp(store.values.clear);

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [preferenceStoreOverride(store)]);
    addTearDown(c.dispose);
    return c;
  }

  test('defaults to 10 minutes', () {
    expect(container().read(dailyGoalProvider), 10);
  });

  test('setGoal updates and clamps to range', () async {
    final c = container();
    final ctrl = c.read(dailyGoalProvider.notifier);
    await ctrl.setGoal(30);
    expect(c.read(dailyGoalProvider), 30);
    await ctrl.setGoal(9999);
    expect(c.read(dailyGoalProvider), DailyGoalController.maxMinutes);
    await ctrl.setGoal(1);
    expect(c.read(dailyGoalProvider), DailyGoalController.minMinutes);
  });

  test('persists across a fresh container', () async {
    final c1 = container();
    await c1.read(dailyGoalProvider.notifier).setGoal(45);

    final c2 = container();
    expect(c2.read(dailyGoalProvider), 45);
  });
}
