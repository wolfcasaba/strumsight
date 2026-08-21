# E13-R02 — Független review

Brief: `docs/rounds/e13-r02-design-system-foundation.md`
Diff: `e33bff50..2bf8d6f2`
Reviewer: Codex Sol (`gpt-5.6-sol`) · Dátum: 2026-08-21
Verdikt: **APPROVED**

## Összegzés

Nyitott BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

A Terra javító commit (`2bf8d6f2`) lezárta mindhárom leletet. A
kompatibilitási réteg közvetlenül delegál az `AppTheme.dark/light` API-ra, a
catalog screen library-private, a publikus API-k dokumentáltak. A friss
reviewer-klón kör-gate-je ismét 8/8 zöld.

## Acceptance criteria

| # | Teljesült | Bizonyíték |
|---|---|---|
| A1 | ✅ | `public.dart` + a valós `lib/` fát bejáró guard; belső-import parser próba zöld |
| A2 | ✅ | feature-import valódi-sértés: `ss_spacing.dart -> features/live/public.dart` két tesztet pirosra vitt |
| A3 | ✅ | legacy fájl érintetlen; a lokális teljes analyze zöld, a teljes suite CI-kapu marad |
| A4 | ✅ | másolt `Color(0xFFD98A46)` reviewer-mutáció pirosra vitte a foundation tesztet |
| A5 | ✅ | a screen private; debug-kapu mutációja piros, publikus konstruktor-próba nem fordul |
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
- **Státusz:** FIXED (`2bf8d6f2`) — `legacyThemeForBrightness` közvetlenül
  `AppTheme.dark()`/`AppTheme.light()` eredményét adja; a reviewer tesztje
  mindkét brightness értéket és a forrást is ellenőrizte.

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
- **Státusz:** FIXED (`2bf8d6f2`) — `_ComponentCatalogScreen` library-private.
  A reviewer barrel-próbája `ComponentCatalogScreen` használatára
  `Method not found` fordítási hibát adott; a debug-kapu ideiglenes kivétele
  pirosra vitte a `(true,false)` cellát.

### F3 — MINOR — Az új publikus szerződések dokumentálatlanok

- **Fájl:** `lib/core/design_system/public.dart:1`
- **Probléma:** az exportált foundation/theme/catalog típusok és fontos
  factoryk nem kapnak API doc-commentet, bár az `AGENTS.md` §10 kötelezővé
  teszi a publikus contract dokumentálását.
- **Kötelező javítás:** rövid, tesztben igazolt doc-comment a publikus
  típusokra és belépőkre; ne állíts többet a teszteknél.
- **Státusz:** FIXED (`2bf8d6f2`) — minden exportált foundation típus, a
  theme extension és a catalog factory teszttel igazolt doc-commentet kapott.

### N1 — NOTE — A wrapper `gate_shape=VIOLATION` jelzése álpozitív

A regex a napló egyetlen sorba ágyazott prompt/preambulum `&&` szövegére
illeszkedett. A tényleges gate-hívás csonkítatlan volt; ettől függetlenül a
review friss klónban újrafuttatta az egész artefaktumot.

## Gate-bizonyíték

`/tmp/review-e13-r02-fix1`, commit `2bf8d6f2`:

- format: zöld, 1748 fájl / 0 változás;
- analyze: zöld, 0 issue;
- foundations: 3/3 zöld;
- component catalog: 8/8 zöld;
- architecture test: 28/28 zöld;
- architecture/secrets/l10n: zöld;
- összegzés: **8/8 gate zöld**.

## Merge-döntés

A correctness review **APPROVED**. Merge csak az exact-SHA Full Gate/Router CI
és a friss-main landolási feltételek zöld eredménye után engedett.
