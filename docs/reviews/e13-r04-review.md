# E13-R04 — Független review

Brief: `docs/rounds/e13-r04-typography-and-text-scale.md`
Diff: `d01b2f28..b2bf3c96`
Reviewer: Codex Sol (`gpt-5.6-sol`) · Dátum: 2026-08-21
Verdikt: **CHANGES REQUIRED**

## Összegzés

Nyitott BLOCKER: 0 · MAJOR: 1 · MINOR: 0 · NOTE: 1

A tipográfiai contract, a theme-integráció, a text-scale layout és a legacy
forrásparitás célzott gate-je zöld. A független semantics-próba azonban a
Stage Mode kritikus chord nevét kétszer találta ugyanabban a semantics
csomópontban, ezért az accessibility contract javításig nem merge-elhető.

## Acceptance criteria

| # | Teljesült | Bizonyíték |
|---|---|---|
| A1 | ✅ | 1.0/2.0 magasság-növekedés; reviewer fix 88 px mutációja `expected >88, actual 88` hibával piros |
| A2 | ✅ | `BoxFit.scaleDown`, teljes címke; reviewer `TextOverflow.ellipsis` mutációja piros |
| A3 | ✅ | `metricLabel(120, 'BPM') == '120\u00a0BPM'`; normál szóköz mutációja piros |
| A4 | ✅ | mindhárom metric token `FontFeature.tabularFigures()` contractja zöld |
| A5 | ✅ | hosszú magyar fixture 1.0/1.3/2.0/2.5 skálán exception nélkül renderel |
| A6 | ✅ | az új chord komponensben nincs lokális `TextStyle(`; forrásőr zöld |
| A7 | ✅ | `docs/ui/typography.md` rögzíti a heading-hierarchiát és `Semantics(header: true)` használatát |
| A8 | ✅ | mindhárom design-system theme-ből lekérhető `SsTypography`; extension-eltávolítás mutációja több cellát pirosra vitt |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e13-r04-sol-FLzC4P/repo
--brief docs/rounds/e13-r04-typography-and-text-scale.md --base d01b2f28` →
`Legacy scope audit OK`, 9 módosított útvonal, 0 generated/ignored.

## Megállapítások

### F1 — MAJOR — A chord hero kétszer mondja be ugyanazt a chord nevet

- **Fájl:** `lib/core/design_system/components/music/ss_chord_hero_text.dart:23`
- **Probléma:** a külső `Semantics(label: chordName)` megtartja a gyermek
  `Text` saját semantics-ét is. A tényleges összefűzött label
  `Cmaj7#11\nCmaj7#11`, nem egyetlen `Cmaj7#11`.
- **Bizonyíték:** az izolált reviewer-klónban
  `tester.getSemantics(find.byType(SsChordHeroText)).label` pontosan a fenti
  duplikált értéket adta; az eldobható exact-label assertion piros lett.
- **Hatás:** a képernyőolvasó minden chord-váltásnál kétszer olvassa fel a
  Stage Mode legfontosabb zenei információját, lassítva és összezavarva a
  valós idejű használatot.
- **Kötelező javítás:** a külső semantics legyen az egyetlen felolvasott
  forrás (`excludeSemantics: true` vagy egyenértékű megoldás), és kerüljön
  production regressziós cella a `ss_typography_test.dart` fájlba, amely az
  egyetlen exact chord labelt méri.
- **Státusz:** OPEN

### N1 — NOTE — A független gate első hívása hibás cwd-ből indult

Az első hívás `/tmp` alól futott, ezért a gate a `pubspec.yaml` hiányával
exit 20-at adott. Ugyanabban az izolált klónban, a repo gyökeréből újraindított
artefaktum 8/8 zöld lett; a hibás invokáció nem kód- vagy gate-hiba.

## Gate-bizonyíték

Izolált review-klón `/tmp/review-e13-r04-sol-FLzC4P/repo`, commit
`b2bf3c96`:

- scope-audit: 9 útvonal, 0 sértés;
- format: 1768 fájl, 0 változás;
- analyze: 0 issue;
- typography: 6/6 zöld;
- text-scale overflow: 5/5 zöld;
- foundations compatibility: 3/3 zöld;
- architecture, secrets (3171 fájl / 0 lelet), l10n (1532/1532): zöld;
- fix-height, ellipsis, normál szóköz és hiányzó extension mutációk: mind piros;
- exact semantics-label próbateszt: piros, F1-et reprodukálta.

## Merge-döntés

Az F1 MAJOR nyitva van, ezért merge tilos. Terra javító kör és független
re-review szükséges; exact-SHA CI csak jóváhagyott csúcson lehet merge-evidencia.
