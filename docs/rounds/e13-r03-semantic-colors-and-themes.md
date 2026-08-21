# E13-R03 — Szemantikai színek és három téma

- **Státusz:** PRE-FLIGHTED (2026-08-21, kód újramérve: `main @ 0948fc26`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 3
- **Kör-azonosító:** `E13-R03`
- **Branch:** `terra/e13-r03-semantic-colors-and-themes`
- **Előfeltétel:** `E13-R02` merge-elve (design-system alap)
- **Brief szerzője:** Claude (Opus 5)
- **Pre-flight ADR:** [`0381`](../adr/0381-semantic-theme-and-accessibility-contract.md)
  — az ADR 0273 változatlan token-forrás szabályára épül.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R02 tényleges
> `ss_theme_extensions.dart` vázát és a `migration-status.md` kanonikus-forrás
> szakaszát. A színek FORRÁSA az ADR 0273 §2 szerint a meglévő
> `AppColors`/`AppPalette` — **olvasni, nem másolni**. Eltérésnél §0.0 revízió.

## 0.0 Pre-flight revízió — 2026-08-21

Az indításkori mérés az előre megírt briefet az E13-R02 tényleges, merge-elt
állapotához igazítja; az implementer engedélyezett fájllistája nem tágul.

1. Az E13-R02 már a `main @ 0948fc26` része. Az
   `SsThemeExtensions.forBrightness` ma hét mezős `SsThemeColors` adaptert
   épít közvetlenül az `AppColors`, `AppPalette` és `AppTheme` API-kból. A
   Chapter 13 §9.2 által kért `SsColorScheme` és annak 23 mezője még nem
   létezik; a három E13-R03 theme-fájl, a két célzott teszt és a kontraszt-tool
   szintén hiányzik.
2. A kanonikus forrás szakasza a `docs/ui/migration-status.md` szerint már az
   új semantic theme extension, de a compatibility rule továbbra is a legacy
   paletta **olvasása**. Az ADR 0273 merge-elt és változatlan. Az atomi foglaló
   (`tools/round-slots.py reserve-adr --round E13-R03`) ezért az új, e körben
   szükséges theme/accessibility döntéshez a `0381` számot adta; az ADR 0381
   nem másolja és nem módosítja a 0273 token-forrás szabályát.
3. A meglévő publikus színforrás minden szükséges alapot ad új hex nélkül:
   brand/status/confidence az `AppColors` API-ból, surface/text/border az
   `AppPalette.dark` és `.light` értékeiből. A pre-flight WCAG-számítása
   (`python3 -c`, sRGB relatív luminancia) szerint dark primary text/canvas
   `15.1056:1`, dark secondary text/canvas `5.7718:1`, light primary
   text/canvas `15.2555:1`, light secondary text/canvas `5.1444:1`; a light
   border/canvas `1.3223:1`, ezért A2-ben nem tekinthető fontos non-text
   határnak. High Contrast erős borderként a meglévő ink használható.
4. A production `ThemeMode` csak system/light/dark, és a `lib/app/**` tilos
   zóna. Az E13-R03 ezért három önálló `ThemeData` konfigurációt és a
   development-only Component Catalog belső kapcsolóját készíti el; a
   production app theme-mode wiring változatlan. A theme-váltó nem vezet be
   hardkódolt felhasználói szöveget.
5. A confidence/offline/AI „nem csak szín” szerződését a design system
   színtől független ikon/shape marker-contracttal és annak catalog
   megjelenítésével méri. Lokalizált product-copy és feature-wiring nincs e
   körben.

Kötelező visszakeresett előzmény, szűkített → kockázati → teljes korpusz
sorrendben: az `adr/0273` közvetlenül megerősítette az egyetlen token-forrást;
a `lessons/L101` a numerikus küszöb explicit határcelláját; a
`lessons/L371` az exact deliverable/scope egyezését; a teljes korpusz pedig az
E13-R02 aktuális adapterét és handoffját hozta. A High Contrast viselkedési
contractjára nem volt az ADR 0381-nél korábbi, közvetlen döntés.

**Kockázat = high, indoklás:** a diff nem kezel secretet vagy jogosultságot,
de a `confidenceLow`, offline és local/cloud AI szemantika a termék
bizonyossági és accessibility határát érinti; hibás mapping biztos állításként
vagy kizárólag színnel közölhetne bizonytalan/provenance állapotot.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/core/design_system/foundations/ss_colors.dart",
  "lib/core/design_system/themes/ss_dark_theme.dart",
  "lib/core/design_system/themes/ss_light_theme.dart",
  "lib/core/design_system/themes/ss_high_contrast_theme.dart",
  "lib/core/design_system/themes/ss_theme_extensions.dart",
  "lib/core/design_system/documentation/component_catalog_screen.dart",
  "lib/core/design_system/public.dart",
  "tool/ui_contrast_check.dart",
  "test/core/design_system/themes/ss_color_scheme_test.dart",
  "test/core/design_system/themes/contrast_test.dart",
  "docs/rounds/e13-r03-semantic-colors-and-themes.md",
]
gate_tests = [
  "test/core/design_system/themes/ss_color_scheme_test.dart",
  "test/core/design_system/themes/contrast_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. Listán kívüli fájl → `stopped`.

## 1. Cél

A meglévő paletta **szemantikai** theme extensionné alakítása három témában:
Dark Studio, Warm Light, High Contrast (SDD Ch13 Kör 3).

## 2. Jelenlegi állapot — mért tények

- Az R02 létrehozta a `design_system/` vázat és a kompatibilitási adaptert.
- A Ch13 §2 kanonikus hexei adottak (copper `#D98A46`, dark/light felületek,
  confidence high/medium/low, danger) — **nem cserélendők le**.
- A Ch13 §9.2 megadja az `SsColorScheme` teljes mezőlistáját.

## 3. Scope

**Benne van:** `SsColorScheme` `ThemeExtension` a dokumentált mezőkkel · a
meglévő hexek **leképezése** szemantikai tokenekre · a három téma
konfigurációja · disabled/focus/hover/pressed/selected state overlay-ek ·
**kontraszt-ellenőrző** a kötelező text/surface párokra · a Component Catalog
téma-váltója.

**NINCS benne (tilos):** tipográfia (Kör 4) · geometria/felület (Kör 5) ·
`lib/features/**` · a `lib/core/theme/` átírása · **új hex dokumentált
kontraszt-indoklás nélkül** · `docs/adr/**`, `tools/**`, `.github/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `foundations/ss_colors.dart` | **ÚJ** — a szemantikai tokenek |
| `themes/ss_{dark,light,high_contrast}_theme.dart` | **ÚJ** — a három téma |
| `themes/ss_theme_extensions.dart` | a `ThemeExtension` bekötése |
| `documentation/component_catalog_screen.dart` | téma-váltó |
| `public.dart` | az export bővítése |
| `tool/ui_contrast_check.dart` | **ÚJ** — kontraszt-ellenőrző |
| `test/…/themes/*_test.dart` (2) | a §6 cellái |
| `docs/rounds/e13-r03-…md` | a §10 handoff |

**Tilos zóna:** `lib/core/theme/**` · `lib/features/**` · `lib/app/**` ·
`docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`.

## 5. Kötött architekturális döntések

### 5.1 A színforrás továbbra is OLVASOTT (ADR 0273 §2)

A szemantikai token a meglévő paletta értékét **hivatkozza**. Új hex csak
dokumentált kontraszt-indoklással kerülhet be.

**NEM elfogadható gyengítés:** „az új témához kényelmesebb volt beírni a
hexet". Két igazságforrás keletkezne.

### 5.2 A `danger` CSAK valódi hibára és destruktív műveletre

A Ch13 §9.2 kimondja: **alacsony confidence nem danger**, és **offline nem
danger**. A `syncPending` nem warning, ha normális offline sor.

**NEM elfogadható gyengítés:** a piros mint „figyelemfelkeltő" szín gyenge
eredményre. Az a felhasználót hibáztatja a rendszer bizonytalanságáért.

### 5.3 Az állapot NEM csak színnel jelzett

Confidence, offline, local/cloud AI — mindegyik ikon vagy szöveg
kíséretében. Szín-vakság mellett is olvasható.

### 5.4 A kontraszt MÉRT, nem szemre becsült

A kötelező text/surface párokra futtatható ellenőrző készül: normál szöveg
**≥ 4,5:1**, fontos nem-szöveges határ **≥ 3:1**.

### 5.5 A High Contrast téma NEM csak sötétebb/világosabb

Erősebb border, minimális áttetszőség, nagyobb fókuszgyűrű, kikapcsolt
dekoratív blur/glow — a Ch13 §9.3 szerint.

### 5.6 Az ADR 0381 rögzíti a végrehajtható theme-contractot

A teljes, 23 mezős `SsColorScheme`, a névvel ellátott state overlayek, a
High Contrast gépileg vizsgálható karakterisztikái és a színtől független
status marker együtt készülnek el. A production `ThemeMode` és a legacy
`AppTheme` wiring ebben a körben nem változik.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Normál szöveg kontrasztja **≥ 4,5:1** mindhárom témában | `contrast_test.dart` |
| A2 | Fontos nem-szöveges határ **≥ 3:1** | ugyanott |
| A3 | Alacsony confidence NEM `danger` színt kap | `ss_color_scheme_test.dart` |
| A4 | Offline NEM `danger`, sync pending NEM warning | ugyanott |
| A5 | Confidence/offline/AI-mód nem csak színnel jelzett | ugyanott |
| A6 | A színforrás olvasott: a paletta módosítása átüt a tokenre | ugyanott |
| A7 | Nincs hardkódolt szín az új komponensekben | `grep` a diffben |
| A8 | A három téma mindegyike előáll és egyenlőség-stabil | `ss_color_scheme_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| Hex beírva a tokenbe hivatkozás helyett | **A6** |
| Alacsony confidence pirosra színezve | **A3** |
| Offline piros | A4 |
| Az állapot csak színnel | **A5** |
| Kontraszt szemre állítva | A1/A2 |
| High Contrast csak sötétebb változat | A2 |

**A kontraszt három kötelező cellája** (a küszöb: 4,5:1 normál szövegre):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb alatt | 4,4:1 pár | **elutasítva** — a kapu piros |
| rajta (a küszöbön) | pontosan 4,5:1 | **elfogadva** (a határ inkluzív) |
| a küszöb fölött | 7:1 pár | elfogadva |

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd az egyik
szövegszínt a küszöb alá → az **A1** cellának PIROSNAK kell lennie →
állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/core/design_system/themes/ss_color_scheme_test.dart test/core/design_system/themes/contrast_test.dart
```

Külön processzek, csonkítatlan kimenet. **Tilos** `| tail`, `| head`,
`&&`-lánc vagy bármilyen szűrés (L09); a `flutter analyze` és `flutter test`
kézi láncolása OOM-ot ad (L05). A kötelező gate-et **TILOS háttérbe küldeni**
(`run_in_background`) — az egy-fordulós harness a forduló végén megöli (L254).

## 8. Implementációs sorrend

1. `ss_colors.dart` — szemantikai tokenek, a palettából OLVASVA.
2. `tool/ui_contrast_check.dart` + `contrast_test.dart` — a mérce ELŐBB.
3. A három téma konfigurációja, state overlay-ekkel.
4. Az állapot-jelölés ikon/szöveg kísérettel.
5. Component Catalog téma-váltó.
6. A valódi-sértés próba, §10-be dokumentálva.
7. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A hex beírásának kényelme.** Az ADR 0273 legfontosabb tiltása; a két
  forrás az első színjavításnál elcsúszik (A6).
- **A piros mint figyelemfelkeltés.** Gyenge eredményre használva a rendszer
  a felhasználót hibáztatja a saját bizonytalanságáért (A3).
- **A szemre állított kontraszt.** Sötét témában különösen csalóka; csak
  mérve dönthető el (A1).

## 10. Implementation handoff — az implementer tölti ki

### Módosítások

- **Javító kör (F1/F2):** a kontraszt-tool WCAG sRGB linearizálása a pontos
  `^ 2.4` hatványt használja; a canonical `#948D82` vektor rögzített
  szabványos luminanciája ezt regressziós tesztben kényszeríti. A
  színtől független marker-contract tesztje a négy ikon páronkénti
  egyediségét, a catalog widget-tesztje pedig a ténylegesen renderelt ikonok
  egyediségét is kéri.
- `foundations/ss_colors.dart`: a teljes, 23 mezős `SsColorScheme`, névvel
  ellátott interaction overlayek, High Contrast viselkedési extension és a
  színtől független ikon-marker contract.
- `themes/ss_{dark,light,high_contrast}_theme.dart`: a három önálló
  `ThemeData`, a legacy palettát olvasó extensionökkel.
- `tool/ui_contrast_check.dart`: közös sRGB-kontraszt-számítás és CLI.
- `component_catalog_screen.dart`: development-only, ikon-alapú háromtéma
  kapcsoló és négy status marker.
- A két új célzott teszt méri a szemantikai invariánsokat, a High Contrast
  viselkedést, a marker-contractot, a catalogot és a kontrasztküszöböket.

### Futtatott ellenőrzések

- Javító TDD-bizonyíték: az új canonical-vektor teszttel a javítás ELŐTT
  `flutter test test/core/design_system/themes/contrast_test.dart
  test/core/design_system/themes/ss_color_scheme_test.dart` → a várt F1
  piros (`Expected: 0.2695735834450039`, `Actual: 0.1943756414277682`);
  a javítás után ugyanez → 12 teszt zöld.
- Javító kör kötelező gate:
  `tools/round-gate.sh test/core/design_system/themes/ss_color_scheme_test.dart
  test/core/design_system/themes/contrast_test.dart` → 7/7 zöld (format,
  analyze, color-scheme teszt 8/8, contrast teszt 4/4, architecture, secrets,
  l10n).
- `flutter test test/core/design_system/themes/ss_color_scheme_test.dart
  test/core/design_system/themes/contrast_test.dart` → 11 teszt zöld.
- A meglévő catalog/foundation regresszióval együtt:
  `flutter test test/core/design_system/foundations_test.dart
  test/core/design_system/component_catalog_test.dart
  test/core/design_system/themes/ss_color_scheme_test.dart
  test/core/design_system/themes/contrast_test.dart` → 21 teszt zöld.
- Valódi-sértés próba: a `contrast_test.dart` tesztben ideiglenesen
  `textPrimary: canvas` mutációra `isTrue` elvárást állítottam. A futás a várt
  `Expected: true / Actual: <false>` hibával piros lett; az elvárást
  `isFalse`-ra visszaállítottam.
- `tools/round-gate.sh test/core/design_system/themes/ss_color_scheme_test.dart
  test/core/design_system/themes/contrast_test.dart` → format, analyze, mindkét
  célzott teszt, architecture, secrets és l10n zöld.

### Eltérések és nem futtatott ellenőrzések

- Az első gate-kísérletben az analyzer az új CLI `print` hívását jelezte;
  `stdout.writeln`-re cserélve a végső gate zöld.
- Teljes Flutter suite, property gate és APK/CI nem helyben fut: ezek a
  következő orchestrátor-fázis merge-kapui.

## 11. Review — a Claude tölti ki
