import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/config/app_config.dart';
import '../../../app/routing/adaptive_shell_routes.dart';
import '../../../core/design_system/public.dart';
import '../../../l10n/app_localizations.dart';
import '../../learn/public.dart';
import '../onboarding_provider.dart';
import 'permission_primer_screen.dart';
import 'first_win_stage_screen.dart';

/// First-run onboarding: three glanceable pages that teach the moat (↓/↑),
/// tease the streak, and prime the mic permission before dropping into Live.
/// Minimal by design (Simply Guitar's lesson: a few taps, then play). Growth =
/// activation — convert every viral install into an active user (chunk 013).
///
/// SDD Ch13 Kör 16 additions: the flow is checkpointed (A6/A7), and both
/// carousel CTAs that request the mic (`onboardFirstWin`, `onboardStart`)
/// route THROUGH the [OnboardingStep.permission] checkpoint — the system
/// permission dialog is never reachable without the primer having been on
/// screen first (ADR 0281 §1/§5.1, A1). [_finish]/[_firstWin] record which
/// completion is pending, advance the checkpoint, and let
/// [PermissionPrimerScreen]'s `onGranted`/`onSkipped` resume it
/// ([_onPermissionResolved]) — best-effort, exactly like the pre-checkpoint
/// behaviour: a skip or a denial still completes onboarding, the Live screen
/// re-requests if still ungranted. A build that resumes mid-flow (checkpoint
/// already at [OnboardingStep.permission], e.g. the app was killed right
/// there) has no pending completion to resume, so it defaults to the plain
/// finish (shell entry location, no forced first-win lesson) rather than
/// guessing.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.onDone, this.onFirstWin});

  /// Where to go when finished; defaults to the shell entry location
  /// (`entryLocationFor`, ADR 0508 D1 — overridable in tests).
  final VoidCallback? onDone;

  /// Where the "first win" CTA lands (chunk 017 rec #4); defaults to the
  /// shell entry location with the [Lessons.firstWin] mini-lesson pushed on
  /// top.
  final VoidCallback? onFirstWin;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pager = PageController();
  int _page = 0;
  bool _finishing = false;

  /// Which completion to resume once the permission checkpoint resolves —
  /// set by whichever of [_finish]/[_firstWin] requested the mic, consumed
  /// by [_onPermissionResolved]. `null` (no carousel CTA in flight, e.g. a
  /// build that resumed straight at [OnboardingStep.permission]) resumes as
  /// a plain finish — see the class doc-comment.
  Future<void> Function()? _afterPermission;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  /// The checkpoint read, defensive against a Riverpod-free construction
  /// (no ancestor `ProviderScope`) — a bare layout-smoke test builds this
  /// screen directly under a themed `MaterialApp` with no `ProviderScope`
  /// (the migrated screen's `SsButton` needs the design-system theme
  /// extensions, so the harness can no longer be themeless — §0.0/R2). A
  /// missing scope degrades to the safe default (show the intro from the
  /// top), the same fail-safe philosophy `OnboardingController.readSeen`
  /// already applies to a corrupt stored value.
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

  /// Either carousel CTA that wants the mic: instead of requesting it cold,
  /// it checkpoints [OnboardingStep.permission] — the build's step-switch
  /// then shows [PermissionPrimerScreen], which owns the ONLY call into the
  /// permission gateway (E01-R09 §9.1, ADR 0281 §1/§5.1, A1).
  Future<void> _finish({bool requestMic = false}) async {
    if (_finishing) return;
    if (requestMic) {
      _finishing = true;
      _afterPermission = _completeFinish;
      await _advanceStep(OnboardingStep.permission);
      return;
    }
    _finishing = true;
    await _completeFinish();
  }

  Future<void> _completeFinish() async {
    final router = widget.onDone == null ? GoRouter.of(context) : null;
    final entryLocation = entryLocationFor(
      ref.read(appConfigProvider).flags.adaptiveShellEnabled,
    );
    await ref.read(onboardingSeenProvider.notifier).complete();
    await _advanceStep(OnboardingStep.done);
    (widget.onDone ?? () => router!.go(entryLocation))();
  }

  /// The activation shortcut (chunk 017 rec #4, r155): straight from the last
  /// onboarding page into a 30-second SCORED mini-lesson — the aha moment
  /// ("it grades my strumming hand") lands inside the first two minutes.
  Future<void> _firstWin() async {
    if (_finishing) return;
    _finishing = true;
    _afterPermission = _completeFirstWin;
    await _advanceStep(OnboardingStep.permission);
  }

  Future<void> _completeFirstWin() async {
    final useDefaultNavigation = widget.onFirstWin == null;
    final router = useDefaultNavigation ? GoRouter.of(context) : null;
    final navigator = useDefaultNavigation
        ? Navigator.of(context, rootNavigator: true)
        : null;
    final entryLocation = entryLocationFor(
      ref.read(appConfigProvider).flags.adaptiveShellEnabled,
    );
    await ref.read(onboardingSeenProvider.notifier).complete();
    await _advanceStep(OnboardingStep.done);
    (widget.onFirstWin ??
        () {
          router!.go(entryLocation);
          // Push AFTER the route swap lands: a pageless route pushed now
          // would anchor to the outgoing /welcome page and be disposed with
          // it (r156 rig catch #2 — the first fix still lost the push).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // A First-Win ÁLLOMÁS megy be ELŐSZÖR, a mini-lecke fölé. Amikor
            // a lecke lezárul, az állomás kerül elő, és a valós
            // `onboardingFirstWinConfidenceProvider`-ből megmutatja, sikerült-e
            // a kísérlet.
            //
            // Miért nem kap saját top-level route-ot (E17-R01, ADR 0520 §5.1):
            // az állomás a FOLYAMAT egy lépése. Egy `/first-win` cím két
            // belépési pontot adna ugyanahhoz az állapothoz, és megsértené az
            // `entryLocationFor(...)` egy-forrás szabályát (ADR 0508 D1).
            navigator!.push(
              MaterialPageRoute<void>(
                builder: (_) => FirstWinStageScreen(
                  // Egyik ág sem navigál literál útvonalra: mindkettő
                  // ugyanabból a forrásból veszi a célt, amit a Skip/finish
                  // ág is használ.
                  onContinue: () => router.go(entryLocation),
                  onSkip: () => router.go(entryLocation),
                ),
              ),
            );
            navigator.push(
              MaterialPageRoute<void>(
                builder: (_) => LearnScreen(lesson: Lessons.firstWin),
              ),
            );
          });
        })();
  }

  /// Fires from the primer's `onGranted` AND `onSkipped` alike — best-effort
  /// priming means the flow completes either way, matching the
  /// pre-checkpoint contract (the Live screen re-requests if still
  /// ungranted).
  Future<void> _onPermissionResolved() {
    final resume = _afterPermission ?? _completeFinish;
    _afterPermission = null;
    return resume();
  }

  void _next(int lastIndex) {
    if (_page >= lastIndex) {
      _finish(requestMic: true);
    } else {
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
      // Reached both from a carousel CTA (A1) and from a resumed checkpoint
      // (A6/A7) — either way, `onGranted`/`onSkipped` resume whichever
      // completion was pending (see the class doc-comment).
      OnboardingStep.permission => PermissionPrimerScreen(
        onGranted: _onPermissionResolved,
        onSkipped: _onPermissionResolved,
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
              child: SsButton(
                variant: SsButtonVariant.tertiary,
                label: l10n.onboardSkip,
                onPressed: _finish,
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
            const SizedBox(height: SsSpacing.space4),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SsSpacing.space6,
                0,
                SsSpacing.space6,
                SsSpacing.space5,
              ),
              child: Column(
                children: [
                  // Stays a literal FilledButton (not SsButton): SsButton
                  // lays its label out in a Flexible(overflow:
                  // TextOverflow.ellipsis), which caps it to one line — the
                  // hu "Próbáld ki az első győzelmed — 30 mp" copy truncates
                  // at the required 2.0x text scale on phone width (E15-R11
                  // review MAJOR-1). A bare FilledButton's Text has no such
                  // cap, so it wraps across lines instead of clipping —
                  // same documented-exception class as the
                  // streak_detail_screen.dart recovery CTA (E15-R08 review
                  // M3).
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onLast ? _firstWin : () => _next(last),
                      child: Text(
                        onLast ? l10n.onboardFirstWin : l10n.onboardNext,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  // The quieter path for players who just want to explore.
                  if (onLast)
                    SsButton(
                      variant: SsButtonVariant.tertiary,
                      label: l10n.onboardStart,
                      onPressed: () => _finish(requestMic: true),
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    // A9 (golden gate, textScaler 2.0): the intro page must not overflow at
    // a large text size — scrollable rather than clipped/cut off.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: SsSpacing.space8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showArrows)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.arrow_downward, size: 64, color: colors.brand),
                const SizedBox(width: SsSpacing.space3),
                Icon(
                  Icons.arrow_upward,
                  size: 64,
                  color: colors.confidenceHigh,
                ),
              ],
            )
          else
            Icon(icon, size: 84, color: colors.brand),
          const SizedBox(height: SsSpacing.space8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w800,
              fontSize: 26,
            ),
          ),
          const SizedBox(height: SsSpacing.space3),
          Text(
            body,
            textAlign: TextAlign.center,
            style: typography.bodyMedium.copyWith(
              fontSize: 15,
              height: 1.4,
              color: colors.textSecondary,
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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: SsSpacing.space1),
            width: i == active ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == active
                  ? colors.brand
                  : colors.brand.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(SsRadius.xs),
            ),
          ),
      ],
    );
  }
}
