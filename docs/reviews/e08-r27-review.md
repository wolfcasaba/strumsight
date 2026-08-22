# E08-R27 — Review

Brief: docs/rounds/e08-r27-gamification-accessibility-and-settings.md
Diff: `git diff 355b508d..7c511c90` (pre-flight commit → javító kör HEAD, branch `minimax/e08-r27-gamification-accessibility-and-settings`)
Reviewer: Claude Sonnet 5 · Dátum: 2026-08-22
Verdikt: **APPROVED** (javító kör után, ld. „Javító kör" szakasz)

## Összegzés

BLOCKER: 0 · MAJOR: 1 (FIXED) · MINOR: 1 (OPEN, follow-up) · NOTE: 2

## Gate-bizonyíték (saját kézzel, izolált klón)

`git clone --branch minimax/e08-r27-gamification-accessibility-and-settings` →
`/tmp/review-e08-r27` (HEAD `70ab7f3a`), `tools/prepare-flutter-generated.sh`,
majd:

```
tools/round-gate.sh test/features/gamification/presentation/gamification_accessibility_test.dart test/features/settings
```

```
format        zöld
analyze       zöld
test .../gamification_accessibility_test.dart   zöld (12/12)
test test/features/settings                      zöld (51/51)
architecture  zöld (12 allowlisted deviation — pre-existing, none new)
secrets       zöld
l10n          zöld (aggregate freshness OK, en→hu parity 1663 messages)
```

Scope-audit (`tools/scope-audit.py --repo /tmp/review-e08-r27 --brief
docs/rounds/e08-r27-gamification-accessibility-and-settings.md --base
355b508df9d21715cde7a1fb35e605d1c2500d5c`): **OK, 10 changed path(s), 0
generated/ignored** — minden változás az `allowed_paths`-on belül.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Teljes kikapcsolás mellett is fut a főkönyv-/széria-/mastery-számítás | ✅ (design), ⚠ próba gyenge — ld. F2 | `gamification_accessibility_test.dart:19-63` |
| A2 | Visszakapcsolás után nincs lyuk | ✅ (design), ⚠ próba gyenge — ld. F2 | uo. `:65-133` |
| A3 | Engedély megadása nem ad XP-t/unlockot | ✅ | uo. `:135-187` — valódi `writeLog` negatív asszerció 5 tiltott kulcsra |
| A4 | Mind az öt beállítás hat a leképezésre | ✅ | uo. `:189-276` — mind az öt tengely önállóan mérve |
| A5 | Azonnali érvényesülés | ✅ | uo. `:278-307` — szinkron `state` írás a `persist()` előtt (`gamification_preferences_provider.dart:53-54`) |
| A6 | Minden achievementnek kitöltött a11y-leírása | ✅ | uo. `:309-413` — 22/22 + mindkét ARB + valódi-sértés próba (in-process, reverzibilis) |
| A7 | 200% szövegskála + WCAG AA kontraszt | ✅ | uo. `:415-514` — a MEGLÉVŐ, L381-fixált `tool/ui_contrast_check.dart`-ot használja (nem újraírt, potenciálisan hibás számítást) |
| A8 | `test/features/settings` suite változatlan zöld | ✅ | gate `[4]` lépés, 51/51 |

## Megállapítások

### F1 — MAJOR — a domain réteg a presentation rétegtől függ (AGENTS.md §6 sértés)

- **Fájl:** `lib/features/gamification/domain/gamification_preferences.dart:1`
- **Probléma:** `import '../presentation/widgets/reward_summary_sheet.dart' show RewardSummaryFeedback;`
  — egy `domain/` alatti fájl importál egy `presentation/widgets/` fájlt. Az
  importált fájl (`reward_summary_sheet.dart:1`) maga `import
  'package:flutter/material.dart';`-tal kezdődik, tehát a `show` klauzula
  ellenére a `GamificationPreferences` domain-osztály **tranzitívan függ a
  Flutter keretrendszertől**. Az `AGENTS.md` §6 explicit, projekt-szintű
  szabálya: „Domain nem függ Fluttertől, Riverpodtól, Dio-tól vagy storage
  plugintól." A gépi `tool/check_architecture.dart` ezt NEM fogta meg, mert a
  `sharedDomainMustRemainFrameworkIndependent` szabály `_isSharedDomain()`
  predikátuma csak a `lib/core/music/`, `lib/core/audio/codec/` és
  `lib/features/practice/domain/` útvonalakat őrzi
  (`tool/check_architecture.dart:384-387`) — a `gamification/domain/` nincs a
  listán. Ez GATE-LEFEDETTSÉGI RÉS, nem felmentés: az `AGENTS.md` szabálya
  útvonaltól függetlenül érvényes.
- **Hatás:** a `GamificationPreferences` — amit a §5 szerint minden jövőbeli
  fogyasztónak (koordinátor, achievement a11y, egy jövőbeli backend-szinkron)
  Flutter-mentesen kellene tudnia importálnia — ma nem tesztelhető/importálható
  tiszta Dart kontextusban a widget-fa nélkül; egy jövőbeli, tényleg
  Flutter-mentes fogyasztó (pl. egy CLI export vagy egy pure-Dart unit teszt,
  ami csak a modellt akarja) felesleges Flutter-függést örököl.
- **Kötelező javítás:** vedd ki a `toRewardSummaryFeedback()` metódust és az
  importot a `gamification_preferences.dart`-ból. A leképezést told át a
  presentation rétegbe — a legkézenfekvőbb hely a MÁR engedélyezett
  `gamification_preferences_provider.dart` (ami `presentation/providers/`
  alatt van), pl. egy top-level függvényként vagy egy `extension
  GamificationPreferencesFeedback on GamificationPreferences` blokkban,
  ugyanazzal a logikával (`hapticsEnabled && isCelebrationVisible`, stb.). A
  `gamification_accessibility_test.dart` A4 csoportjának hívásait
  (`prefs.toRewardSummaryFeedback()`) erre a provider-szintű függvényre kell
  átírni. Mindhárom érintett fájl (`gamification_preferences.dart`,
  `gamification_preferences_provider.dart`, a teszt) már az
  `allowed_paths`-on van — a javítás NEM igényel lista-bővítést.
- **Ellenőrzés:** `grep -n "^import" lib/features/gamification/domain/gamification_preferences.dart`
  ne találjon `presentation/`-re vagy `package:flutter/`-re mutató sort; a
  gate (`tools/round-gate.sh …`) 12/12 maradjon zöld a módosított hívási
  helyekkel.
- **Státusz:** **FIXED** (`7c511c90`) — a `toRewardSummaryFeedback()` a
  domainból eltűnt, a leképezés `gamificationFeedbackFor(GamificationPreferences)`
  néven a `gamification_preferences_provider.dart`-ba (presentation réteg)
  került. Saját kézzel újra-klónozva (`/tmp/review-e08-r27-fix`, HEAD
  `7c511c90`) igazolva: `grep -n "^import" lib/features/gamification/domain/gamification_preferences.dart`
  **0 találat** (a domain fájl importmentes); a hívási helyek
  (`gamification_accessibility_test.dart:198,206,219,229,267`) a provider
  szintű függvényt hívják. A teljes gate ÚJRA lefuttatva, izolált klónban:
  format/analyze/12×12 teszt/51×51 teszt/architecture/secrets/l10n mind
  zöld. Scope-audit (`tools/scope-audit.py`, bázis `355b508d`) → OK, 11
  változott útvonal, 1 generated/ignored (a saját review-jelentés).

### F2 — MINOR — az A1/A2 „valódi-sértés próba" nem köti be ténylegesen a preferenciát a koordinátorba

- **Fájl:** `test/features/gamification/presentation/gamification_accessibility_test.dart:19-63` (A1), `:65-133` (A2)
- **Probléma:** az A1 teszt `_routeAllToInbox(coordinator, events)`-et
  KÉTSZER hívja MEGEGYEZŐ argumentumokkal (`silent1`/`loud1`), és arra alapoz
  egyenlőséget, hogy a hívás determinisztikus — de a `silent`/`loud`
  `GamificationPreferences` példányok SOHA nem kerülnek át a
  `_routeAllToInbox` hívásba (a segédfüggvény nem is fogad ilyen paramétert).
  A teszt ezért NEM azt bizonyítja, amit a §10 handoff állít („If a future
  refactor wires processing to visibility, this cell goes RED") — egy
  jövőbeli, a láthatóságot a feldolgozáshoz kötő hiba ezen a konkrét
  asserción nem menne át pirosba, mert a teszt magát a kötést sosem hozza
  létre. Az A2 teszt ugyanezt a mintát ismétli (`silent`/`loud` változók
  kiszámolva és `isCelebrationVisible`-jük ellenőrizve, de a rákövetkező
  `state2`/`third`/`fourth` esemény-útvonal egyáltalán nem hivatkozik rájuk).
  Ami ténylegesen bizonyított: (a) `isCelebrationVisible` helyesen számol
  `intensity`-ből (triviális, de valódi), és (b) a `CelebrationCoordinator`
  (E08-R22-ből változatlan) nem veszít eseményt — ami már az E08-R22 saját
  suite-jában is le van fedve.
- **Hatás:** alacsony — a jelenlegi kódban NINCS tényleges kapcsolat a
  preferencia és a koordinátor között (a bekötés explicit módon a jövőbeli
  E13-R32 dolga, ADR 0393 5. döntés), tehát ma nincs valós regresszió, amit ez
  a hiányos próba elmulasztana elkapni. A kockázat a §10 dokumentáció
  pontossága: a handoff túlállítja, mit bizonyít a teszt.
- **Javasolt irány (nem kötelező e körben, mert nem hizlalja indokolatlanul a
  diffet, de a §10 szöveg pontosítása olcsó):** vagy (a) pontosítsd a §10
  handoff szövegét úgy, hogy a tesztek jelenlegi, szűkebb állítását írják le
  (nincs éles csatolás ma, ezért a teszt a modellt és a koordinátort külön-
  külön, nem együtt méri), vagy (b) egészítsd ki a tesztet egy explicit,
  bekötött ellenpróbával: definiálj egy lokális `_wouldGateOnVisibility`
  segédfüggvényt, ami a `isCelebrationVisible`-t ténylegesen bemenetként
  használja a routolásnál, és mérd, hogy ez a hipotetikus bekötés
  ELTÉRŐ számot adna — ezzel a teszt tényleg megmutatja, MELYIK jövőbeli
  mintázat bukna el rajta.
- **Státusz:** OPEN (follow-up — nem blokkolja a mostani mergét, de rögzítendő
  a HANDOFF-ban a jövőbeli E13-R32 pre-flightjának)

### N1 — NOTE — tárolókulcsok nincsenek a központi `StorageKeys` katalógusban

A `gamification_preferences_provider.dart` öt kulcsa (`_kIntensity`, stb.)
tudatosan inline `const String`, dokumentált indokkal (a `StorageKeys` fájl
nincs az `allowed_paths`-on). Elfogadható, mert az `allowed_paths` valóban
kizárja, és a döntés a fájlban meg van magyarázva. Egy jövőbeli, a
`StorageKeys`-t is engedélyező kör felvehetné.

### N2 — NOTE — `reward_summary_sheet.dart` doc-kommentje stale marad

Az ADR 0393 5. döntése ezt tudatosan dokumentálja: a fájl doc-kommentje
(„the wiring lands in round 27") ma is tévesen a 27-es körre hivatkozik, mert
a tényleges hívó (és így a doc-komment javítása) az `E13-R32` gamification-UI
kör dolga. Nem e kör hatásköre (a fájl nincs az `allowed_paths`-on).

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs** (`tools/scope-audit.py` →
OK, 10/10 az `allowed_paths`-on belül; l10n-aggregátum és a szegmens-fájlok is
a revideált listán szerepelnek).

## Architektúra + termékhatárok

- Cross-feature import: a §10 szerint az implementer az ELSŐ futásban
  közvetlen `domain/`/`presentation/` importot használt a szekcióban/tesztben,
  amit az architektúra-gate elkapott; a `ac44b8f4` javító commit mindkettőt a
  `public.dart` barrelre váltotta — **ez működött, a gate elkapta, amit
  kellett.**
- Domain-függetlenség: **SÉRTVE**, ld. F1 — a gate-lefedettségi rés miatt nem
  a gépi mérce, hanem a manuális review fogta meg.
- UI↛plugin, secret-a-logban, mic/hálózat: nem érintett terület, nincs lelet.

## Javító kör (2026-08-22, ugyanaz a branch, commit `7c511c90`)

Egy MiniMax javító kör az F1 leletlistával indult; a fix a §0.0.1 brief-
revízió kötelező javítását pontosan követte. Saját kézhez újra lefuttatott
gate + scope-audit fent. F2/N1/N2 továbbra sem blokkol — a HANDOFF a merge
után rögzíti, F2 kifejezetten a következő UI-bekötő kör (E13-R32)
pre-flightjának szól.

**Végső döntés: APPROVED.** BLOCKER/MAJOR nyitva: 0. A kör mehet CI-dispatchra
és mergere.
