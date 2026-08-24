import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/ui_inventory.dart';

void main() {
  test('production screen inventory is stable, sorted, and excludes test trees', () {
    final repository = Directory.current;
    final first = UiInventory(repository).render();
    final second = UiInventory(repository).render();

    expect(first.toMarkdown(), second.toMarkdown());
    expect(first.screenPaths, hasLength(79));
    expect(first.screenPaths, orderedEquals([...first.screenPaths]..sort()));
    expect(
      first.screenPaths,
      contains('lib/features/live/screens/live_screen.dart'),
    );
    expect(
      first.screenPaths,
      contains(
        'lib/features/community/presentation/screens/leaderboard_screen.dart',
      ),
    );
    expect(
      first.screenPaths,
      contains(
        'lib/features/gamification/presentation/screens/achievements_screen.dart',
      ),
    );
    expect(
      first.screenPaths,
      contains(
        'lib/features/gamification/presentation/screens/achievement_detail_screen.dart',
      ),
    );
    expect(
      first.screenPaths,
      contains(
        'lib/features/gamification/presentation/screens/gamification_hub_screen.dart',
      ),
    );
    expect(
      first.screenPaths,
      contains(
        'lib/features/community/presentation/screens/community_notifications_screen.dart',
      ),
    );
    expect(
      first.screenPaths,
      contains(
        'lib/features/gamification/presentation/screens/level_detail_screen.dart',
      ),
    );
    expect(
      first.screenPaths,
      contains(
        'lib/features/vision/presentation/screens/vision_session_screen.dart',
      ),
    );
    expect(first.screenPaths, isNot(contains(contains('test/'))));
    expect(() => first.screenPaths.add('unexpected'), throwsUnsupportedError);
    expect(
      first.reusableWidgetPaths,
      orderedEquals([...first.reusableWidgetPaths]..sort()),
    );
    expect(first.overlayPaths, orderedEquals([...first.overlayPaths]..sort()));
    expect(
      first.overlayPaths,
      contains('lib/features/learn/screens/learn_screen.dart'),
    );
    expect(
      () => first.reusableWidgetPaths.add('unexpected'),
      throwsUnsupportedError,
    );
    expect(() => first.overlayPaths.add('unexpected'), throwsUnsupportedError);
  });
}
