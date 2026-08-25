import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routing/app_route.dart';
import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../learn/public.dart';
import '../onboarding_provider.dart';
import 'first_win_stage_screen.dart';
import 'permission_primer_screen.dart';

/// First-run onboarding (SDD Ch13 Kör 16, ADR 0281): a three-page carousel
/// teaching the moat (↓/↑) and the streak, then a mic-permission primer, then
/// a scored first-win mini Stage. Progressive and resumable — an interruption
/// resumes at the checkpointed [OnboardingStep], never restarts the whole
/// flow (A6/A7).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.onDone, this.onFirstWin});

  /// Where to go when finished; defaults to the Live tab (overridable in tests).
  final VoidCallback? onDone;

  /// Where the "first win" CTA lands once the mini Stage reports a genuine
  /// success (chunk 017 rec #4); defaults to the Live tab with the
  /// [Lessons.firstWin] mini-lesson pushed on top.
  final VoidCallback? onFirstWin;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pager = PageController();
  int _page = 0;
  bool _finishing = false;

  /// Which last-page CTA sent the user into the permission primer — decides
  /// what happens once the primer resolves (Allow, Not now, or already
  /// permanently denied): the primary CTA continues into the first-win
  /// Stage, the quieter one finishes onboarding directly.
  bool _wantsFirstWin = true;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  /// The checkpoint read, defensive against a Riverpod-free construction
  /// (no ancestor `ProviderScope`) — a bare layout-smoke test builds this
  /// screen directly under a plain `MaterialApp`. A missing scope degrades
  /// to the safe default (show the intro from the top), the same
  /// fail-safe philosophy `OnboardingController.readSeen` already applies
  /// to a corrupt stored value.
  OnboardingStep _currentStep() {
    try {
      return ref.watch(onboardingStepProvider);
    } on StateError {
      return OnboardingStep.welcome;
    }
  }

  Future<void> _advanceStep(OnboardingStep step) async {
    try {
      await ref.read(onboardingStepProvider.notifier).advanceTo(step);
    } on StateError {
      // No ProviderScope to persist into — nothing to do.
    }
  }

  void _goToPermissionPrimer({required bool wantsFirstWin}) {
    _wantsFirstWin = wantsFirstWin;
    _advanceStep(OnboardingStep.permission);
  }

  void _onPrimerResolved() {
    if (_wantsFirstWin) {
      _advanceStep(OnboardingStep.firstWin);
    } else {
      _completeOnboarding();
    }
  }

  /// Marks onboarding complete and leaves via [widget.onDone] (or the
  /// default: the Live tab).
  Future<void> _completeOnboarding() async {
    if (_finishing) return;
    _finishing = true;
    final router = widget.onDone == null ? GoRouter.of(context) : null;
    await ref.read(onboardingSeenProvider.notifier).complete();
    await _advanceStep(OnboardingStep.done);
    (widget.onDone ?? () => router!.go(AppRoutes.live))();
  }

  /// The activation shortcut (chunk 017 rec #4, r155): from a genuine
  /// first-win success into a 30-second SCORED mini-lesson — the aha moment
  /// ("it grades my strumming hand") lands inside the first two minutes.
  Future<void> _completeWithFirstWin() async {
    if (_finishing) return;
    _finishing = true;
    final useDefaultNavigation = widget.onFirstWin == null;
    final router = useDefaultNavigation ? GoRouter.of(context) : null;
    final navigator = useDefaultNavigation
        ? Navigator.of(context, rootNavigator: true)
        : null;
    await ref.read(onboardingSeenProvider.notifier).complete();
    await _advanceStep(OnboardingStep.done);
    (widget.onFirstWin ??
        () {
          router!.go(AppRoutes.live);
          // Push AFTER the route swap lands: a pageless route pushed now
          // would anchor to the outgoing /welcome page and be disposed with
          // it (r156 rig catch #2 — the first fix still lost the push).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            navigator!.push(
              MaterialPageRoute<void>(
                builder: (_) => LearnScreen(lesson: Lessons.firstWin),
              ),
            );
          });
        })();
  }

  void _next(int lastIndex) {
    if (_page < lastIndex) {
      _pager.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_currentStep()) {
      OnboardingStep.welcome => _buildWelcomeCarousel(context),
      OnboardingStep.permission => PermissionPrimerScreen(
        onGranted: _onPrimerResolved,
        onSkipped: _onPrimerResolved,
      ),
      OnboardingStep.firstWin => FirstWinStageScreen(
        onContinue: _completeWithFirstWin,
        onSkip: _completeOnboarding,
      ),
      OnboardingStep.done => const SizedBox.shrink(),
    };
  }

  Widget _buildWelcomeCarousel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pages = <_Page>[
      _Page(
        icon: Icons.music_note,
        title: l10n.onboardTitle1,
        body: l10n.onboardBody1,
      ),
      _Page(
        icon: Icons.swap_vert,
        title: l10n.onboardTitle2,
        body: l10n.onboardBody2,
        showArrows: true,
      ),
      _Page(
        icon: Icons.local_fire_department,
        title: l10n.onboardTitle3,
        body: l10n.onboardBody3,
      ),
    ];
    final last = pages.length - 1;
    final onLast = _page == last;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _completeOnboarding,
                child: Text(l10n.onboardSkip),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pager,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => pages[i],
              ),
            ),
            _Dots(count: pages.length, active: _page),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                children: [
                  FilledButton(
                    onPressed: onLast
                        ? () => _goToPermissionPrimer(wantsFirstWin: true)
                        : () => _next(last),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                    ),
                    child: Text(
                      onLast ? l10n.onboardFirstWin : l10n.onboardNext,
                    ),
                  ),
                  // The quieter path for players who just want to explore —
                  // still primed for the mic through the same primer/A1.
                  if (onLast)
                    TextButton(
                      onPressed: () =>
                          _goToPermissionPrimer(wantsFirstWin: false),
                      child: Text(l10n.onboardStart),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.icon,
    required this.title,
    required this.body,
    this.showArrows = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool showArrows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showArrows)
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.arrow_downward, size: 64, color: AppColors.primary),
                SizedBox(width: 12),
                Icon(
                  Icons.arrow_upward,
                  size: 64,
                  color: AppColors.confidenceHigh,
                ),
              ],
            )
          else
            Icon(icon, size: 84, color: AppColors.primary),
          const SizedBox(height: 32),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w800,
              fontSize: 26,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});
  final int count;
  final int active;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < count; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: i == active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: i == active
                ? AppColors.primary
                : AppColors.primary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
    ],
  );
}
