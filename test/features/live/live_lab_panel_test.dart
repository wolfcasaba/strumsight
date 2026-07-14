import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:music_theory/features/live/providers/live_providers.dart';
import 'package:music_theory/features/settings/providers/lab_mode_provider.dart';
import 'package:music_theory/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_engines.dart';

/// A LabMode notifier fixed at [_v] (skips the async prefs load) for tests.
class _FixedLabMode extends LabModeNotifier {
  _FixedLabMode(this._v);
  final bool _v;
  @override
  bool build() => _v;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Live Lab panel is HIDDEN when Lab mode is off (default)',
      (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          strumEngineProvider.overrideWithValue(engine),
          labModeProvider.overrideWith(() => _FixedLabMode(false)),
        ],
        child: const StrumSightApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Capture & analyze last ~30 s'), findsNothing);
    // With Lab off the engine is told NOT to capture (never a stray `true`).
    expect(engine.captureCalls, isNot(contains(true)));

    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('Live Lab panel SHOWS with a capture button when Lab mode is on',
      (tester) async {
    final engine = FakeStrumEngine();
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          strumEngineProvider.overrideWithValue(engine),
          labModeProvider.overrideWith(() => _FixedLabMode(true)),
        ],
        child: const StrumSightApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Capture & analyze last ~30 s'), findsOneWidget);
    // Lab on → the engine's rolling capture was enabled.
    expect(engine.captureCalls, contains(true));

    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('Capture with an empty mic buffer shows the "no audio yet" hint',
      (tester) async {
    final engine = FakeStrumEngine(); // fakePcm empty by default
    addTearDown(engine.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          strumEngineProvider.overrideWithValue(engine),
          labModeProvider.overrideWith(() => _FixedLabMode(true)),
        ],
        child: const StrumSightApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Capture & analyze last ~30 s'));
    await tester.pumpAndSettle();

    // Empty buffer → the guard reports "no audio", never runs analysis/crashes.
    expect(find.textContaining('No audio captured yet'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
  });
}
