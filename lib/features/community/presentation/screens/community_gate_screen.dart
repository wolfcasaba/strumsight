/// Community gate — the entry screen (E09-R06, ADR 0400 §5, brief
/// §5.1), one view per [CommunityGateStatus].
///
/// The gate is intentionally minimal. The brief §5.1 invariant is
/// that a Community profile is NEVER created implicitly — the gate
/// shows the right entry point for the current state and lets the
/// user advance explicitly:
///
/// * ``disabled`` — the account layer is off; show a "feature not
///   available" message. No further interaction.
/// * ``loggedOut`` — the user is not signed in. Shows the message
///   AND (R21, audit MI6) the sign-in CTA that was missing: until
///   this round the state rendered a bare ``_StatusView``, so a
///   logged-out learner was told to sign in with no control that
///   could take them there. The CTA ``push``-es ``/login`` — a
///   ``go`` would replace the stack and strand the user on a
///   one-page navigator (the R17 finding). It only renders while
///   ``accountEnabled`` is on: with the account layer off there is
///   nothing to sign in to, and the router does not register
///   ``/login`` at all.
/// * ``profileMissing`` — the user is signed in but has no
///   profile. Show the CTA that opens the edit-profile screen in
///   create mode.
/// * ``ready`` — the user is signed in AND has a profile. The state
///   is the Community HUB (WP-C, 2026-09-06): the read-only summary,
///   the "Edit profile" CTA, and a named entry to every one of the
///   thirteen registered community routes.
/// * ``unavailable`` — the server does not host the Community module
///   (R12); a card + Retry, no create CTA.
/// * ``error`` — the profile probe failed for a reason that says
///   nothing about whether a profile exists (R20, audit M6.3: a
///   timeout, a 500). Its own card + Retry — NEVER the
///   ``profileMissing`` create CTA.
///
/// The screen holds no local state of its own — the controller is
/// the single source of truth (the four states, the loaded profile,
/// the in-flight flag). The gate is a pure projection of the
/// controller.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:strumsight/core/design_system/public.dart';

import '../../../../app/config/app_config.dart';
import '../../../../app/routing/app_route.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/controllers/profile_controller.dart';
import '../../data/repositories/feed_repository_impl.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/repositories/community_page.dart';
import '../../domain/value_objects/cursor_page.dart';
import '../../domain/value_objects/public_user_id.dart';
import '../widgets/community_theme_scope.dart';
import 'edit_profile_screen.dart';

class CommunityGateScreen extends ConsumerWidget {
  const CommunityGateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(communityProfileControllerProvider);
    final localizations = AppLocalizations.of(context);

    return CommunityThemeScope(
      child: Scaffold(
        appBar: AppBar(title: Text(_appBarTitle(state, localizations))),
        body: state.when(
          loading: () => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(localizations.communityGateLoadingBody),
              ],
            ),
          ),
          error: (failure, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    localizations.communityGateErrorBody,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SsButton(
                    onPressed: () => ref
                        .read(communityProfileControllerProvider.notifier)
                        .refresh(),
                    label: localizations.communityGateRetry,
                  ),
                ],
              ),
            ),
          ),
          data: (value) => _GateBody(state: value),
        ),
      ),
    );
  }

  /// The AppBar title, per gate state (MI-A, R33).
  ///
  /// Every state used to be titled "Create your Community profile" —
  /// including the two that say the opposite in their body ("Community is
  /// not available in this build", "…not enabled on this server yet") and
  /// the logged-out one, which offers no profile creation at all. The
  /// title is the first thing a screen reader announces, so it was the
  /// screen's loudest untruth.
  ///
  /// These are DEDICATED short AppBar strings, not the body titles:
  /// reusing the body title would print the same 40-character sentence
  /// twice on one screen and clip it in the bar at large text scales.
  /// `profileMissing` keeps [AppLocalizations.communityGateProfileMissingTitle]
  /// — that state is the one pinned by `e13_r33_gate_compact`, and it is
  /// the one state where the old title was true.
  String _appBarTitle(
    AsyncValue<CommunityProfileState> state,
    AppLocalizations localizations,
  ) {
    if (state.hasError) return localizations.communityGateAppBarErrorTitle;
    final value = state.value;
    if (value == null) return localizations.communityGateAppBarTitle;
    return switch (value.status) {
      CommunityGateStatus.disabled || CommunityGateStatus.unavailable =>
        localizations.communityGateAppBarUnavailableTitle,
      CommunityGateStatus.loggedOut =>
        localizations.communityGateAppBarLoggedOutTitle,
      CommunityGateStatus.profileMissing =>
        localizations.communityGateProfileMissingTitle,
      CommunityGateStatus.ready => localizations.communityGateAppBarTitle,
      CommunityGateStatus.error => localizations.communityGateAppBarErrorTitle,
    };
  }
}

class _GateBody extends ConsumerWidget {
  const _GateBody({required this.state});

  final CommunityProfileState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final accountEnabled = ref.watch(appConfigProvider).flags.accountEnabled;
    return switch (state.status) {
      CommunityGateStatus.disabled => _StatusView(
        title: localizations.communityGateDisabledTitle,
        body: localizations.communityGateDisabledBody,
      ),
      CommunityGateStatus.loggedOut => _LoggedOutView(
        accountEnabled: accountEnabled,
        onSignIn: () => context.push(AppRoutes.login),
      ),
      CommunityGateStatus.profileMissing => _CtaView(
        title: localizations.communityGateProfileMissingTitle,
        body: localizations.communityGateProfileMissingBody,
        ctaLabel: localizations.communityGateProfileMissingCta,
        onCta: () => _openEditProfile(context, ref, mode: _EditMode.create),
      ),
      CommunityGateStatus.ready => _ReadyView(state: state),
      CommunityGateStatus.unavailable => _UnavailableView(
        onRetry: () =>
            ref.read(communityProfileControllerProvider.notifier).refresh(),
      ),
      CommunityGateStatus.error => _GateErrorView(
        onRetry: () =>
            ref.read(communityProfileControllerProvider.notifier).refresh(),
      ),
    };
  }

  Future<void> _openEditProfile(
    BuildContext context,
    WidgetRef ref, {
    required _EditMode mode,
  }) async {
    final profile = state.profile;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => EditProfileScreen(
          mode: switch (mode) {
            _EditMode.create => EditProfileMode.create,
            _EditMode.edit => EditProfileMode.edit,
          },
          initialProfile: profile,
        ),
      ),
    );
    // Refresh on the way back so a successful create / update
    // flips the gate from ``profile-missing`` -> ``ready`` (or
    // updates the read-only summary in the ready view). The check
    // is on the context's mounted property, not ``ref.mounted`` —
    // ``ref`` belongs to ``_GateBody`` and is disposed when the
    // widget leaves the tree; the navigator's context is the
    // reliable liveness signal.
    if (!context.mounted) return;
    await ref.read(communityProfileControllerProvider.notifier).refresh();
  }
}

enum _EditMode { create, edit }

class _StatusView extends StatelessWidget {
  const _StatusView({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      // Görgethető, `min` fő-tengellyel (2026-09-05): fekvő tájolásban,
      // 2.0-s szöveg-méretnél a szöveg magasabb, mint a képernyő, és a
      // `Center > Column` 8px-et túlcsordult. Egy túlcsorduló
      // akadálymentességi állapot nem „csúnya", hanem OLVASHATATLAN: a
      // szöveg alja levágódik.
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(body, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _CtaView extends StatelessWidget {
  const _CtaView({
    required this.title,
    required this.body,
    required this.ctaLabel,
    required this.onCta,
    this.ctaKey,
  });

  final String title;
  final String body;
  final String ctaLabel;
  final VoidCallback onCta;

  /// Stable identifier for the button, so a widget test can name the
  /// CTA without depending on the translated label.
  final Key? ctaKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      // Ugyanaz a görgethető alak, mint a `_StatusView`-ban — itt a
      // gomb miatt még korábban csordul túl.
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(body, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              SsButton(key: ctaKey, onPressed: onCta, label: ctaLabel),
            ],
          ),
        ),
      ),
    );
  }
}

/// The ``loggedOut`` state (R21, audit MI6).
///
/// MÉRT hiba: the state rendered a bare [_StatusView] — "Sign in to use
/// Community" with no control that could take the user anywhere. The
/// ``communityGateLoggedOutCta`` string had been sitting in the ARB
/// unused since E09-R06.
///
/// The CTA ``push``-es ``/login``, it does not ``go``: ``go`` replaces the
/// whole stack, and the login screen pops itself on success (the R17
/// finding), so a ``go`` would strand the user on a one-page navigator.
///
/// With [accountEnabled] off the CTA is dropped — there is no account
/// layer to sign in to, and the router does not register ``/login`` at
/// all, so the button could only lead to a 404. (That combination is not
/// reachable today: the controller answers ``disabled`` before it ever
/// answers ``loggedOut``. The guard is the belt-and-braces that keeps the
/// two flags' relationship from becoming an implicit invariant.)
class _LoggedOutView extends StatelessWidget {
  const _LoggedOutView({required this.accountEnabled, required this.onSignIn});

  final bool accountEnabled;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    if (!accountEnabled) {
      return _StatusView(
        title: localizations.communityGateLoggedOutTitle,
        body: localizations.communityGateLoggedOutBody,
      );
    }
    return _CtaView(
      ctaKey: const Key('community-gate-sign-in'),
      title: localizations.communityGateLoggedOutTitle,
      body: localizations.communityGateLoggedOutBody,
      ctaLabel: localizations.communityGateLoggedOutCta,
      onCta: onSignIn,
    );
  }
}

/// The ``unavailable`` state — the server does not host Community (R12,
/// audit §5.2).
///
/// Deliberately NOT the generic error view: that copy blames the
/// connection ("check your connection") and invites a reload that can only
/// fail again, while the measured truth is a server-side switch
/// (``STRUMSIGHT_COMMUNITY_ENABLED=false``) that no amount of retrying from
/// the phone changes. The card says which of the two it is; Retry stays,
/// because the moment an operator flips that switch the next attempt does
/// succeed.
///
/// Same scrollable shape as [_StatusView] / [_CtaView] — landscape at 2.0
/// text scale is taller than the viewport.
class _UnavailableView extends StatelessWidget {
  const _UnavailableView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SsContentCard(
                key: const Key('community-gate-unavailable'),
                icon: Icons.cloud_off_outlined,
                title: localizations.communityGateUnavailableTitle,
                message: localizations.communityGateUnavailableBody,
              ),
              const SizedBox(height: 24),
              SsButton(
                key: const Key('community-gate-unavailable-retry'),
                onPressed: onRetry,
                label: localizations.communityGateRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The ``error`` state (R20, audit M6.3) — the profile probe failed for a
/// reason that says nothing about whether a profile exists (a timeout, a
/// 500, a dropped connection).
///
/// MÉRT hiba: every such failure used to render the ``profile-missing``
/// CTA, so a learner who already owns a profile was invited to create a
/// second one the moment their connection blinked. This view says what
/// actually happened and offers the only honest next step — try again.
/// Deliberately mirrors [_UnavailableView]: same card + retry shape, its
/// own keys, and its own copy, so a test can tell the two apart.
class _GateErrorView extends StatelessWidget {
  const _GateErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SsContentCard(
                key: const Key('community-gate-error'),
                icon: Icons.error_outline,
                title: localizations.communityGateErrorTitle,
                message: localizations.communityGateErrorBody,
              ),
              const SizedBox(height: 24),
              SsButton(
                key: const Key('community-gate-error-retry'),
                onPressed: onRetry,
                label: localizations.communityGateRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The ``ready`` state — the Community HUB.
///
/// MÉRT hiba (2026-09-06, WP-C): a 13 community képernyő route-ja
/// létezett, de a szállított felületről SEMMI nem vezetett hozzájuk —
/// a kapu `ready` állapota egyetlen „Edit profile" gombot mutatott. A
/// funkció tehát a felhasználó számára nem létezett.
///
/// A hub ezért NEVESÍTETT belépési pontot ad mind a tizenháromhoz. A
/// navigáció `context.push` (go_router), NEM `context.go`: a vissza-
/// gomb a hubra tér vissza, nem a fa gyökerére. A `Navigator.push` a
/// profil-szerkesztőnél marad — az nem regisztrált útvonal.
///
/// Két belépő zászló alatt áll, ugyanazzal a mintázattal, amivel a
/// router is kapuz: az író-felület a `communityWritesEnabled`, a
/// klubok a `communityClubsEnabled` alatt. Egy kikapcsolt zászlónál a
/// route sincs regisztrálva, tehát a gomb egy 404-re vinne.
class _ReadyView extends ConsumerWidget {
  const _ReadyView({required this.state});

  final CommunityProfileState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final profile = state.profile;
    final flags = ref.watch(appConfigProvider).flags;
    // A saját profil nyilvános azonosítója — a követők / követettek
    // listája ezzel a paraméterrel nyílik. Profil nélkül (elvileg
    // elérhetetlen a `ready` ágon) a két bejegyzés kimarad, nem egy
    // üres azonosítóval navigál.
    final profileId = profile?.userId.value;
    return SingleChildScrollView(
      // A7 — 2.0-s szöveg-méretnél a hub végig görgethető marad.
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            profile?.handle.value ?? '—',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            profile?.displayName ?? '—',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SsButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => EditProfileScreen(
                    mode: EditProfileMode.edit,
                    initialProfile: profile,
                  ),
                ),
              ),
              label: localizations.communityHubEditProfile,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            localizations.communityHubSectionTitle,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _HubEntry(
            icon: Icons.dynamic_feed,
            label: localizations.communityHubFeed,
            route: AppRoutes.communityFeed,
          ),
          if (flags.communityWritesEnabled)
            _HubEntry(
              icon: Icons.edit_note,
              label: localizations.communityHubCompose,
              route: AppRoutes.communityCompose,
            ),
          if (flags.communityClubsEnabled)
            _HubEntry(
              icon: Icons.groups_outlined,
              label: localizations.communityHubClubs,
              route: AppRoutes.communityClubs,
            ),
          _HubEntry(
            icon: Icons.notifications_none,
            label: localizations.communityHubNotifications,
            route: AppRoutes.communityNotifications,
          ),
          _HubEntry(
            icon: Icons.search,
            label: localizations.communityHubSearch,
            route: AppRoutes.communitySearch,
          ),
          _HubEntry(
            icon: Icons.bookmark_border,
            label: localizations.communityHubBookmarks,
            route: AppRoutes.communityBookmarks,
          ),
          _HubEntry(
            icon: Icons.emoji_events_outlined,
            label: localizations.communityHubChallenges,
            route: AppRoutes.communityChallenges,
          ),
          if (profileId != null) ...[
            _HubEntry(
              icon: Icons.people_outline,
              label: localizations.communityHubFollowers,
              route: AppRoutes.communityFollowers.replaceFirst(
                ':profileId',
                profileId,
              ),
            ),
            _HubEntry(
              icon: Icons.person_add_alt,
              label: localizations.communityHubFollowing,
              route: AppRoutes.communityFollowing.replaceFirst(
                ':profileId',
                profileId,
              ),
            ),
          ],
          _HubEntry(
            icon: Icons.shield_outlined,
            label: localizations.communityHubSafety,
            route: AppRoutes.communitySafety,
          ),
          if (profile != null) ...[
            const SizedBox(height: 24),
            _MyPostsSection(profileId: profile.userId),
          ],
          const SizedBox(height: 16),
          Text(
            localizations.communityEditBadgesBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// A megnevezett profil posztjai — `GET /community/profiles/{id}/posts`
/// (E17-R11).
///
/// A végpont 2026-09-06-ig NEM létezett, ezért a repository-metódus
/// `UnimplementedError`-t dobott, és a kliensben egyetlen felület sem
/// hívta. A hub „A posztjaid" szakasza az első valódi fogyasztója.
///
/// A hiba SZÁNDÉKOSAN kibukik a providerből: a szerver egyetlen, egyforma
/// 404-et ad a nem létező, a blokkolt és a nem látható profilra, tehát a
/// kliens nem tudja (és nem is szabad tudnia) melyik történt — üres listát
/// adni viszont azt ÁLLÍTANÁ, hogy a profilnak nincs posztja.
final communityProfilePostsProvider = FutureProvider.autoDispose
    .family<CommunityPage<CommunityPost>, PublicUserId>((ref, userId) async {
      final repository = ref.watch(communityFeedRepositoryProvider);
      return repository.profilePosts(
        userId: userId,
        cursor: const CursorPage.initial(),
        limit: _kProfilePostsPageSize,
      );
    });

/// A hub poszt-szakaszának lapmérete. A szakasz nem lapoz — az utolsó
/// néhány poszt a cél, nem a teljes archívum.
const int _kProfilePostsPageSize = 10;

/// A hub „A posztjaid" szakasza.
///
/// Három, egymást KIZÁRÓ állapot, mindhárom kimondva: töltés, hiba
/// (újrapróbálás-gombbal), és adat — ahol az üres lista VALÓDI állítás,
/// mert a szerver válaszolt.
class _MyPostsSection extends ConsumerWidget {
  const _MyPostsSection({required this.profileId});

  final PublicUserId profileId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context);
    final postsAsync = ref.watch(communityProfilePostsProvider(profileId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          localizations.communityHubMyPostsTitle,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        ...postsAsync.when(
          data: (page) => page.items.isEmpty
              ? <Widget>[
                  Text(
                    localizations.communityHubMyPostsEmpty,
                    key: const Key('community-hub-my-posts-empty'),
                  ),
                ]
              : <Widget>[
                  for (final post in page.items)
                    ListTile(
                      key: Key('community-hub-my-post-${post.id.value}'),
                      title: Text(post.body ?? ''),
                    ),
                ],
          loading: () => const <Widget>[
            Center(child: CircularProgressIndicator()),
          ],
          // A hiba NEM üres listaként jelenik meg: az azt állítaná, hogy
          // nincs posztod, holott az igazság az, hogy nem tudjuk.
          error: (_, _) => <Widget>[
            Text(
              localizations.communityHubMyPostsError,
              key: const Key('community-hub-my-posts-error'),
            ),
            const SizedBox(height: 8),
            SsButton(
              variant: SsButtonVariant.secondary,
              onPressed: () =>
                  ref.invalidate(communityProfilePostsProvider(profileId)),
              label: localizations.communityHubMyPostsRetry,
            ),
          ],
        ),
      ],
    );
  }
}

/// One hub row. A `key` a cella-azonosító a widget-tesztnek: a
/// felirat fordítás-függő, a `Key` nem.
class _HubEntry extends StatelessWidget {
  const _HubEntry({
    required this.icon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final String label;

  /// A már behelyettesített útvonal (a paraméteres útvonalaknál a
  /// hívó cseréli ki a `:profileId`-t).
  final String route;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('community-hub-entry-$route'),
      leading: Icon(icon),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(route),
    );
  }
}
