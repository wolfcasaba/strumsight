/// Audit H15 — the bookmarks list rendered `Post <raw id>` and
/// `Saved at <ISO timestamp>`, both hardcoded English. Raw ids and ISO
/// timestamps are never user-facing (AGENTS.md); the row now shows the
/// post's title (or a localized fallback when the post is not loadable)
/// and a localized, locale-formatted date.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/i18n/ss_formatters.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/presentation/screens/bookmarks_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

final _savedAt = DateTime.utc(2026, 8, 20, 9, 30);

BookmarksState _state() => BookmarksState(
  rows: <BookmarkRow>[
    BookmarkRow(
      id: 1,
      postId: ContentId('post-raw-id-1'),
      createdAt: _savedAt,
      isTombstone: false,
      title: 'Barre chords finally clicked',
    ),
    BookmarkRow(
      id: 2,
      postId: ContentId('post-raw-id-2'),
      createdAt: _savedAt,
      isTombstone: true,
    ),
  ],
  nextCursor: const CursorPage.haltedAfterRequest(),
  isLoadingMore: false,
  isRemoving: false,
);

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bookmarksProvider.overrideWith((ref) => Stream.value(_state())),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const BookmarksScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets('a bookmark row shows the post title, never the raw id', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Barre chords finally clicked'), findsOneWidget);
    expect(find.textContaining('post-raw-id-1'), findsNothing);
  });

  testWidgets('a post that is not loadable falls back to a localized label', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text(l10n.communityBookmarkUntitledPost), findsOneWidget);
    expect(find.textContaining('post-raw-id-2'), findsNothing);
  });

  testWidgets('the saved-at line is a localized date, not an ISO timestamp', (
    tester,
  ) async {
    await _pump(tester);

    final expected = l10n.communityBookmarkSavedOn(
      SsFormatters.date(_savedAt.toLocal(), localeName: 'en'),
    );
    expect(find.text(expected), findsNWidgets(2));
    expect(find.textContaining(_savedAt.toIso8601String()), findsNothing);
    expect(find.textContaining('Saved at '), findsNothing);
  });
}
