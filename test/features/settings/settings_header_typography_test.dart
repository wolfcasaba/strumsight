// Audit U8 — the Settings screen's header used to be a hand-rolled 30 px
// Montserrat w800, while every shell screen ("Today", "Profile", "Practice")
// titles itself with a plain `AppBar(title: Text(...))`, i.e. the theme's
// `titleLarge`. Moving between the shell and Settings therefore changed the
// header's weight for no reason. This file measures the EFFECTIVE rendered
// font size of both titles (the merged span style off `RenderParagraph`, not
// the widget's own possibly-null `style`) under one and the same theme.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/profile_hub/screens/profile_hub_screen.dart';
import 'package:strumsight/features/settings/data/settings_repository.dart';
import 'package:strumsight/features/settings/screens/settings_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_auth.dart';
import '../../support/fake_settings.dart';
import '../../support/preference_store.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  List<Override> overrides = const [],
}) async {
  // A fresh scope per pump: Riverpod forbids changing the NUMBER of
  // overrides on a rebuilt ProviderScope, and the two screens need
  // different override sets.
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [...preferenceOverrides(), ...overrides],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pump();
}

/// The size the title is actually painted at: `Text` merges the ambient
/// `DefaultTextStyle` (which is where an `AppBar` title gets its style from)
/// into the span it hands to the paragraph, so the span is the only place
/// both titles can be compared like for like.
double? _renderedFontSize(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(text).first);
  return paragraph.text.style?.fontSize;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the Settings title renders at the same size as a shell '
      "screen's app-bar title", (tester) async {
    await _pump(tester, const ProfileHubScreen());
    final shellTitleSize = _renderedFontSize(tester, 'Profile');

    await _pump(
      tester,
      const Scaffold(body: SettingsScreen()),
      overrides: [
        tokenStoreProvider.overrideWithValue(FakeTokenStore()),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      ],
    );
    final settingsTitleSize = _renderedFontSize(tester, 'Settings');

    expect(shellTitleSize, isNotNull);
    expect(
      settingsTitleSize,
      shellTitleSize,
      reason:
          'the Settings header must not out-shout every shell screen title '
          '(audit U8)',
    );
  });
}
