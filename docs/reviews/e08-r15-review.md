# E08-R15 — Review

Brief: `docs/rounds/e08-r15-achievement-ui-and-evidence.md`  
Diff: `a1547d45...33def4f0`  
Reviewer: Codex / `gpt-5.6-sol` · Dátum: 2026-08-21  
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 0 · MAJOR: 4 · MINOR: 0 · NOTE: 0

A hidden privacy-őr valódi `Opacity(0)` szivárgásra piros és restore után
zöld, a tracked scope tiszta. A commitált végállapot kötelező gate-je azonban
analyze-nál piros, a lista nem ad detail-navigációs actiont, az audit-only
`accessibilityNeutral` értéket tévesen UI-kategóriaként mutatja, és a publikus
evidence contract nem validálja a megjelenített számokat.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | all / unlocked / in-progress / category helyes halmaz | ❌ | alapmátrix zöld, de reviewer-cella szerint audit-only kategóriachip látható; F3 |
| A2 | locked hidden részlet a semantics fában sincs | ✅ | screen + detail negatív cella; `Opacity(0)` mutáció piros, restore zöld |
| A3 | progress és completion dátum | ✅ | A3 widget-cella, locale-formázott dátum |
| A4 | zárt, privacy-safe evidence | ❌ | payload/source scan zöld, de NaN/infinity/negatív/0 target átjut; F4 |
| A5 | lokalizált empty state | ✅ | A5 widget-cella |
| A6 | exact unknown ID safe state | ✅ | A6 widget-cella |
| A7 | minden copy ARB | ✅ | feature-szegmens + generált aggregate parity |
| A8 | nagy text scale + teljes semantics | ✅ | 1.99/2.0/2.01/3.0 listamátrix; hidden és visible semantics cellák |

## Scope-audit

```text
Legacy scope audit OK (a1547d45bca4..33def4f0e477, 10 changed path(s), 0 generated/ignored)
```

Az implementer diffje kizárólag a brief tételes allowlistjén belül van.

## Megállapítások

### F1 — MAJOR — A commitált round-gate analyze lépése piros

- **Fájl:** `achievement_detail_screen.dart:57`, `achievement_tile.dart:44,118`
- **Probléma:** két szükségtelen non-null assertion és egy publikus
  függvényből visszaadott private `_AchievementContent` analyzer-lelet maradt.
- **Hatás:** a kötelező gate nem zöld; az implementer handoffja ezért nem a
  commitált végállapot tényleges eredményét írja le.
- **Bizonyíték:** izolált klón, `tools/round-gate.sh ...`: format zöld,
  analyze 3 lelet, exit 10.
- **Kötelező javítás:** távolítsd el a két `!`-t; a lokalizált content típusa
  és lookup API-ja legyen analyzer-tiszta, dokumentált publikus contract vagy
  ne legyen publikus API. Adj analyzer-zöld végső round-gate bizonyítékot.
- **Státusz:** OPEN.

### F2 — MAJOR — A listából nem érhető el a detail nézet

- **Fájl:** `achievements_screen.dart:9-18,84-88`, `achievement_tile.dart:6-84`
- **Probléma:** sem a screen, sem a tile nem fogad detail-callbacket; a tile
  nem tappable és nincs semantics tap action. A route-regisztráció valóban
  későbbi kör, de a caller így sem tudja a validált detail képernyőt megnyitni.
- **Hatás:** a kör célja szerinti „jól navigálható lista és részletes
  magyarázat” két külön, összeköthetetlen widget marad.
- **Bizonyíték:** eldobható reviewer-cella `AchievementTile` leszármazott
  `InkWell`-t keresett: várt legalább 1, tényleges 0.
- **Kötelező javítás:** caller-fed `ValueChanged<String>` detail callback;
  visible/revealed tile exact achievement ID-val egyetlen tap actiont adjon,
  teljes button semantics mellett. Locked hidden placeholder ne adjon valódi
  ID-t vagy detail actiont. Tartós callback-cella kötelező.
- **Státusz:** OPEN.

### F3 — MAJOR — Az audit-only accessibilityNeutral UI-kategóriaként látszik

- **Fájl:** `achievements_screen.dart:64-78`, `achievement_tile.dart:101-116`
- **Probléma:** `AchievementCategory.values` minden enumértéket chipként
  renderel, köztük az `accessibilityNeutral` értéket. Chapter 9 §8.8 ezt
  név szerint catalog-audit jelzésnek, nem UI-kategóriának definiálja.
- **Hatás:** a felhasználó félrevezető „Minden tanulónak” kategóriát lát;
  a vision achievement besorolása termékjelentést kap egy audit markerből.
- **Bizonyíték:** eldobható reviewer-cella a
  `achievement-filter-category-accessibilityNeutral` kulcsot tiltotta; várt
  0, tényleges 1 chip.
- **Kötelező javítás:** a UI filterlista explicit, az audit-only értéket
  kizárja. Adj pozitív category-cellát valós UI-kategóriára és negatív cellát
  az audit markerre; a hidden exclusion maradjon.
- **Státusz:** OPEN.

### F4 — MAJOR — A publikus evidence contract nem őrzi a numerikus igazságot

- **Fájl:** `achievement_detail_screen.dart:13-23,164-172`
- **Probléma:** a `const AchievementEvidence` bármilyen `num` értéket elfogad,
  így NaN, infinity, negatív current és nulla target is lokalizált tényként
  jelenhet meg.
- **Hatás:** a privacy-safe contract hamis vagy értelmezhetetlen
  „Measured progress” állítást tehet; ez sérti az evidence-before-claims
  határt és az ADR 0378 aggregált, kész érték szerződését.
- **Bizonyíték:** eldobható reviewer-mátrix a négy invalid párra
  `ArgumentError`-t várt; az első `(NaN, 5)` objektumot adott vissza.
- **Kötelező javítás:** runtime konstruktor-őr: current véges és nem negatív,
  target véges és pozitív. Tartós NaN/infinity/negatív/0 target cellák; az
  unknown privacy-safe fallback maradjon.
- **Státusz:** OPEN.

## Gate-bizonyíték

| Gate | Eredmény |
|---|---|
| scope-audit | OK, 10/10 implementer path |
| format | zöld, 1739 fájl, 0 változás |
| analyze | **PIROS**, 3 lelet |
| célzott suite | implementer szerint 13/13; reviewer A2 restore cella 1/1 zöld |
| A2 mutáció | `Opacity(0)` hidden title → piros; restore → zöld |
| reviewer category/navigation | 2/2 eldobható cella piros |
| reviewer numeric evidence | invalid mátrix első NaN cellája piros |
| CI | nem dispatch-elve, review blokkol |

## Merge-döntés

Négy nyitott MAJOR és piros kötelező gate mellett merge tilos. Terra javító
kör szükséges, majd friss izolált re-review és exact-SHA CI.
