// A7 — section reordering has a keyboard/button alternative to drag, and
// every such affordance meets the >= 48 dp touch target (ADR 0280 §Döntés 5,
// round brief §0.0/B/R6, §6.1's three threshold cells: 47.0 dp red, 48.0 dp
// green — inclusive — and 56.0 dp green). L496 measured that a per-widget
// touch-target fix regresses on the NEXT new interactive element unless the
// cell measures every reorder affordance generically, not one hardcoded
// widget — so this walks every up/down button `SongSectionEditor` renders.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_section.dart';
import 'package:strumsight/features/song_trainer/presentation/widgets/song_section_editor.dart';
import 'package:strumsight/l10n/app_localizations.dart';

void main() {
  List<SongSection> threeSections() => <SongSection>[
    SongSection(
      id: SongSectionId('verse'),
      name: 'Verse',
      startMeasure: 0,
      endMeasureExclusive: 1,
    ),
    SongSection(
      id: SongSectionId('chorus'),
      name: 'Chorus',
      startMeasure: 1,
      endMeasureExclusive: 2,
    ),
    SongSection(
      id: SongSectionId('bridge'),
      name: 'Bridge',
      startMeasure: 2,
      endMeasureExclusive: 3,
    ),
  ];

  Future<void> pump(
    WidgetTester tester,
    List<SongSection> sections,
    void Function(int, int) onMove,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SongSectionEditor(sections: sections, onMove: onMove),
        ),
      ),
    );
  }

  testWidgets(
    'moving a section down works via a button tap, without any drag gesture',
    (tester) async {
      final moves = <(int, int)>[];
      await pump(tester, threeSections(), (from, to) => moves.add((from, to)));

      expect(find.byType(Draggable<Object>), findsNothing);
      expect(find.byType(LongPressDraggable<Object>), findsNothing);
      expect(find.byType(ReorderableListView), findsNothing);

      await tester.tap(
        find.byKey(const Key('song-editor-section-move-down-0')),
      );
      await tester.pump();

      expect(moves, <(int, int)>[(0, 1)]);
    },
  );

  testWidgets(
    'moving a section up works via a button tap, without any drag gesture',
    (tester) async {
      final moves = <(int, int)>[];
      await pump(tester, threeSections(), (from, to) => moves.add((from, to)));

      await tester.tap(find.byKey(const Key('song-editor-section-move-up-1')));
      await tester.pump();

      expect(moves, <(int, int)>[(1, 0)]);
    },
  );

  testWidgets(
    'every reorder affordance meets the >= 48 dp touch target (inclusive)',
    (tester) async {
      await pump(tester, threeSections(), (_, __) {});

      final reorderButtons = find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'song-editor-section-move-',
            ),
      );
      // 3 sections × 2 (up/down) buttons each — including the two disabled
      // edge buttons (first section's up, last section's down), which must
      // still meet the touch target: a disabled affordance is still a
      // rendered hit target space-wise.
      expect(reorderButtons, findsNWidgets(6));
      for (final element in reorderButtons.evaluate()) {
        final size = tester.getSize(find.byWidget(element.widget));
        expect(
          size.width,
          greaterThanOrEqualTo(48.0),
          reason: '${(element.widget as IconButton).key} width',
        );
        expect(
          size.height,
          greaterThanOrEqualTo(48.0),
          reason: '${(element.widget as IconButton).key} height',
        );
      }
    },
  );
}
