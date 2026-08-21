# E13-R03 — Független review

Brief: `docs/rounds/e13-r03-semantic-colors-and-themes.md`
Diff: `8fc99a6c..bbe721af`
Reviewer: Codex Sol (`gpt-5.6-sol`) · Dátum: 2026-08-21
Verdikt: **APPROVED**

## Összegzés

Nyitott BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

A Terra javító commit (`bbe721af`) lezárta mindkét MAJOR leletet. A kontraszt-
tool a pontos sRGB `2.4` hatványt használja és canonical vektor őrzi; a négy
status marker egyediségét contract- és widget-szinten is teszt méri. A friss
izolált reviewer-klón gate-je 7/7 zöld, a két korábbi hibás implementáció
külön-külön célzottan pirosra vitte a megfelelő tesztet.

## Acceptance criteria

| # | Teljesült | Bizonyíték |
|---|---|---|
| A1 | ✅ | canonical `0xFF948D82` sRGB vektor + alatta/rajta/fölötte küszöbteszt; köbözés-mutáció piros |
| A2 | ✅ | ugyanaz a javított WCAG számítás méri a mindhárom theme `borderStrong` párját |
| A3 | ✅ | mindhárom theme-ben `confidenceLow != danger`; célzott teszt zöld |
| A4 | ✅ | `offline != danger`, `syncPending != warning`; célzott teszt zöld |
| A5 | ✅ | négy páronként külön ikon; all-same reviewer-mutáció két tesztcellát pirosra vitt |
| A6 | ✅ | forrásreferenciák `AppColors`/`AppPalette`; nincs új `Color(0x...)` a semantic theme-fájlokban |
| A7 | ✅ | a production diffben nincs hardkódolt hex; scope-audit 10 útvonalat engedett |
| A8 | ✅ | mindhárom `ThemeData` létrejön, értékegyenlőség és extensionök tesztelve |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e13-r03-YAwnlK/repo
--brief docs/rounds/e13-r03-semantic-colors-and-themes.md --base
8fc99a6c...` → `Legacy scope audit OK`, 12 módosított útvonal, 2
generated/ignored review-jelentés.

## Megállapítások

### F1 — MAJOR — A kontraszt-tool hibás sRGB linearizálást használ

- **Fájl:** `tool/ui_contrast_check.dart:36`
- **Probléma:** a WCAG képlet nagyobb csatornaértéknél
  `((c + 0.055) / 1.055) ^ 2.4` értéket kér, a kód ugyanazt a tényezőt
  háromszor szorozza össze, vagyis köböz.
- **Bizonyíték:** az eldobható reviewer-teszt a tool luminanciáját a Flutter
  `Color.computeLuminance()` eredményéhez mérte. `0xFF948D82` esetén elvárt
  `0.2695735834450039`, tényleges `0.1943756414277682`; a teszt piros. A tool
  dark secondary-text/canvas aránya `4.7494097:1`, a szabványos pre-flight
  mérés `5.7718:1`.
- **Hatás:** A1/A2 zöld kapuja nem a specifikált WCAG-kontrasztot méri, ezért
  küszöb közeli hibás vagy helyes párokat tévesen minősíthet.
- **Kötelező javítás:** használd a valódi `2.4` hatványt, és tegyél a
  `contrast_test.dart`-ba canonical sRGB színvektorokat, amelyek a
  `Color.computeLuminance()` vagy kipinnelt standard eredmény ellen őrzik a
  linearizálást; az ideális luminancia-küszöb cellahármas maradjon meg.
- **Státusz:** FIXED (`bbe721af`) — `math.pow(..., 2.4)` és a canonical
  luminancia-vektor őrzi. A reviewer visszarontotta a hatványt 3-ra: a
  célzott contrast suite a várt `0.2695735834450039` / tényleges
  `0.1943756414277682` eltéréssel piros lett.

### F2 — MAJOR — Az A5 teszt nem bizonyítja a markerek megkülönböztethetőségét

- **Fájl:** `test/core/design_system/themes/ss_color_scheme_test.dart:35`
- **Probléma:** a teszt csak azt várja, hogy minden marker ikonja nem null; a
  catalog teszt pedig csak négy `SsStatusMarker` példányt számol. Egyetlen,
  minden állapothoz azonos ikon mindkettőn átmegy.
- **Bizonyíték:** reviewer-mutációban az offline/local-AI/cloud-AI ikonokat
  mind `Icons.help_outline`-ra állítottam, így mind a négy állapot ugyanazt a
  shape-et kapta. A teljes `ss_color_scheme_test.dart` mégis 8/8 zöld lett.
- **Hatás:** ilyen regressziónál confidence, offline és AI provenance újra
  kizárólag a színből különbözne, az A5 nem tárgyalható accessibility határa
  teszt nélkül maradna.
- **Kötelező javítás:** a teszt kérje a négy marker ikon/shape értékének
  páronkénti egyediségét, és tartson meg legalább egy widget-szintű bizonyítékot
  arra, hogy a catalog a contractból kapott külön markereket rendereli.
- **Státusz:** FIXED (`bbe721af`) — a contract teszt a négy ikon halmazának
  elemszámát, a widgetteszt a ténylegesen renderelt ikonokat méri. All-same
  mutációnál mindkét cella piros lett (`expected 4`, `actual 1`).

### N1 — NOTE — A wrapper gate-shape regexe adminisztratív láncra jelzett

A javító wrapper `gate_shape=VIOLATION` értéket írt, mert az implementer a
terminális jelzést és a read-only `git status`/`git show` parancsokat `&&`
lánccal futtatta. A logban a kötelező `tools/round-gate.sh ...` önálló,
csonkítatlan invokáció. A reviewer ettől függetlenül friss klónban újrafuttatta
a teljes artefaktumot; a verdict nem támaszkodik a wrapper gate-állítására.

## Gate-bizonyíték

Izolált re-review klón `/tmp/review-e13-r03-fix1-WcxbLP/repo`, commit
`bbe721af`:

- format: zöld, 1755 fájl / 0 változás;
- analyze: zöld, 0 issue;
- semantic color scheme: 8/8 zöld;
- contrast: 4/4 zöld;
- architecture, secrets (3149 fájl / 0 lelet), l10n (1503/1503): zöld;
- összegzés: **7/7 gate zöld**;
- F1 re-mutation (`2.4 -> 3`): contrast suite piros;
- F2 re-mutation (négy marker → azonos ikon): color-scheme suite két cellája
  piros; mindkét mutáció restore után tiszta worktree.

## Merge-döntés

A correctness review **APPROVED**. Merge csak az exact-SHA Full Gate/Router CI
és a friss-main landolási feltételek zöld eredménye után engedett.
