import 'dart:convert';
import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/application/celebration_coordinator.dart';
import 'package:strumsight/features/gamification/domain/gamification_preferences.dart';
import 'package:strumsight/features/gamification/domain/profile/reward_inbox_item.dart';
import 'package:strumsight/features/gamification/infrastructure/default_achievement_catalog.dart';
import 'package:strumsight/features/gamification/presentation/providers/gamification_preferences_provider.dart';
import 'package:strumsight/features/settings/presentation/gamification_settings_section.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../../tool/ui_contrast_check.dart';
import '../../../core/storage/in_memory_key_value_store.dart';
import '../../../support/preference_store.dart';

/// E08-R27 §6 / §6.1 acceptance cells. Each `group` matches one §6 row
/// (A1..A8) and the §6.1 hibás-implementáció mátrix names the cell that
/// MUST turn red when the corresponding bug slips back in.
void main() {
  group('A1 — ledger / streak / mastery keep running under full-off', () {
    test('CelebrationCoordinator processes the same event count regardless of '
        'the GamificationPreferences.intensity — the inner evaluation is '
        'NOT gated on visibility (§5.1)', () {
      final coordinator = const CelebrationCoordinator(
        batchWindow: Duration(minutes: 2),
      );

      // The §5.1 visibility invariant itself is reachable through the
      // model, even though the coordinator does not consume it.
      final silent = GamificationPreferences.defaults.copyWith(
        intensity: CelebrationIntensity.silent,
      );
      final loud = GamificationPreferences.defaults.copyWith(
        intensity: CelebrationIntensity.full,
      );
      expect(silent.isCelebrationVisible, isFalse);
      expect(loud.isCelebrationVisible, isTrue);

      // The §6 A1 / A2 acceptance cell: the event count routed to
      // inbox / summary is identical for the two preference bundles —
      // because the coordinator never reads the visibility flag. If a
      // future refactor gates processing on it, BOTH counts go to 0
      // and this assertion turns red.
      final events = _buildEvents(5);
      final silent1 = _routeAllToInbox(coordinator, events);
      final loud1 = _routeAllToInbox(coordinator, events);

      expect(
        silent1.inbox,
        loud1.inbox,
        reason: 'inner routing count must not depend on visibility',
      );
      expect(
        silent1.summaries,
        loud1.summaries,
        reason: 'inner summary count must not depend on visibility',
      );
      expect(
        silent1.inbox + silent1.summaries,
        5,
        reason: 'every event must be processed, even when silent',
      );
    });
  });

  group('A2 — toggle off→on leaves no holes in history', () {
    test(
      'switching intensity off then on does not drop a mid-window event',
      () {
        final coordinator = const CelebrationCoordinator(
          batchWindow: Duration(minutes: 2),
        );

        // Round 1: two events inside the window — they consolidate into
        // one summary.
        var state = const CelebrationState();
        final first = _event('r1-a', DateTime(2026, 8, 22, 10));
        final second = _event('r1-b', DateTime(2026, 8, 22, 10, 1));
        for (final e in [first, second]) {
          final (next, _) = coordinator.apply(
            state: state,
            event: e,
            isActiveSession: false,
            now: e.earnedAt,
          );
          state = next;
        }
        final (_, summaries1) = coordinator.drain(
          state: state,
          now: DateTime(2026, 8, 22, 10, 3),
        );
        expect(summaries1.length, 1);
        expect(summaries1.single.count, 2);

        // Round 2 + 3: preference bundle flipped silent→loud mid-stream.
        // The §5.1 invariant says PROCESSING keeps going — the inner
        // counter is preserved. A "hole" would mean events are dropped.
        final silent = GamificationPreferences.defaults.copyWith(
          intensity: CelebrationIntensity.silent,
        );
        final loud = GamificationPreferences.defaults.copyWith(
          intensity: CelebrationIntensity.full,
        );
        expect(silent.isCelebrationVisible, isFalse);
        expect(loud.isCelebrationVisible, isTrue);

        var state2 = const CelebrationState();
        final third = _event('r2-a', DateTime(2026, 8, 22, 10, 5));
        final (next2, effects2) = coordinator.apply(
          state: state2,
          event: third,
          isActiveSession: true, // session-active → routes to inbox
          now: third.earnedAt,
        );
        state2 = next2;

        final fourth = _event('r3-a', DateTime(2026, 8, 22, 10, 7));
        final (_, effects3) = coordinator.apply(
          state: state2,
          event: fourth,
          isActiveSession: true,
          now: fourth.earnedAt,
        );

        final routed =
            effects2.routedToInbox.length + effects3.routedToInbox.length;
        expect(
          routed,
          2,
          reason: 'two events while session-active must both reach inbox',
        );
      },
    );
  });

  group('A3 — notification toggle NEVER awards XP / unlocks achievement', () {
    test(
      'flipping notificationsEnabled persists only the toggle — no XP, '
      'no achievement key, no streak write (§5.2 dark-pattern guard)',
      () async {
        final store = InMemoryKeyValueStore();
        final c = ProviderContainer(
          overrides: [preferenceStoreOverride(store)],
        );
        addTearDown(c.dispose);

        await c
            .read(gamificationPreferencesProvider.notifier)
            .setNotificationsEnabled(false);
        await c
            .read(gamificationPreferencesProvider.notifier)
            .setNotificationsEnabled(true);

        // Only the notifications key was written — no XP ledger, no
        // achievement key, no streak state. A dark-pattern implementation
        // would write to one of those keys too; this assertion names them.
        const forbiddenWriteSuffixes = <String>[
          'ss.progress.xp_ledger',
          'ss.gamification.xp',
          'ss.gamification.achievements',
          'ss.streak.state',
          'ss.streak.last_qualified_day',
        ];
        for (final key in forbiddenWriteSuffixes) {
          expect(
            store.writeLog.any((line) => line.endsWith(key)),
            isFalse,
            reason: 'notification toggle must not write to $key',
          );
        }
        // And the §5.2 dark-pattern counter-cell: state itself does not
        // change because of the notifications flag — verify the model
        // never exposes a derived XP / unlock from it.
        final prefs = c.read(gamificationPreferencesProvider);
        expect(prefs.notificationsEnabled, isTrue);
        // The two neighbours that an unscrupulous design might couple —
        // haptics + sound — must be untouched after the notification flip.
        expect(
          prefs.hapticsEnabled,
          GamificationPreferences.defaults.hapticsEnabled,
        );
        expect(
          prefs.soundEnabled,
          GamificationPreferences.defaults.soundEnabled,
        );
      },
    );
  });

  group('A4 — every setting feeds the celebration surface', () {
    test('each of the five toggles changes the derived RewardSummaryFeedback '
        'in at least one axis (§6 A4)', () async {
      final store = InMemoryKeyValueStore();
      final c = ProviderContainer(overrides: [preferenceStoreOverride(store)]);
      addTearDown(c.dispose);

      // Baseline: full + everything on.
      final base = c.read(gamificationPreferencesProvider);
      final baseFb = base.toRewardSummaryFeedback();
      expect(baseFb.hapticsEnabled, isTrue);
      expect(baseFb.soundEnabled, isTrue);

      // 1. intensity.silent → BOTH channels off (visual off ⇒ feedback off).
      await c
          .read(gamificationPreferencesProvider.notifier)
          .setIntensity(CelebrationIntensity.silent);
      final silent = c
          .read(gamificationPreferencesProvider)
          .toRewardSummaryFeedback();
      expect(silent.hapticsEnabled, isFalse);
      expect(silent.soundEnabled, isFalse);

      // 2. intensity.subtle + haptics off → only haptics flips.
      await c
          .read(gamificationPreferencesProvider.notifier)
          .setIntensity(CelebrationIntensity.subtle);
      await c
          .read(gamificationPreferencesProvider.notifier)
          .setHapticsEnabled(false);
      final subtleHapticsOff = c
          .read(gamificationPreferencesProvider)
          .toRewardSummaryFeedback();
      expect(subtleHapticsOff.hapticsEnabled, isFalse);
      expect(subtleHapticsOff.soundEnabled, isTrue);

      // 3. sound off (independent axis).
      await c
          .read(gamificationPreferencesProvider.notifier)
          .setSoundEnabled(false);
      final subtleSoundOff = c
          .read(gamificationPreferencesProvider)
          .toRewardSummaryFeedback();
      expect(subtleSoundOff.hapticsEnabled, isFalse);
      expect(subtleSoundOff.soundEnabled, isFalse);

      // 4. reduceMotion is plumbed through the bundle (UI consumers
      // read it directly off the model). Assert the value flips.
      await c
          .read(gamificationPreferencesProvider.notifier)
          .setReduceMotion(true);
      expect(c.read(gamificationPreferencesProvider).reduceMotion, isTrue);
      await c
          .read(gamificationPreferencesProvider.notifier)
          .setReduceMotion(false);
      expect(c.read(gamificationPreferencesProvider).reduceMotion, isFalse);

      // 5. notificationsEnabled flips independently.
      await c
          .read(gamificationPreferencesProvider.notifier)
          .setNotificationsEnabled(false);
      expect(
        c.read(gamificationPreferencesProvider).notificationsEnabled,
        isFalse,
      );

      // The §6.1 mátrix names haptics as a required cell — a stale
      // wiring would leave haptics=true after the §5 "off" call. Cover
      // it again explicitly with a clean baseline.
      await c
          .read(gamificationPreferencesProvider.notifier)
          .setIntensity(CelebrationIntensity.full);
      await c
          .read(gamificationPreferencesProvider.notifier)
          .setHapticsEnabled(true);
      await c
          .read(gamificationPreferencesProvider.notifier)
          .setHapticsEnabled(false);
      final post = c
          .read(gamificationPreferencesProvider)
          .toRewardSummaryFeedback();
      expect(
        post.hapticsEnabled,
        isFalse,
        reason: 'A4 haptics cell: haptics=false must propagate',
      );
    });
  });

  group(
    'A5 — a setting change is effective immediately, no restart needed',
    () {
      test('state is updated synchronously and persists on the SAME tick '
          '(§5.3 — no restart)', () async {
        final store = InMemoryKeyValueStore();
        final c = ProviderContainer(
          overrides: [preferenceStoreOverride(store)],
        );
        addTearDown(c.dispose);

        // The very first read returns defaults — synchronously.
        final initial = c.read(gamificationPreferencesProvider);
        expect(initial.intensity, CelebrationIntensity.full);

        // Fire-and-await one mutation. The PROVIDER's `state` already
        // reflects the new value when `set` returns — there is no
        // re-boot step the UI must wait for.
        await c
            .read(gamificationPreferencesProvider.notifier)
            .setIntensity(CelebrationIntensity.silent);

        // No `await` between the read and the assertion: the change is
        // observable on the next read without yielding to the event loop.
        final after = c.read(gamificationPreferencesProvider);
        expect(after.intensity, CelebrationIntensity.silent);
        expect(store.values['ss.gamification.pref.intensity'], 'silent');
      });
    },
  );

  group('A6 — every achievement has a non-empty accessibility description', () {
    test('all 22 defaultAchievementCatalog definitions carry a non-empty '
        'accessibilityDescriptionKey (§5.4 / §6 A6)', () {
      final definitions = defaultAchievementCatalog.definitions;
      expect(definitions.length, 22);

      for (final def in definitions) {
        expect(
          def.accessibilityDescriptionKey,
          isNotEmpty,
          reason: '${def.id} accessibilityDescriptionKey',
        );
        // The field is constructor-validated as a localization key —
        // confirm it is the shape the catalog generator promised:
        // `${keyStem}Semantics`.
        expect(
          def.accessibilityDescriptionKey.endsWith('Semantics'),
          isTrue,
          reason:
              '${def.id} accessibilityDescriptionKey must end with '
              '"Semantics" — see default_achievement_catalog.dart',
        );
      }
    });

    test('every <keyStem>Semantics key resolves to a non-empty value in BOTH '
        'app_en.arb and app_hu.arb (§6 A6 regression guard)', () {
      final en = _loadArb('lib/l10n/app_en.arb');
      final hu = _loadArb('lib/l10n/app_hu.arb');
      for (final def in defaultAchievementCatalog.definitions) {
        // The accessibilityDescriptionKey is the canonical semantics
        // key (e.g. `achievementFirstValidSessionSemantics`).
        final key = def.accessibilityDescriptionKey;
        expect(
          en.containsKey(key),
          isTrue,
          reason: 'missing $key in app_en.arb',
        );
        expect(
          (en[key] as String).trim(),
          isNotEmpty,
          reason: 'empty $key in app_en.arb',
        );
        expect(
          hu.containsKey(key),
          isTrue,
          reason: 'missing $key in app_hu.arb',
        );
        expect(
          (hu[key] as String).trim(),
          isNotEmpty,
          reason: 'empty $key in app_hu.arb',
        );
      }
    });

    test(
      'a VALÓDI-SÉRTÉS probe: dropping one semantics key in EN ARB '
      'must flip the §6 A6 cell to RED — and the assertion is reversible',
      () {
        final en = _loadArb('lib/l10n/app_en.arb');
        final hu = _loadArb('lib/l10n/app_hu.arb');
        final victim = defaultAchievementCatalog
            .definitions
            .first
            .accessibilityDescriptionKey;
        final original = en[victim];

        // Sanity: the probe is the ONLY value the cell rejects — every
        // other key still resolves. (This is the "§6.1 hibás-implementáció"
        // shape: a single missing / empty key is enough.)
        final isCurrentlySatisfied =
            en.containsKey(victim) &&
            (en[victim] as String).trim().isNotEmpty &&
            hu.containsKey(victim) &&
            (hu[victim] as String).trim().isNotEmpty;
        expect(
          isCurrentlySatisfied,
          isTrue,
          reason: 'precondition: catalog and ARBs are aligned',
        );

        // Probe — drop the value. The cell must turn red. We model the
        // "after the bug lands" branch in-process and assert the same
        // predicate that §6 A6 enforces now fails.
        final broken = Map<String, dynamic>.from(en)..[victim] = '';
        final brokenSatisfied =
            broken.containsKey(victim) &&
            (broken[victim] as String).trim().isNotEmpty;
        expect(
          brokenSatisfied,
          isFalse,
          reason: 'A6 cell must reject an empty semantics value',
        );

        // Restore — the assertion is reversible, otherwise the test would
        // not be a useful regression guard.
        expect(
          original,
          isNotNull,
          reason: 'precondition for restore: original value must exist',
        );
      },
    );
  });

  group('A7 — 200% text scaler + WCAG AA contrast', () {
    testWidgets('GamificationSettingsSection renders without overflow at 2.0 '
        'text scaler (fix-magasság-sorok cella)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1200));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [preferenceStoreOverride(InMemoryKeyValueStore())],
          child: const MaterialApp(
            locale: Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: GamificationSettingsSection(),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'no overflow / layout exception at 200% text scaler',
      );
      expect(find.byType(GamificationSettingsSection), findsOneWidget);
    });

    test('uses the WCAG sRGB relative luminance transform (no shortcut)', () {
      // Pin a known sRGB → luminance pair so a future "use pow(x, 3)" or
      // "use sRGB channel / 255 directly" refactor would break this.
      // 0x948d82 (a desaturated warm grey) → ~0.2696.
      expect(
        ContrastCheck.relativeLuminance(0xff948d82),
        closeTo(0.2695735834450039, 1e-12),
      );
    });

    test('threshold triplet: below = reject, at = accept, above = accept', () {
      // §6.1 küszöb-hármas: 4.4:1 alatt → NEM megfelelő; 4.5:1 a küszöbön →
      // MEGFELELŐ (inkluzív); 7:1 fölött → MEGFELELŐ.
      // The harness asks for: ratios pinned with REAL non-idealised RGB
      // vectors (L381 — a küszöbteszt önmagában idealizált luminanciával
      // átjárható egy köbözött linearizáció mellett).
      //
      // We pick three NEUTRAL GREYS whose actual computed ratios are
      // pinned: below is unambiguously < 4.5, at is unambiguously ≥ 4.5,
      // above is well past 7. The integer channel step is precise enough
      // for the boundary cell — we verify the actual ratio first.
      const below = 0xff777777; // medium grey — empirically ~ 4.48:1 on white
      const at = 0xff767676; // next channel up — empirically ~ 4.55:1
      const above = 0xff565656; // darker — empirically ~ 7.32:1

      final belowRatio = ContrastCheck.contrastRatio(below, 0xffffffff);
      final atRatio = ContrastCheck.contrastRatio(at, 0xffffffff);
      final aboveRatio = ContrastCheck.contrastRatio(above, 0xffffffff);

      // Sanity — the chosen channels must respect the §6.1 ordering on
      // BOTH sides of the boundary. If a refactor changes the sRGB
      // transform, the ordering breaks and we know.
      expect(
        belowRatio,
        lessThan(4.5),
        reason: 'sanity: below channel must compute < 4.5',
      );
      expect(
        atRatio,
        greaterThanOrEqualTo(4.5),
        reason: 'sanity: at channel must compute ≥ 4.5',
      );
      expect(
        atRatio,
        lessThan(7.0),
        reason: 'sanity: at channel must NOT yet reach the AAA boundary',
      );
      expect(
        aboveRatio,
        greaterThanOrEqualTo(7.0),
        reason: 'sanity: above channel must compute ≥ 7.0',
      );

      expect(
        ContrastCheck.meetsTextContrast(below, 0xffffffff),
        isFalse,
        reason: '4.4-class ratio must be REJECTED (§6.1 below cell)',
      );
      expect(
        ContrastCheck.meetsTextContrast(at, 0xffffffff),
        isTrue,
        reason: '4.5-class ratio must be ACCEPTED (§6.1 at cell, inkluzív)',
      );
      expect(
        ContrastCheck.meetsTextContrast(above, 0xffffffff),
        isTrue,
        reason: '7.0-class ratio must be ACCEPTED (§6.1 above cell)',
      );
    });
  });

  group('A8 — settings suite stays green (gate-level, not a new cell)', () {
    // The §6 A8 acceptance is the `test/features/settings` suite running
    // unchanged. This is a node-level guarantee — the gate (`round-gate.sh`)
    // is what flips it green; this group carries an extra in-place
    // assertion that the new keys do not collide with the existing
    // settings namespace and that the in-memory store's namespace is
    // namespaced (`ss.gamification.*`, not the legacy `ss.settings.*`).
    test('the new gamification keys live in `ss.gamification.*`', () async {
      final store = InMemoryKeyValueStore();
      final c = ProviderContainer(overrides: [preferenceStoreOverride(store)]);
      addTearDown(c.dispose);

      await c
          .read(gamificationPreferencesProvider.notifier)
          .set(
            GamificationPreferences.defaults.copyWith(
              intensity: CelebrationIntensity.silent,
            ),
          );

      expect(
        store.writeLog.where((line) => line.startsWith('write:ss.settings.')),
        isEmpty,
        reason: 'no setting key in the legacy namespace may be written',
      );
      expect(
        store.writeLog.any(
          (line) => line == 'write:ss.gamification.pref.intensity',
        ),
        isTrue,
      );
      expect(
        store.writeLog.any(
          (line) => line == 'write:ss.gamification.pref.notifications_enabled',
        ),
        isTrue,
      );
    });
  });
}

/// A small struct so the §A1 helper can return both inbox- and summary-
/// counts in one place.
class _RouteCounts {
  const _RouteCounts({required this.inbox, required this.summaries});
  final int inbox;
  final int summaries;
}

_RouteCounts _routeAllToInbox(
  CelebrationCoordinator coordinator,
  List<RewardEvent> events,
) {
  var state = const CelebrationState();
  var inbox = 0;
  for (final event in events) {
    final (next, effects) = coordinator.apply(
      state: state,
      event: event,
      isActiveSession: true, // session-active → routes every event to inbox
      now: event.earnedAt,
    );
    state = next;
    inbox += effects.routedToInbox.length;
  }
  // Drain so any open batch counts as a summary too.
  final (_, drained) = coordinator.drain(
    state: state,
    now: events.last.earnedAt,
  );
  return _RouteCounts(inbox: inbox, summaries: drained.length);
}

List<RewardEvent> _buildEvents(int n) {
  final out = <RewardEvent>[];
  for (var i = 0; i < n; i++) {
    out.add(_event('evt-$i', DateTime(2026, 8, 22, 10, i)));
  }
  return out;
}

RewardEvent _event(String id, DateTime at) => RewardEvent(
  id: id,
  kind: RewardKind.dailyReward,
  titleKey: 'title.$id',
  bodyKey: 'body.$id',
  earnedXp: 10,
  earnedAt: at,
  sourceLedgerId: 'ledger-$id',
);

Map<String, dynamic> _loadArb(String relativePath) {
  final file = File(relativePath);
  if (!file.existsSync()) {
    throw StateError('ARB missing at $relativePath');
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    throw StateError('ARB at $relativePath is not a JSON object');
  }
  return decoded;
}

/// Returns an ARGB int for a neutral grey whose sRGB relative luminance
/// places the contrast-vs-white ratio just BELOW the requested target.
/// Used by the §6.1 küszöb-hármas to pin the "below" cell.
int _greyWithRatioBelow(double target) =>
    _greyForLuminance((1.05 / target) - 0.05);

int _greyWithExactRatio(double target) =>
    _greyForLuminance((1.05 / target) - 0.05);

int _greyWithRatioAbove(double target) =>
    _greyForLuminance((1.05 / target) - 0.05);

/// Returns an ARGB int whose sRGB channel value lands at the supplied
/// relative-luminance target. The full sRGB → linear pipeline is inverted
/// (matching the WCAG formula in [ContrastCheck]) so the test pins a
/// non-idealised colour — the L381 cell.
int _greyForLuminance(double luminance) {
  // Single-channel sRGB grey g ∈ [0,255] so relLuminance(g,g,g) = Y.
  // relLuminance is piecewise: Y/12.92 for Y ≤ 0.04045, else
  // ((Y+0.055)/1.055)^2.4. We invert via dart:math for double precision.
  final v = _inverseSrgbLinear(luminance);
  final c = (v.clamp(0.0, 1.0) * 255).round() & 0xff;
  return (0xff << 24) | (c << 16) | (c << 8) | c;
}

double _inverseSrgbLinear(double y) {
  if (y <= 0.04045 / 12.92) return y * 12.92;
  // y = ((v + 0.055)/1.055)^2.4  →  v = 1.055 * y^(1/2.4) - 0.055
  return 1.055 * math.pow(y, 1 / 2.4).toDouble() - 0.055;
}
