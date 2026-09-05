/// Community gate — the four-state entry screen (E09-R06, ADR 0400
/// §5, brief §5.1).
///
/// The gate is intentionally minimal. The brief §5.1 invariant is
/// that a Community profile is NEVER created implicitly — the gate
/// shows the right entry point for the current state and lets the
/// user advance explicitly:
///
/// * ``disabled`` — the account layer is off; show a "feature not
///   available" message. No further interaction.
/// * ``loggedOut`` — the user is not signed in. Show a CTA to sign
///   in / sign up. (The CTA does not launch the auth screen
///   directly — that is owned by the auth feature; the gate
///   mirrors the existing ``accountEnabledProvider`` /
///   ``authControllerProvider`` pattern from ``lib/features/auth/
///   public.dart`` and only shows the right message.)
/// * ``profileMissing`` — the user is signed in but has no
///   profile. Show the CTA that opens the edit-profile screen in
///   create mode.
/// * ``ready`` — the user is signed in AND has a profile. Show a
///   minimal read-only summary and an "Edit" CTA that opens the
///   edit-profile screen in edit mode.
///
/// The screen holds no local state of its own — the controller is
/// the single source of truth (the four states, the loaded profile,
/// the in-flight flag). The gate is a pure projection of the
/// controller.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:strumsight/core/design_system/public.dart';

import '../../../../l10n/app_localizations.dart';
import '../../application/controllers/profile_controller.dart';
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
        appBar: AppBar(
          title: Text(localizations.communityGateProfileMissingTitle),
        ),
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
                    label: 'Retry',
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
}

class _GateBody extends ConsumerWidget {
  const _GateBody({required this.state});

  final CommunityProfileState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    return switch (state.status) {
      CommunityGateStatus.disabled => _StatusView(
        title: localizations.communityGateDisabledTitle,
        body: localizations.communityGateDisabledBody,
      ),
      CommunityGateStatus.loggedOut => _StatusView(
        title: localizations.communityGateLoggedOutTitle,
        body: localizations.communityGateLoggedOutBody,
      ),
      CommunityGateStatus.profileMissing => _CtaView(
        title: localizations.communityGateProfileMissingTitle,
        body: localizations.communityGateProfileMissingBody,
        ctaLabel: localizations.communityGateProfileMissingCta,
        onCta: () => _openEditProfile(context, ref, mode: _EditMode.create),
      ),
      CommunityGateStatus.ready => _ReadyView(state: state),
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
  });

  final String title;
  final String body;
  final String ctaLabel;
  final VoidCallback onCta;

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
              SsButton(onPressed: onCta, label: ctaLabel),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadyView extends ConsumerWidget {
  const _ReadyView({required this.state});

  final CommunityProfileState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = AppLocalizations.of(context);
    final profile = state.profile;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Text(
            profile?.handle.value ?? '—',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            profile?.displayName ?? '—',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          SsButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => EditProfileScreen(
                  mode: EditProfileMode.edit,
                  initialProfile: profile,
                ),
              ),
            ),
            label: 'Edit profile',
          ),
          const SizedBox(height: 12),
          // A7 — 2.0 text scale must not break the read-only view.
          // The layout is scrollable + single-column so a 2× font
          // size does not push the CTA off the screen.
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                localizations.communityEditBadgesBody,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
