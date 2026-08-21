# E13-R02 — Független review

Brief: `docs/rounds/e13-r02-design-system-foundation.md`
Diff: `e33bff50..2f3b51d2`
Reviewer: Codex Sol (`gpt-5.6-sol`) · Dátum: 2026-08-21
Verdikt: **CHANGES REQUIRED**

## Összegzés

BLOCKER: 0 · MAJOR: 2 · MINOR: 1 · NOTE: 1

A Terra implementáció scope-ja tiszta és a független kör-gate 8/8 zöld, de
két explicit szerződés tartalmilag hiányos. A kompatibilitási réteg az előírt
három legacy API közül csak az `AppColors`/`AppPalette` párost olvassa, az
`AppTheme`-et nem. A Component Catalog route factory kapui jók, de a barrelből
publikusan elérhető screen közvetlen konstruktorral megkerüli őket.

## Acceptance criteria

| # | Teljesült | Bizonyíték |
|---|---|---|
| A1 | ✅ | `public.dart` + a valós `lib/` fát bejáró guard; belső-import parser próba zöld |
| A2 | ✅ | feature-import valódi-sértés: `ss_spacing.dart -> features/live/public.dart` két tesztet pirosra vitt |
| A3 | ⚠️ | legacy fájl érintetlen, de teljes suite csak CI-ben lesz bizonyítva |
| A4 | ✅ | másolt `Color(0xFFD98A46)` reviewer-mutáció pirosra vitte a foundation tesztet |
| A5 | ❌ | F2: a publikus screen közvetlenül renderel kikapcsolt kapuk mellett |
| A6 | ✅ | scope-audit: 13 changed, 0 generated/ignored, nincs theme/feature/app diff |
| A7 | ✅ | `migration-status.md` három fázisra megnevezi a kanonikus forrást |
| A8 | ✅ | a kipinnelt breakpoint/spacing/radius/motion/semantics cella zöld |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e13-r02 --brief
docs/rounds/e13-r02-design-system-foundation.md --base e33bff50...` →
`Legacy scope audit OK`, 13 módosított útvonal, 0 generated/ignored.

## Megállapítások

### F1 — MAJOR — Az adapter nem olvassa az előírt `AppTheme` API-t

- **Fájl:** `lib/core/design_system/themes/ss_theme_extensions.dart:3`
- **Probléma:** a brief §5.2 név szerint `AppColors`/`AppPalette`/`AppTheme`
  adaptert kér. A fájl csak az első kettőt importálja és használja.
- **Bizonyíték:** az eldobható reviewer-próba az `app_theme.dart` importot és
  `AppTheme.` használatot várta; mindkét cella piros lett.
- **Kötelező javítás:** adj dokumentált, tesztelt adapter API-t, amely
  brightness alapján közvetlenül `AppTheme.light()`/`AppTheme.dark()`
  eredményét adja; ne másolja a ThemeData konfigurációját.
- **Státusz:** OPEN.

### F2 — MAJOR — A publikus catalog screen megkerüli a két kaput

- **Fájl:** `lib/core/design_system/documentation/component_catalog_screen.dart:36`
- **Probléma:** `ComponentCatalogScreen` publikus és a `public.dart` exportálja.
  Bármely production fogyasztó saját route-ba teheti, függetlenül a
  default-OFF flagtől és `kDebugMode`-tól.
- **Bizonyíték:** a reviewer előbb igazolta, hogy a factory `null`-t ad
  `(false,false)` mellett, majd ugyanabban a tesztben a
  `MaterialApp(home: ComponentCatalogScreen())` egy példányt renderelt.
- **Kötelező javítás:** a screen legyen library-private; csak a kapuzott route
  factory legyen publikus. A dark/light smoke a sikeresen kapuzott route-on
  keresztül pumpáljon, ne közvetlen screen konstruktorral.
- **Státusz:** OPEN.

### F3 — MINOR — Az új publikus szerződések dokumentálatlanok

- **Fájl:** `lib/core/design_system/public.dart:1`
- **Probléma:** az exportált foundation/theme/catalog típusok és fontos
  factoryk nem kapnak API doc-commentet, bár az `AGENTS.md` §10 kötelezővé
  teszi a publikus contract dokumentálását.
- **Kötelező javítás:** rövid, tesztben igazolt doc-comment a publikus
  típusokra és belépőkre; ne állíts többet a teszteknél.
- **Státusz:** OPEN.

### N1 — NOTE — A wrapper `gate_shape=VIOLATION` jelzése álpozitív

A regex a napló egyetlen sorba ágyazott prompt/preambulum `&&` szövegére
illeszkedett. A tényleges gate-hívás csonkítatlan volt; ettől függetlenül a
review friss klónban újrafuttatta az egész artefaktumot.

## Gate-bizonyíték

`/tmp/review-e13-r02`, commit `2f3b51d2`:

- format: zöld, 1748 fájl / 0 változás;
- analyze: zöld, 0 issue;
- foundations: 3/3 zöld;
- component catalog: 7/7 zöld;
- architecture test: 28/28 zöld;
- architecture/secrets/l10n: zöld;
- összegzés: **8/8 gate zöld**.

## Merge-döntés

Merge tilos F1 és F2 lezárásáig. A javító commit után friss izolált klónban
teljes gate, leletenkénti re-review és high-risk security re-review kötelező.
