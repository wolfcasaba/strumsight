# E13-R03 — Szemantikai színek és három téma

- **Státusz:** PREPARED (előre megírva 2026-08-15, kód olvasva: `main @ 903e7a7d`)
- **Típus:** Chapter 13 (UI/UX Design System), Kör 3
- **Kör-azonosító:** `E13-R03`
- **Branch:** `<motor>/e13-r03-semantic-colors-and-themes`
- **Előfeltétel:** `E13-R02` merge-elve (design-system alap)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — a token-forrás szabályát az **ADR 0273** rögzíti.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra az R02 tényleges
> `ss_theme_extensions.dart` vázát és a `migration-status.md` kanonikus-forrás
> szakaszát. A színek FORRÁSA az ADR 0273 §2 szerint a meglévő
> `AppColors`/`AppPalette` — **olvasni, nem másolni**. Eltérésnél §0.0 revízió.

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

## 11. Review — a Claude tölti ki
