import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/config/app_config.dart';
import '../../../app/routing/app_route.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/public.dart';
import '../../community/public.dart';
import '../../progress/public.dart';
import '../../streak/public.dart';

/// The Profile Hub (UI-07, SDD Ch13 §UI-07) — personal progress, account,
/// community and settings in one place. Fully meaningful **without** an
/// account (A3, §5.3): a login wall here would break the offline-first
/// promise, so the account section only renders at all when
/// [accountEnabledProvider] is on, exactly like the legacy Settings screen.
///
/// Styled with plain Material widgets (matching `SettingsScreen`), not the
/// `core/design_system` component library — see `today_hub_screen.dart`'s
/// doc comment. The old "not safe under the app's root theme" reason is
/// obsolete (R21, audit MI8); the migration itself is still open.
class ProfileHubScreen extends ConsumerWidget {
  const ProfileHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final streak = ref.watch(streakProvider);
    final stats = ref.watch(aggregatedPracticeStatsProvider);
    final communityEnabled = ref
        .watch(appConfigProvider)
        .flags
        .communityEnabled;
    final accountEnabled = ref.watch(accountEnabledProvider);
    // MI-L (R33) — the MEASURED gate state, not just the build flag.
    // `.value` is null while the probe is in flight and on a failed
    // probe; both keep the pre-R33 copy, so nothing on this screen
    // moves until the gate has actually said the server is off.
    //
    // Watched only when the feature is compiled in: a build that ships
    // without Community has nothing to probe, and reading the gate
    // controller there would start an account-API call for a section
    // that already says "not in this build".
    final gateStatus = communityEnabled
        ? ref.watch(communityProfileControllerProvider).value?.status
        : null;
    // Az AI Tanár belépési pontja. A `/tutor/*` útvonalak az `aiTutorEnabled`
    // kapu alatt regisztrálódnak (`app_router.dart`), ezért a gomb PONTOSAN
    // ugyanazzal a flaggel kapuzott — kikapcsolt kapunál nem mutat
    // regisztrálatlan címre. (A `/coach` héj-célpont csak az adaptív héj
    // bekapcsolt állásán látszik; ez a gomb attól függetlenül elérhető.)
    final aiTutorEnabled = ref.watch(appConfigProvider).flags.aiTutorEnabled;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileHubTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            _SectionLabel(l10n.profileHubProgressSectionTitle),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: l10n.progressStreak,
                    value: '${streak.current}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Metric(
                    label: l10n.progressSessions,
                    value: '${stats.totalSessions}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              key: const ValueKey('profile-hub-achievements-entry'),
              // `push`, not `go` (2026-09-07 audit): every destination
              // below is a TOP-LEVEL route, so a `go` REPLACES the stack —
              // the arriving screen has `canPop == false`, its AppBar shows
              // no back arrow and the adaptive shell's bottom bar is gone,
              // so the only way back is leaving the app. Pushed, the same
              // route pops straight back to this hub.
              onPressed: () => context.push(AppRoutes.gamificationHub),
              child: Text(l10n.profileHubAchievementsSectionTitle),
            ),
            if (aiTutorEnabled) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                key: const ValueKey('profile-hub-tutor-entry'),
                onPressed: () => context.push(AppRoutes.tutorHome),
                child: Text(l10n.aiTutorHomeTitle),
              ),
            ],
            const SizedBox(height: 24),
            if (accountEnabled)
              _AccountSection(l10n: l10n)
            else ...[
              _SectionLabel(l10n.profileHubLocalOnlyTitle),
              const SizedBox(height: 8),
              Text(
                l10n.profileHubLocalOnlyMessage,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 24),
            _SectionLabel(l10n.profileHubCommunitySectionTitle),
            const SizedBox(height: 8),
            Text(
              _communityMessage(
                l10n,
                communityEnabled: communityEnabled,
                gateStatus: gateStatus,
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            // A közösség BELÉPÉSI PONTJA (2026-09-05). A 13 community
            // képernyő route-jai léteztek, de a szállított felületről SEMMI
            // nem vezetett hozzájuk — a felhasználó számára ez ugyanaz,
            // mintha nem lennének. A gomb a kapu-képernyőre visz, ami a
            // feature saját belépési szűrője.
            if (communityEnabled) ...[
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('profile-hub-community-entry'),
                onPressed: () => context.push(AppRoutes.community),
                child: Text(l10n.profileHubCommunityOpen),
              ),
            ],
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => context.go(AppRoutes.profileLibrary),
              child: Text(l10n.navLibrary),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.go(AppRoutes.profileSettings),
              child: Text(l10n.settingsTitle),
            ),
          ],
        ),
      ),
    );
  }

  /// What the hub says about Community (MI-L, R33).
  ///
  /// The build flag alone was the only input, so a build that ships the
  /// feature against a server running with the Community module OFF told
  /// the user "Connect with other players and share your progress" and
  /// then handed them a gate screen that says the opposite. The gate
  /// controller already measures that case as
  /// [CommunityGateStatus.unavailable]; this reads it.
  ///
  /// Every other state — including "not resolved yet" and "the probe
  /// failed" — keeps the original copy on purpose: an unfinished probe
  /// is not evidence that the server is off, and the pixel-pinned
  /// `e13_r17_profile_hub_compact` golden renders exactly that case.
  String _communityMessage(
    AppLocalizations l10n, {
    required bool communityEnabled,
    required CommunityGateStatus? gateStatus,
  }) {
    if (!communityEnabled) return l10n.profileHubCommunityDisabledReason;
    if (gateStatus == CommunityGateStatus.unavailable) {
      return l10n.profileHubCommunityServerDisabledMessage;
    }
    return l10n.profileHubCommunityEnabledMessage;
  }
}

/// The account block — only reachable when [accountEnabledProvider] is on.
/// Signed-out is a *choice* here (Sign in CTA), never a wall: every other
/// section on this screen renders regardless of this block's state.
class _AccountSection extends ConsumerWidget {
  const _AccountSection({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    if (authState.isLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(l10n.profileHubAccountSectionTitle),
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
      );
    }

    final signedIn = authState.value != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(l10n.profileHubAccountSectionTitle),
        const SizedBox(height: 8),
        Text(
          signedIn
              ? l10n.profileHubSignedInMessage
              : l10n.profileHubLocalOnlyMessage,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        signedIn
            ? OutlinedButton(
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).logout(),
                child: Text(l10n.profileHubSignOutCta),
              )
            : OutlinedButton(
                key: const ValueKey('profile-hub-sign-in-entry'),
                // `push` (2026-09-07 audit): `/login` is a top-level route,
                // and the login screen leaves itself by popping on success.
                // Reached with a `go` the stack was one page deep, so that
                // pop threw `GoError: There is nothing to pop` — the
                // measured "login does not work" defect.
                onPressed: () => context.push(AppRoutes.login),
                child: Text(l10n.profileHubSignInCta),
              ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
