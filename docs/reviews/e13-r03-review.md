# E13-R03 — Független review

Brief: `docs/rounds/e13-r03-semantic-colors-and-themes.md`
Diff: `8fc99a6c..93742cc2`
Reviewer: Codex Sol (`gpt-5.6-sol`) · Dátum: 2026-08-21
Verdikt: **CHANGES REQUIRED**

## Összegzés

Nyitott BLOCKER: 0 · MAJOR: 2 · MINOR: 0 · NOTE: 0

A scope és a 7/7 lokális gate zöld, de a kontraszt-tool nem a WCAG sRGB
képletét implementálja, a színtől független status-marker teszt pedig egy
egyetlen, minden állapothoz azonos ikonra rontott implementációt is zölden
enged. Mindkettő közvetlenül a kör A1/A2, illetve A5 szerződését érinti.

## Acceptance criteria

| # | Teljesült | Bizonyíték |
|---|---|---|
| A1 | ❌ | F1: a tool köböz, nem `2.4` hatványt számol; a canonical-vector reviewer teszt piros |
| A2 | ❌ | ugyanaz a hibás linearizálás minősíti a non-text párt is |
| A3 | ✅ | mindhárom theme-ben `confidenceLow != danger`; célzott teszt zöld |
| A4 | ✅ | `offline != danger`, `syncPending != warning`; célzott teszt zöld |
| A5 | ❌ | F2: az összes marker azonos ikonra rontva a teljes célzott suite továbbra is 8/8 zöld |
| A6 | ✅ | forrásreferenciák `AppColors`/`AppPalette`; nincs új `Color(0x...)` a semantic theme-fájlokban |
| A7 | ✅ | a production diffben nincs hardkódolt hex; scope-audit 10 útvonalat engedett |
| A8 | ✅ | mindhárom `ThemeData` létrejön, értékegyenlőség és extensionök tesztelve |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e13-r03-YAwnlK/repo
--brief docs/rounds/e13-r03-semantic-colors-and-themes.md --base
8fc99a6c...` → `Legacy scope audit OK`, 10 módosított útvonal, 0
generated/ignored.

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
- **Státusz:** OPEN

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
- **Státusz:** OPEN

## Gate-bizonyíték

Izolált reviewer-klón `/tmp/review-e13-r03-YAwnlK/repo`, commit `93742cc2`:

- format: zöld, 1755 fájl / 0 változás;
- analyze: zöld, 0 issue;
- semantic color scheme: 8/8 zöld;
- contrast: 3/3 zöld;
- architecture, secrets (3147 fájl / 0 lelet), l10n (1503/1503): zöld;
- összegzés: **7/7 gate zöld**, de a két eldobható falszifikáció F1/F2 szerint
  leleplezte a hiányos mércét.

## Merge-döntés

Az ADR 0052 szerint a két nyitott MAJOR miatt merge tilos. Ugyanaz a Terra
implementer egy javító kört kap; utána friss izolált klónban teljes re-review
és gate szükséges.
