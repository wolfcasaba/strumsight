# E15-R01 — A design-rendszer témájának app-szintű bevezetése

- **Státusz:** PREPARED (előre megírva 2026-08-28, kód olvasva: `main @ 4cb32eb0`)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 1
- **Kör-azonosító:** `E15-R01`
- **Branch:** `<motor>/e15-r01-design-system-theme-adoption`
- **Előfeltétel:** nincs (a Chapter 13 lezárva, `E13-R36` merge-elve)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0466` — a szám FOGLALT (Chapter 15 batch-tartomány: `0466`–`0477`).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "design system theme extensions app theme adoption tokens typography"` → **[ADR 0383](../adr/0383-typography-and-text-scale-contract.md)** (tipográfia és text-scale szerződés) és **[ADR 0381](../adr/0381-semantic-theme-and-accessibility-contract.md)** (szemantikus téma- és akadálymentességi szerződés). A kör ezeket a MÁR ELFOGADOTT szerződéseket teszi az app tényleges futásidejű témájává.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/app/strumsight_app.dart` MÉRT téma-sorait (a megíráskor `theme: AppTheme.light()`, `darkTheme: AppTheme.dark()`, és a hibaág `theme: AppTheme.dark()`), valamint a `SsLightTheme.data()` / `SsDarkTheme.data()` szerkezetét (mindkettő a `legacyThemeForBrightness`-ből indul és extensionöket ad hozzá). Ha az E12 sáv időközben hozzányúlt a bootstraphez, a §4 listát igazítsd.

## 0.0 A kör MÉRT kiváltó oka

A Chapter 13 alatt megépült a design-rendszer (`lib/core/design_system/`: foundations, components, layouts, motion, accessibility, **három téma**), de az alkalmazás **soha nem kapcsolta be**: a `strumsight_app.dart` ma is a `AppTheme.light()/dark()`-ot adja a `MaterialApp`-nak, és a `SsColorScheme`/`SsTypography` extensionökre a fán mindössze **22** fájl hivatkozik — mindegyik egy feature-szintű `*ThemeScope` burkolón át (auth, settings, share, progress_v2, library_v2, gamification, community, offline_ai, today, metronome). Következmény: a migrált képernyők tokenjei feature-enként külön fabrikálódnak, a nem burkolt képernyők pedig egyáltalán nem látják őket.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/app/strumsight_app.dart",
  "lib/core/design_system/themes/ss_theme_extensions.dart",
  "test/app/theme_adoption_test.dart",
  "test/ui/goldens/e15_r01_theme_adoption_test.dart",
  "docs/ui/migration-status.md",
  "docs/rounds/e15-r01-design-system-theme-adoption.md",
]
gate_tests = [
  "test/app/theme_adoption_test.dart",
  "test/ui/goldens/e15_r01_theme_adoption_test.dart",
  "test/accessibility/semantics_contract_test.dart",
  "test/app/navigation/adaptive_scaffold_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a diff az alkalmazás EGÉSZ vizuális rétegének gyökerét cseréli (a `MaterialApp` témáját), tehát minden képernyő minden cellája érintett — egy elrontott extension-lista néma kontraszt- vagy olvashatósági regressziót okozna. A `security-reviewer` nem kötelező (nincs adat/hálózati határ), de a `flutter-reviewer` + `flutter-devil-advocate` igen.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a téma bevezetése egy feature-képernyő ÁTÍRÁSÁT igényelné, a kimenet a `stopped` jelzés — a képernyő-migráció a saját körének (E15-R05…R10) a dolga, nem ezé ([L478](../LESSONS.md#l478)).

## 1. Cél

Az alkalmazás futásidejű témája a design-rendszer témája legyen (extensionökkel együtt), hogy MINDEN képernyő — a már migráltak és a még migrálatlanok is — ugyanabból a token-forrásból dolgozzon, feature-szintű burkolók nélkül.

## 2. Jelenlegi állapot — mért tények

- `lib/app/strumsight_app.dart:33-34` → `theme: AppTheme.light()`, `darkTheme: AppTheme.dark()`; a bootstrap-hibaág (`:62`) `AppTheme.dark()`.
- `lib/core/design_system/themes/`: `ss_light_theme.dart`, `ss_dark_theme.dart`, `ss_high_contrast_theme.dart`, `ss_theme_extensions.dart`. **Egyik sincs importálva a `lib/app/**` fából** (`grep -rn "SsLightTheme\|SsDarkTheme" lib/app lib/main.dart` → 0 találat).
- `SsLightTheme.data()` a `SsThemeExtensions.legacyThemeForBrightness(...)`-ből indul, és NÉGY extensiont ad hozzá: `SsColorScheme`, `SsStateOverlays`, `SsThemeBehavior`, valamint (a legacy-ágon) `SsTypography`. **Vagyis a színek forrása változatlanul a legacy `AppPalette`/`AppColors`** — ez a kör tehát NEM változtat márkaszínt (az az `E15-R02`).
- **Tíz** feature-szintű `*ThemeScope` burkoló él a fán; ezek a kör után feleslegessé válnak, de a MEGSZÜNTETÉSÜK nem ezé a köré (a képernyő-körök viszik).
- `dart run tool/ui_inventory.dart` → **96** képernyő-forrás; `test/ui/goldens/goldens/` **144** PNG.

## 3. Scope

**Benne van:** a `MaterialApp` `theme`/`darkTheme` átállítása `SsLightTheme.data()` / `SsDarkTheme.data()`-ra (a hibaág is) · `SsThemeExtensions` kiegészítése, ha egy extension a legacy ágon hiányzik (pl. a `SsTypography` mindkét fényerőn) · `test/app/theme_adoption_test.dart`: a futó app témája MINDEN elvárt extensiont hordoz, mindkét fényerőn, és a `*ThemeScope` burkoló NÉLKÜLI képernyő is feloldja a `SsColorScheme`-t · `test/ui/goldens/e15_r01_theme_adoption_test.dart`: PNG-mentes variáns-mátrix (nincs raszter-összehasonlítás, csak túlcsordulás- és kivétel-figyelés) hat képernyőre × {világos, sötét} × {en, hu} × {1.0, 2.0 textScale} · `docs/ui/migration-status.md` frissítése a MÉRT új állapottal.

**NINCS benne (tilos):**

- Bármely `lib/features/**` fájl módosítása (képernyő-migráció).
- Márkaszín, paletta vagy tipográfiai token megváltoztatása (`lib/core/theme/**`) — az az `E15-R02`.
- A `*ThemeScope` burkolók törlése.
- Új golden PNG felvétele (ADR 0426: a raszterizáció a merge-kapu architektúráján mérendő).
- `docs/adr/**` — az ADR 0466-ot a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/app/strumsight_app.dart` | a téma átkötése |
| `lib/core/design_system/themes/ss_theme_extensions.dart` | hiányzó extension pótlása mindkét fényerőn |
| `test/app/theme_adoption_test.dart` | ÚJ — a §6 cellái |
| `test/ui/goldens/e15_r01_theme_adoption_test.dart` | ÚJ — PNG-mentes variáns-mátrix |
| `docs/ui/migration-status.md` | a MÉRT állapot frissítése |

**Tilos zóna:** `lib/features/**` · `lib/core/theme/**` · `lib/core/design_system/` egyéb könyvtárai · `test/ui/goldens/goldens/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0466)

### 5.1 EGY token-forrás: az app témája

A migrált komponensek a `Theme.of(context)` extensionjeiből oldják fel a tokeneket. **NEM elfogadható gyengítés:** új feature-szintű `ThemeScope` bevezetése „amíg a migráció tart" — pontosan ezt a kettősséget szünteti meg a kör.

### 5.2 A legacy képernyők NEM romolhatnak el

A `SsLightTheme`/`SsDarkTheme` a legacy témából származik, tehát a nem migrált képernyők látványa változatlan marad. **NEM elfogadható gyengítés:** a `ColorScheme` vagy a `TextTheme` „menet közbeni" átszabása — az vizuális regressziót okozna 53 képernyőn, és ez a kör azt nem méri.

### 5.3 A magas kontrasztú téma nem vész el

A `SsHighContrastTheme` elérhető marad a hozzáférési beállításból. **NEM elfogadható gyengítés:** a harmadik téma csendes kihagyása a bekötésből.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A futó app témája világos ÉS sötét módban is hordozza a `SsColorScheme`, `SsTypography`, `SsStateOverlays`, `SsThemeBehavior` extensiont | `theme_adoption_test.dart` |
| A2 | Egy `*ThemeScope` burkoló NÉLKÜL pumpolt design-rendszer komponens feloldja a tokeneket (nem dob, nem esik vissza alapértékre) | `theme_adoption_test.dart` |
| A3 | A bootstrap-hibaág (recovery képernyő) is a design-rendszer témáját kapja | `theme_adoption_test.dart` |
| A4 | Hat képernyő × 2 fényerő × 2 locale × 2 szövegskála (24 cella) túlcsordulás és kivétel nélkül renderel | `e15_r01_theme_adoption_test.dart` |
| A5 | A meglévő akadálymentességi és navigációs őrök VÁLTOZATLANUL zöldek | a §7 gate |
| A6 | A `migration-status.md` a MÉRT (nem becsült) új állapotot írja: hány képernyő old fel tokent az app témájából | a dokumentum + `theme_adoption_test.dart` szám-cellája |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A `theme:` átáll, de a `darkTheme:` marad `AppTheme.dark()` | A1 (sötét ág) |
| Az extension-lista `copyWith`-nél felülíródik (a legacy extensionök elvesznek) | A1 |
| A hibaág témája marad legacy | A3 |
| A téma átkötése egy képernyőn túlcsordulást okoz 200%-os szövegnél | A4 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** állítsd vissza a `darkTheme`-et `AppTheme.dark()`-ra, futtasd a §7 gate-et → az **A1** sötét cellájának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/app/theme_adoption_test.dart test/ui/goldens/e15_r01_theme_adoption_test.dart test/accessibility/semantics_contract_test.dart test/app/navigation/adaptive_scaffold_test.dart
```

## 8. Implementációs sorrend

1. `test/app/theme_adoption_test.dart` — a mérce ELŐSZÖR (RED).
2. `lib/core/design_system/themes/ss_theme_extensions.dart` — hiányzó extension pótlása.
3. `lib/app/strumsight_app.dart` — mindhárom téma-hivatkozás átkötése.
4. `test/ui/goldens/e15_r01_theme_adoption_test.dart` — a 24 cellás mátrix.
5. `docs/ui/migration-status.md` + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Extension-vesztés `copyWith`-nél.** A leggyakoribb hiba: a `extensions:` felülírja a legacy listát (A1).
- **Néma kontraszt-romlás.** A színforrás nem változik, de az overlay-tokenek igen — az A4 mátrix fogja.
- **Scope-csúszás a képernyők felé.** A tilos zóna szigorú: egy „gyors" képernyő-javítás itt elrejtené, mit mért a kör.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
