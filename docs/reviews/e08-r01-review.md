# E08-R01 — Review

Brief: `docs/rounds/e08-r01-gamification-baseline-and-principles.md`  
Diff: `origin/main...minimax/e08-r01-gamification-baseline-and-principles`  
Reviewer: Codex / gpt-5.6-terra (független orchestrátor)  
Dátum: 2026-08-19  
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 0 · MAJOR: 2 · MINOR: 0 · NOTE: 1

Az izolált, GitHub-originről klónozott review-fa (`d72bf193`) gate-je 9/9
zöld, a scope-audit tiszta. Ez nem bizonyítja a baseline központi
tartalmi állításait: a file:line ellenőrzés két megtévesztő térképet és
indokolatlan ADR-tesztlefedettséget talált.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Minden baseline-állítás visszakereshető | ❌ | F1: §1.1 és §1.2 több, kóddal cáfolható állítása |
| A2 | Aktuális és legacy kulcslista teljes | ✅ | reviewer key-scan; a valódi-sértés próba `practice_streak_v1` törlésekor `BASELINE_MISSING` |
| A3 | Freeze-szabály számszerű | ✅ | baseline §3 ↔ `streak_logic.dart:11–20,32–62` |
| A4 | Daily challenge determinisztikus | ✅ | baseline §4 ↔ `daily_challenge.dart:45–57` |
| A5 | Race/a11y/screen-size guardok leltára | ❌ | F2: a §8.4 ADR-lefedettségi minősítései nem a tesztek által bizonyítottak |
| A6 | Alkalmazáskód változatlan | ✅ | csak docs-pathok a diffben |
| A7 | Tiltólista ADR-hivatkozású | ✅ | baseline §9 D1–D16 mind 0289/0290 hivatkozású |
| A8 | Meglévő tesztek zöldek | ✅ | izolált `tools/round-gate.sh` 9/9 zöld |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e08-r01 --brief
docs/rounds/e08-r01-gamification-baseline-and-principles.md --base
b5317fd52b41aeb10839f9a90c971155f3b35632` → `Legacy scope audit OK`;
2 engedélyezett changed path, 0 generated/ignored.

## Megállapítások

### F1 — MAJOR — A feature- és importtérkép több alapállítása hamis

- **Fájl:** `docs/baseline/epic-08-start.md:30,35–37,49–50`
- **Probléma:** A baseline szerint a Share-nek nincs termelő forrása, és a
  Learnnek nincs közvetlen Streak- vagy Progress-éle. A review mérése ezt
  cáfolja: `lib/features/share/` kilenc Dart forrást tartalmaz, köztük a
  `public.dart:4–13` exportokat és `share_service.dart:15–35` szolgáltatást;
  a `learn/model/lesson.dart:7`, illetve a `learn/screens/learn_screen.dart:12,18`
  közvetlenül a Streak/Progress public contractot importálja.
- **Hatás:** A baseline az Epic 8 következő köreinek függőségi kiindulópontja.
  A hamis „nincs él” állítások hibás ownership- és migrációs döntést okoznak.
- **Kötelező javítás:** Javítsd a §1.1–§1.2 térképet kizárólag a tényleges,
  file:line mérésekre. A Share production fáit és a Learn tényleges public
  importjait sorold fel; ne vezess be új normatív architektúrát.
- **Ellenőrzés:** `find lib/features/share -type f -name '*.dart'` és
  `rg -n "../../(streak|progress)/public.dart" lib/features/learn` eredménye
  egyezzen a baseline hivatkozásaival.
- **Státusz:** OPEN

### F2 — MAJOR — Az ADR-lefedettségi táblázat tesztekkel nem bizonyított állításokat zöldít

- **Fájl:** `docs/baseline/epic-08-start.md:346–355`
- **Probléma:** A táblázat például a `streak_logic_test`/`practice_stats_test`
  alapján lefedettnek jelöli a 0289 §1 „mastery nem XP”, illetve a
  `streak_provider_test` alapján a 0290 §2 „UI nem számol jutalmat” döntést.
  Ezek a tesztek nem vizsgálják sem a mastery claim forrását, sem a jutalom UI
  számításának hiányát; a `weekly_bars_a11y_test` szemantikai címkéje sem
  bizonyítja a 0289 §2 auditálható session-evidence követelményt.
- **Hatás:** A baseline későbbi köröknek hamis lefedettségi képet ad, ezért
  hiányzó termékhatár-őrök maradhatnak észrevétlenek.
- **Kötelező javítás:** A táblázat csak a teszt által közvetlenül mért
  viselkedést jelölje lefedettnek; a többi sor legyen GAP vagy „kapcsolódó,
  de nem elegendő”, rövid pontosítással. Ne írj tesztet ebben a docs-only körben.
- **Ellenőrzés:** A táblázat minden „lefedett” sorához a megnevezett teszt
  konkrét assertionje és a releváns ADR-követelmény között legyen közvetlen
  kapcsolat.
- **Státusz:** OPEN

### N1 — NOTE — A wrapper gate-shape jelzése hamis pozitív

- **Fájl:** `.codex-round-status` (gitignore-olt wrapper artefaktum)
- **Probléma:** `gate_shape=VIOLATION`, mert a logban a gate-parancs
  leírása „no pipe/tail/&&” szöveget tartalmazott; a tényleges gate nem volt
  láncolva vagy csonkítva.
- **Hatás:** Nincs diff- vagy termékkockázat; az izolált reviewer gate
  csonkítás nélkül zölden futott.
- **Státusz:** NOTE

## Valódi-sértés próba

A reviewer klónban ideiglenesen töröltem a baseline `practice_streak_v1`
sorát. A kulcs-összevető parancs `BASELINE_MISSING:practice_streak_v1`
kimenettel piros állapotot adott; a sort ezután változatlanul visszaállítottam.

## Gate-bizonyíték

| Gate | Reviewer eredmény |
|---|---|
| `tools/round-gate.sh` | ✅ 9/9 (format, analyze, 4 teszt-útvonal, architecture, secrets, l10n) |
| Scope-audit | ✅ 2 engedélyezett changed path |
| CI | még nem dispatch-elt; javítás után új exact-SHA run kell |

## Merge-döntés

Az F1 és F2 MAJOR leletek miatt merge tilos. A javító kör után friss izolált
review, célzott gate és exact-SHA CI szükséges.
