// Golden snapshots of the E13-R35 account/settings/privacy/offline-AI/share
// screens at a compact portrait phone (412×915) and the same frame at
// textScaler 2.0, per the round brief §7/A9. Pattern follows the merged
// `test/ui/goldens/e13_r34_screens_golden_test.dart` precedent: `AppTheme`
// (the app's actual runtime theme) — each screen wraps itself in its own
// per-feature `*ThemeScope` internally, so this file does not need to.
//
// Recorded on x86_64 (ADR 0426, §0.0.B/B8) via `tools/golden-x86.sh
// record` — NOT `flutter test --update-goldens` on this (aarch64) box.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/analyze/model/analyze_result.dart';
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/auth/screens/login_screen.dart';
import 'package:strumsight/features/offline_ai/data/offline_model_source.dart';
import 'package:strumsight/features/offline_ai/model/offline_model.dart';
import 'package:strumsight/features/offline_ai/providers/offline_model_controller.dart';
import 'package:strumsight/features/offline_ai/screens/model_manager_screen.dart';
import 'package:strumsight/features/settings/data/settings_repository.dart';
import 'package:strumsight/features/settings/screens/privacy_center_screen.dart';
import 'package:strumsight/features/settings/screens/settings_screen.dart';
import 'package:strumsight/features/share/screens/share_preview_screen.dart';
import 'package:strumsight/features/share/share_service.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../support/fake_auth.dart';
import '../../support/fake_settings.dart';
import '../../support/preference_store.dart';

const _compactPortrait = Size(412, 915);

// ---------------------------------------------------------------------------
// 1 — login_screen.dart
// ---------------------------------------------------------------------------

Widget _loginScreen() => const LoginScreen();
List<Override> _loginOverrides() => [
  ...preferenceOverrides(),
  tokenStoreProvider.overrideWithValue(FakeTokenStore()),
  authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
];

// ---------------------------------------------------------------------------
// 2 — settings_screen.dart
// ---------------------------------------------------------------------------

Widget _settingsScreen() => const Scaffold(body: SettingsScreen());
List<Override> _settingsOverrides() => [
  ...preferenceOverrides(),
  tokenStoreProvider.overrideWithValue(FakeTokenStore()),
  authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
  settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
];

// ---------------------------------------------------------------------------
// 3 — privacy_center_screen.dart
// ---------------------------------------------------------------------------

Widget _privacyCenterScreen() => const PrivacyCenterScreen();
List<Override> _privacyCenterOverrides() => [...preferenceOverrides()];

// ---------------------------------------------------------------------------
// 4 — offline_ai/screens/model_manager_screen.dart
// ---------------------------------------------------------------------------

final class _GoldenOfflineModelSource implements OfflineModelSource {
  const _GoldenOfflineModelSource();

  @override
  Future<AppResult<OfflineModelAsset>> fetchCandidate(String modelId) async {
    const bytes = <int>[1, 2, 3, 4, 5];
    return Success(
      OfflineModelAsset(
        modelId: modelId,
        version: '1.4.0',
        expectedSha256: offlineModelChecksum(bytes),
        bytes: bytes,
      ),
    );
  }
}

Widget _modelManagerScreen() => const ModelManagerScreen();
List<Override> _modelManagerOverrides() => [
  offlineModelSourceProvider.overrideWithValue(
    const _GoldenOfflineModelSource(),
  ),
];

// ---------------------------------------------------------------------------
// 5 — share_preview_screen.dart
// ---------------------------------------------------------------------------

final _shareResult = AnalyzeResult(
  durationSec: 12,
  bpm: 96,
  chords: const [
    TimelineChord(label: 'C', startSec: 0, endSec: 3),
    TimelineChord(label: 'G', startSec: 3, endSec: 6),
  ],
  strums: [
    for (var i = 0; i < 6; i++)
      TimelineStrum(
        direction: i.isEven ? StrumDirection.down : StrumDirection.up,
        timeSec: i.toDouble(),
        confidence: 0.9,
      ),
  ],
);

Widget _sharePreviewScreen() => SharePreviewScreen(
  result: _shareResult,
  title: 'Practice riff',
  shareService: const ShareService(),
);
List<Override> _sharePreviewOverrides() => const [];

// ---------------------------------------------------------------------------
// Pump / golden helpers
// ---------------------------------------------------------------------------

Future<void> _pump(
  WidgetTester tester,
  Widget home,
  List<Override> overrides, {
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = _compactPortrait;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expectGolden(WidgetTester tester, String name) => expectLater(
  find.byType(MaterialApp),
  matchesGoldenFile('goldens/$name.png'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final screens = <String, (Widget Function(), List<Override> Function())>{
    'login': (_loginScreen, _loginOverrides),
    'settings': (_settingsScreen, _settingsOverrides),
    'privacy_center': (_privacyCenterScreen, _privacyCenterOverrides),
    'model_manager': (_modelManagerScreen, _modelManagerOverrides),
    'share_preview': (_sharePreviewScreen, _sharePreviewOverrides),
  };

  for (final textScale in [1.0, 2.0]) {
    final suffix = textScale == 1.0 ? 'compact' : 'compact_scale2';

    for (final entry in screens.entries) {
      testWidgets('${entry.key} — $suffix', (tester) async {
        final (widgetBuilder, overridesBuilder) = entry.value;
        await _pump(
          tester,
          widgetBuilder(),
          overridesBuilder(),
          textScale: textScale,
        );
        await _expectGolden(tester, 'e13_r35_${entry.key}_$suffix');
      });
    }
  }
}
