---
id: 013
topic: Growth & virality for StrumSight — how music apps actually grow, and the shareable "Strum Card" (the moat as content)
tags: [growth, virality, sharing, retention, streaks, gamification, k-factor, ugc, share-plus, deep-links, roadmap]
sources:
  - Spotify Wrapped teardown — 9:16 + watermark + one-tap share → 21% Dec-2020 install spike (nogood.io/blog/spotify-wrapped-marketing-strategy)
  - Trophy "streaks feature gamification examples" — 18M-streak dataset: streak-freeze 11.6→17.2 days (+48%), median streak 4 days, Friday = 25% of losses (trophy.so/blog/streaks-feature-gamification-examples)
  - StriveCloud Duolingo case — streaks drive 55% next-day return; loss-aversion (strivecloud.io/blog/gamification-examples-boost-user-retention-duolingo)
  - Yousician gamification case (trophy.so/blog/yousician-gamification-case-study); Chordify premium 4-songs/day freemium (chordify.net/premium); Ultimate Guitar UG IQ UGC (ultimate-guitar.com/about/ug-iq.htm)
  - K-factor benchmarks — 0.3–0.7 healthy, K>1 rare/temporary; Dropbox referral K 0.24→0.56 (saxifrage.xyz/post/k-factor-benchmarks; review.firstround.com/glossary/k-factor-virality)
  - TikTok branded hashtag challenge data — 4x ad recall; ZALORA CPI −27% (stackmatix.com/blog/tiktok-branded-hashtag-challenge-guide; wersm.com tiktok-branded-hashtag-challenge-case-study-zalora)
  - Flutter offline capture/share — RepaintBoundary→toImage→PNG + share_plus; deferred-deep-link attribution needs Branch (freecodecamp.org save-share-flutter-widgets; branch.io/glossary/deferred-deep-linking)
---

# Growth & virality: make the moat shareable

**Thesis.** StrumSight's one uncontested feature — seeing **DOWN ↓ / UP ↑**
strokes (no competitor: Chordify, Chord AI, Yousician, Simply Guitar, Ultimate
Guitar, GuitarTuna does it) — is also its best growth asset. Turn every practice
clip into a **shareable card that puts the ↓/↑ pattern on screen**: the artifact
*is* the ad, and it carries an install link back. This is the Spotify-Wrapped
playbook applied to our moat.

## What the top music apps actually do to grow
- **Free-utility wedge → upsell.** GuitarTuna (100M+ installs) acquires cheaply
  with a free tuner, then cross-sells chords/lessons. StrumSight's tuner + live
  chord view is the same wedge.
- **Freemium throttle.** Chordify caps the free tier at 4 songs/day. (We skip
  monetization for now — noted, not adopted.)
- **UGC flywheel.** Ultimate Guitar's catalog is user-submitted, governed by a
  reputation system (UG IQ). Cheapest reach multiplier = a **branded hashtag**.
- **Gamified daily habit.** Yousician/Simply: points, streaks, challenges,
  subtle leaderboards, "don't break your streak" nudges.
- None detect strum direction — **uncontested white space**, our wedge to be
  *distinctive*, not just another chord app.

## The shareable-card evidence (why this is #1)
Spotify Wrapped is the reference implementation of a "results card":
- **9:16 vertical**, sized for Stories/TikTok so users never crop (friction
  removal). We render the Strum Card at **360×640 (9:16)**.
- Vibrant, high-contrast, a **one-tap share button**, and **branding baked into
  the asset** (watermark = attribution).
- Outcome: **21% install spike (Dec 2020)**; ~500M shares in 24h (2025).
Branded hashtag challenges add reach: TikTok data shows **4x ad recall**; ZALORA
**CPI −27%**. Cost to us = copy + a `#StrumSightChallenge` tag in the caption.

## Retention makes viral installs compound (don't skip it)
A viral install that churns is wasted. Streaks are the best-evidenced retention
mechanic:
- **55% of Duolingo users return next day** to keep a streak (loss aversion).
- Trophy's 18M-streak data: **streak-freeze lifts avg streak +48% (11.6→17.2
  days)**; **median streak is 4 days → protect days 3–7**; **Friday = 25% of all
  losses** (nudge then).
This is the top follow-up (see roadmap).

## K-factor reality (set honest expectations)
`K = invites × conversion`. **K>1 (self-sustaining) is rare and temporary**;
realistic target **K ≈ 0.3–0.7**, i.e. virality as **CAC reduction**, not a
growth engine on its own. Dropbox's referral moved K 0.24→0.56. "We'll go viral"
is hype; "shareable cards + a light referral lower blended CAC" is the real bet.

## What's offline-feasible in Flutter (our on-device constraint)
| Feature | Offline? | How |
|---|---|---|
| PNG results-card export | ✅ | `RepaintBoundary`(GlobalKey) → `toImage` → `dart:ui` PNG bytes |
| Native share sheet | ✅ | `share_plus` `SharePlus.instance.share(ShareParams(files/text))` |
| Watermark/branding | ✅ | just widgets inside the captured subtree |
| Animated/video card | ⚠️ | frame capture + encode; `ffmpeg_kit_flutter` was discontinued Apr-2025 → use `ffmpeg_kit_flutter_new` / `widget_record_video` |
| Deep link (open app) | ✅ | `app_links` |
| Deferred-deep-link **attribution** | ❌ | needs Branch (`flutter_branch_sdk`) — the one hosted piece |

## AS BUILT (round 29) — the static Strum Card
Shipped in `lib/features/share/`: `share_content.dart` (pure caption + ↓/↑ glyph
builders, unit-tested), `widgets/strum_card.dart` (9:16 brand card: chords, the
**↓/↑ arrow pattern hero**, BPM/down/up/length stat chips, wordmark + moat
footer), `share_service.dart` (RepaintBoundary→PNG→`share_plus`, with a
text-only fallback), `screens/share_preview_screen.dart` (preview + one-tap
share; card wrapped in a `RepaintBoundary` at native size inside a `FittedBox`
so capture stays full-res). Entry points: a share action on the **Analyze**
done view and the **Library** session detail AppBar. Caption is
English-global (hashtags/symbols travel), on-screen labels localised (en/hu).
`installUrl` = the public GitHub Release (swap for a store/landing URL later).
14 tests. Deliberately the **static** card first (research rank #2: the
fast-to-ship, low-risk v1 of the "Strum Cam" video idea).

## Roadmap (ranked, from the research)
1. **"Strum Cam" video/animated card** — a 9:16 clip with the ↓/↑ arrows +
   chords animating in sync with the audio. The ultimate moat-as-content, but
   heavier (frame capture + a maintained encoder). Static card ships its value now.
2. **Streak + daily strum-pattern challenge** (with streak-freeze, Friday nudge)
   — the best-evidenced retention loop; makes viral installs compound.
3. **`#StrumSightChallenge` UGC prompt** — already seeded in the caption; grow
   into an in-app challenge feed.
4. **Referral via deferred deep links** (Branch) — closes and *measures* the
   share→install loop; the one hosted dependency. Target K ≈ 0.3–0.7.

## Honesty flags (from the research)
- Evidence-backed: streak retention numbers; Wrapped's 9:16+watermark+share →
  measurable installs; challenge CPI reduction; K 0.3–0.7 realistic.
- Plausible-but-unproven: that any *specific* guitar clip "will go viral"
  (trend-driven — a portfolio of bets), and vendor-blog gamification percentages.
  Lean on the moat: the ↓/↑ overlay is the one genuinely novel thing that earns
  organic reach.
