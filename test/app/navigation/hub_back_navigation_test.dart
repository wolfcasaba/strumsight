// Navigation back-stack cells — the regression guard for the owner's
// 2026-09-16 device report ("when I open a menu item I cannot swipe back and
// there is no back arrow").
//
// Root cause: every hub entry navigated with `context.go`, which REPLACES the
// router stack, so the opened screen had no page below it. `Navigator.canPop`
// was therefore false — no automatic `AppBar` leading back button, no back
// control on the `SsStageScaffold` screens (which render theirs behind a
// `Navigator.canPop` check) — and the Android back gesture had nothing to pop,
// so it left the app.
//
// N1 — a source-level guard over EVERY `lib/features/**/screens/**` file: a
//      screen may only `context.go` to a primary navigation destination (a tab
//      switch). Anything else is a stack replace and must be a `push`. This is
//      the cell that would have caught the bug, and it covers screens that do
//      not exist yet.
// N2 — per hub entry: after the tap the opened screen has a back affordance,
//      the router can pop, and `tester.pageBack()` lands back on the hub.
// N3 — router level, parametrised over the route catalogue (not a hand list):
//      pushing a non-destination route that the LIVE router registers leaves
//      the hub route on the stack (`canPop()` true) and pops back to it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:strumsight/app/config/app_config.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/core/design_system/public.dart' show SsLightTheme;
import 'package:strumsight/features/auth/data/token_store.dart';
import 'package:strumsight/features/auth/providers/auth_providers.dart';
import 'package:strumsight/features/chords/screens/chord_library_screen.dart';
import 'package:strumsight/features/gamification/presentation/screens/gamification_hub_screen.dart';
import 'package:strumsight/features/library_v2/screens/unified_library_screen.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/metronome/screens/metronome_screen.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_setup_screen.dart';
import 'package:strumsight/features/practice_hub/screens/practice_area_hub_screen.dart';
import 'package:strumsight/features/profile_hub/screens/profile_hub_screen.dart';
import 'package:strumsight/features/progress_v2/public.dart';
import 'package:strumsight/features/settings/screens/settings_screen.dart';
import 'package:strumsight/features/today/screens/today_hub_screen.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_auth.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

class _RouterTestApp extends ConsumerWidget {
  const _RouterTestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      theme: SsLightTheme.data(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

Future<GoRouter> _pumpAdaptiveRouter(WidgetTester tester) async {
  final liveEngine = FakeStrumEngine();
  final tunerEngine = FakeTunerEngine();
  final container = ProviderContainer(
    overrides: [
      ...preferenceOverrides(),
      ...fakeAudioOverrides(),
      strumEngineProvider.overrideWithValue(liveEngine),
      tunerEngineProvider.overrideWithValue(tunerEngine),
      tokenStoreProvider.overrideWithValue(FakeTokenStore()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      onboardingSeenProvider.overrideWith(() => OnboardingController(true)),
      appConfigProvider.overrideWithValue(
        AppConfig(
          environment: AppEnvironment.development,
          apiBaseUrl: AppConfig.devApiBaseUrl,
          flags: const FeatureFlags(
            accountEnabled: false,
            diagnosticsEnabled: true,
            labModeAvailable: true,
            practiceEngineV2Enabled: true,
            adaptiveShellEnabled: true,
          ),
          diagnosticsToken: AppConfig.devDiagnosticsToken,
          buildMode: 'test',
          appVersion: 'test',
        ),
      ),
    ],
  );
  final router = container.read(routerProvider);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await liveEngine.dispose();
    await tunerEngine.dispose();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const _RouterTestApp(),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// Any visible "go back one page" control: the `AppBar`'s automatic leading
/// [BackButton], or the explicit `Icons.arrow_back` [IconButton] the
/// `SsStageScaffold` screens (Tuner, Metronome) put in their status header.
Finder _backAffordance() {
  return find.byWidgetPredicate((widget) {
    if (widget is BackButton) return true;
    if (widget is IconButton) {
      final icon = widget.icon;
      return icon is Icon && icon.icon == Icons.arrow_back;
    }
    return false;
  });
}

/// `name -> path` for every constant in the route catalogue, parsed from the
/// catalogue itself so the guards below can never drift from it.
Map<String, String> _routeCatalogue() {
  final source = File('lib/app/routing/app_route.dart').readAsStringSync();
  final pattern = RegExp(r"static\s+const\s+String\s+(\w+)\s*=\s*'([^']+)'");
  final catalogue = <String, String>{};
  for (final match in pattern.allMatches(source)) {
    catalogue[match.group(1)!] = match.group(2)!;
  }
  return catalogue;
}

/// Every production screen source. Both layouts are in use in this tree:
/// `features/<f>/screens/` and `features/<f>/presentation/screens/`.
List<File> _screenSources() {
  final sources = <File>[];
  for (final entity in Directory('lib/features').listSync(recursive: true)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.dart')) continue;
    if (!entity.path.contains('/screens/')) continue;
    sources.add(entity);
  }
  return sources;
}

typedef _GoCall = ({String argument, int line});

/// [source] with every comment blanked out, character for character.
///
/// The scanner below matches raw text, so a doc comment that QUOTES a call —
/// `practice_session_screen.dart` explains its pop contract by naming the
/// `context.go(AppRoutes.practiceSession)` the setup screen makes — used to
/// register as a call site the file does not contain. Blanking (rather than
/// deleting) keeps every offset and line number exact, and it cuts the other
/// way too: a commented-out `context.go` can no longer smuggle a real one
/// past the guard by looking like documentation.
///
/// String literals are tracked so a `//` INSIDE one (a URL, say) does not
/// swallow the rest of the line.
String _withoutComments(String source) {
  final out = StringBuffer();
  var index = 0;
  String? quote;
  while (index < source.length) {
    final char = source[index];
    final next = index + 1 < source.length ? source[index + 1] : '';
    if (quote != null) {
      out.write(char);
      if (char == r'\') {
        if (next.isNotEmpty) {
          out.write(next);
          index += 2;
          continue;
        }
      } else if (char == quote || char == '\n') {
        quote = null;
      }
      index++;
      continue;
    }
    if (char == "'" || char == '"') {
      quote = char;
      out.write(char);
      index++;
      continue;
    }
    if (char == '/' && next == '/') {
      while (index < source.length && source[index] != '\n') {
        out.write(' ');
        index++;
      }
      continue;
    }
    if (char == '/' && next == '*') {
      while (index < source.length &&
          !(source[index] == '*' &&
              index + 1 < source.length &&
              source[index + 1] == '/')) {
        out.write(source[index] == '\n' ? '\n' : ' ');
        index++;
      }
      // The closing `*/` itself.
      final remaining = source.length - index;
      out.write(' ' * (remaining < 2 ? remaining : 2));
      index += 2;
      continue;
    }
    out.write(char);
    index++;
  }
  return out.toString();
}

/// The argument text of each `context.go(` call in [source], parentheses
/// balanced so a ternary or a multi-line argument list stays one entry.
/// Comments are blanked first ([_withoutComments]) so only real call sites
/// are measured.
List<_GoCall> _contextGoCalls(String rawSource) {
  final source = _withoutComments(rawSource);
  const marker = 'context.go(';
  final calls = <_GoCall>[];
  var index = source.indexOf(marker);
  while (index >= 0) {
    var depth = 1;
    var cursor = index + marker.length;
    while (cursor < source.length && depth > 0) {
      final char = source[cursor];
      if (char == '(') depth++;
      if (char == ')') depth--;
      cursor++;
    }
    final raw = source.substring(index + marker.length, cursor - 1);
    final argument = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    final line = '\n'.allMatches(source.substring(0, index)).length + 1;
    calls.add((argument: argument, line: line));
    index = source.indexOf(marker, cursor);
  }
  return calls;
}

/// The only `context.go` call sites in a screen that are NOT a primary
/// navigation destination, each with the measured reason it must stay a stack
/// replace. Everything else must be a `push` — see N1.
const Map<String, Set<String>> _goExceptions = <String, Set<String>>{
  // The Live Stage's two exits, both deliberate hand-offs AWAY from a stage
  // that is over. `entryLocation`: "Finish" pops when it CAN
  // (`context.canPop()` guards the line above it); this branch only fires with
  // an empty stack, where a push would strand the user with no way out. The
  // ternary: the summary dialog's "open the course" leaves the finished
  // session behind — a push would keep it under the course, so back would
  // return to a session that already ended.
  'lib/features/live/screens/live_screen.dart': <String>{
    'entryLocation',
    'adaptive ? AppRoutes.practiceLearn : AppRoutes.learn',
  },
  // Starting a session is a deliberate hand-off to the Stage flow, whose own
  // `PopScope` confirmation owns the exit; it is not a "menu item".
  'lib/features/practice/presentation/screens/practice_setup_screen.dart':
      <String>{'AppRoutes.practiceSession'},
  // E14-R36 (ADR 0595) — the ten-minute chain. A chain STEP is a primary
  // destination, not a menu item: the chain owns the whole session and its
  // own "Leave the chain" action is the exit, so each step REPLACES the
  // previous one. Pushing instead would stack tune→play→review under each
  // other and make back-stepping re-enter a step the chain already advanced
  // past. `primaryCtaLocation` is the Today hub's single primary CTA, i.e.
  // the hub's own primary destination, which is what `go` is for.
  'lib/features/today/screens/today_hub_screen.dart': <String>{
    'primaryCtaLocation',
    'location',
  },
  // The same chain, handed off from the Tuner's tune step.
  'lib/features/tuner/screens/tuner_screen.dart': <String>{'location'},
  // The challenge's exit, the Live Stage's `entryLocation` pattern exactly:
  // `_leave` pops when it CAN (`context.canPop()` guards the line above it),
  // and this branch only fires with an empty stack — where a push would
  // strand the learner on a finished minute with no way out.
  'lib/features/strum_challenge/presentation/screens/strum_challenge_screen.dart':
      <String>{
        'ref.read(appConfigProvider).flags.adaptiveShellEnabled ? AppRoutes.today : AppRoutes.live,',
      },
};

/// The routes the hubs navigate to, read out of the hub sources — derived from
/// the catalogue, never a hand list.
Set<String> _hubTargets() {
  const hubs = <String>[
    'lib/features/today/screens/today_hub_screen.dart',
    'lib/features/practice_hub/screens/practice_area_hub_screen.dart',
    'lib/features/profile_hub/screens/profile_hub_screen.dart',
  ];
  final catalogue = _routeCatalogue();
  final pattern = RegExp(r'AppRoutes\.(\w+)');
  final targets = <String>{};
  for (final hub in hubs) {
    final source = File(hub).readAsStringSync();
    for (final match in pattern.allMatches(source)) {
      final path = catalogue[match.group(1)!];
      if (path != null) targets.add(path);
    }
  }
  return targets;
}

/// Every concrete path the LIVE router registers under this harness's flags,
/// walked from the router's own configuration — so a route added by a later
/// round is covered without touching this file.
Set<String> _registeredPaths(GoRouter router) {
  final paths = <String>{};
  void walk(List<RouteBase> routes) {
    for (final route in routes) {
      if (route is GoRoute) paths.add(route.path);
      if (route is StatefulShellRoute) {
        for (final branch in route.branches) {
          walk(branch.routes);
        }
      }
      walk(route.routes);
    }
  }

  walk(router.configuration.routes);
  return paths;
}

typedef _HubEntry = ({String hub, Type hubScreen, String label, Type screen});

/// Pumps a bounded number of frames instead of settling.
///
/// Some routed screens animate CONTINUOUSLY by design — `SsStrumPendulum`
/// polls its clock pull-style and deliberately never stops its ticker (its
/// own comment says so), so the rhythm rung and the strum challenge never
/// reach a quiescent tree and `pumpAndSettle` times out on them. What this
/// group claims is that the hub stays on the stack and the route pops back to
/// it — that needs the route BUILT, not the tree still.
Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  final l10n = AppLocalizationsEn();

  group('N1 — a screen only `go`es to a destination', () {
    test('every other hub/menu entry is a push, so it has something to pop '
        'back to', () {
      final catalogue = _routeCatalogue();
      final destinations = AppRoutes.adaptiveShellDestinations.toSet();
      final constantPattern = RegExp(r'^AppRoutes\.(\w+)$');
      final violations = <String>[];

      for (final file in _screenSources()) {
        final path = file.path;
        for (final call in _contextGoCalls(file.readAsStringSync())) {
          if (_goExceptions[path]?.contains(call.argument) ?? false) {
            continue;
          }
          final constant = constantPattern.firstMatch(call.argument);
          final name = constant?.group(1);
          final routePath = name == null ? null : catalogue[name];
          if (routePath != null && destinations.contains(routePath)) continue;
          violations.add('$path:${call.line} context.go(${call.argument})');
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'context.go REPLACES the router stack: the opened screen gets no '
            'page below it, so there is no AppBar back arrow and the Android '
            'back gesture leaves the app (owner report 2026-09-16). Use '
            'context.push for anything that is not a primary navigation '
            'destination, or document the call site in _goExceptions. '
            'Found: ${violations.join(', ')}',
      );
    });

    test('the exception list only names call sites that still exist', () {
      for (final entry in _goExceptions.entries) {
        final source = File(entry.key).readAsStringSync();
        final arguments = _contextGoCalls(source).map((c) => c.argument);
        for (final exception in entry.value) {
          expect(
            arguments,
            contains(exception),
            reason:
                '${entry.key} no longer contains context.go($exception) — '
                'drop the stale exception instead of letting it shield a new '
                'violation',
          );
        }
      }
    });
  });

  group('N2 — a hub entry opens a screen you can come back from', () {
    final cases = <_HubEntry>[
      (
        hub: AppRoutes.today,
        hubScreen: TodayHubScreen,
        label: l10n.todayHubViewProgressCta,
        screen: ProgressDashboardScreen,
      ),
      (
        hub: AppRoutes.practiceHub,
        hubScreen: PracticeAreaHubScreen,
        label: l10n.practiceAreaHubRecommendedCta,
        screen: PracticeSetupScreen,
      ),
      (
        hub: AppRoutes.practiceHub,
        hubScreen: PracticeAreaHubScreen,
        label: l10n.liveTuner,
        screen: TunerScreen,
      ),
      (
        hub: AppRoutes.practiceHub,
        hubScreen: PracticeAreaHubScreen,
        label: l10n.metronomeTitle,
        screen: MetronomeScreen,
      ),
      (
        hub: AppRoutes.practiceHub,
        hubScreen: PracticeAreaHubScreen,
        label: l10n.chordLibraryTitle,
        screen: ChordLibraryScreen,
      ),
      (
        hub: AppRoutes.profileHome,
        hubScreen: ProfileHubScreen,
        label: l10n.profileHubAchievementsSectionTitle,
        screen: GamificationHubScreen,
      ),
      (
        hub: AppRoutes.profileHome,
        hubScreen: ProfileHubScreen,
        label: l10n.navLibrary,
        screen: UnifiedLibraryScreen,
      ),
      (
        hub: AppRoutes.profileHome,
        hubScreen: ProfileHubScreen,
        label: l10n.settingsTitle,
        screen: SettingsScreen,
      ),
    ];

    for (final entry in cases) {
      testWidgets('${entry.hub} "${entry.label}" pops back to the hub', (
        tester,
      ) async {
        final router = await _pumpAdaptiveRouter(tester);
        router.go(entry.hub);
        await tester.pumpAndSettle();
        expect(find.byType(entry.hubScreen), findsOneWidget);
        expect(
          router.canPop(),
          isFalse,
          reason: 'a hub is a destination root — nothing to pop yet',
        );

        final button = find.text(entry.label);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final opened = find.byWidgetPredicate(
          (widget) => widget.runtimeType == entry.screen,
        );
        expect(
          opened,
          findsOneWidget,
          reason: '"${entry.label}" must open a ${entry.screen}',
        );
        expect(
          router.canPop(),
          isTrue,
          reason:
              '"${entry.label}" must PUSH, so the Android back gesture pops '
              'to ${entry.hub} instead of leaving the app',
        );
        expect(
          _backAffordance(),
          findsWidgets,
          reason: '${entry.screen} must render a visible back control',
        );

        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(router.canPop(), isFalse);
        expect(router.state.uri.path, entry.hub);
        expect(find.byType(entry.hubScreen), findsOneWidget);
        expect(opened, findsNothing);
      });
    }
  });

  group('N3 — a pushed detail route keeps the hub on the stack', () {
    testWidgets('every registered non-destination hub target is poppable', (
      tester,
    ) async {
      final router = await _pumpAdaptiveRouter(tester);
      final registered = _registeredPaths(router);
      final destinations = AppRoutes.adaptiveShellDestinations.toSet();

      final detailRoutes = <String>[];
      for (final path in _hubTargets()) {
        if (!registered.contains(path)) continue;
        if (destinations.contains(path)) continue;
        if (path.contains(':')) continue;
        detailRoutes.add(path);
      }
      detailRoutes.sort();

      expect(
        detailRoutes,
        isNotEmpty,
        reason: 'the derivation itself must not silently collapse to nothing',
      );

      for (final path in detailRoutes) {
        router.go(AppRoutes.today);
        await _pumpFrames(tester);
        expect(router.canPop(), isFalse, reason: path);

        router.push<void>(path);
        await _pumpFrames(tester);

        expect(tester.takeException(), isNull, reason: path);
        expect(
          router.canPop(),
          isTrue,
          reason: '$path must leave ${AppRoutes.today} on the stack',
        );

        router.pop();
        await _pumpFrames(tester);
        expect(router.state.uri.path, AppRoutes.today, reason: path);
      }
    });
  });
}
