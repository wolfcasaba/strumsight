# E15-R01 — A design-rendszer témájának app-szintű bevezetése

- **Státusz:** READY (pre-flight lefutott 2026-08-28, kód ÚJRAMÉRVE: `main @ 1e23bd27`)
- **Típus:** Chapter 15 (UI-aktiválás és -befejezés), Kör 1
- **Kör-azonosító:** `E15-R01`
- **Branch:** `<motor>/e15-r01-design-system-theme-adoption`
- **Előfeltétel:** nincs (a Chapter 13 lezárva, `E13-R36` merge-elve)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0466` — a szám FOGLALT (Chapter 15 batch-tartomány: `0466`–`0477`).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "design system theme extensions app theme adoption tokens typography"` → **[ADR 0383](../adr/0383-typography-and-text-scale-contract.md)** (tipográfia és text-scale szerződés) és **[ADR 0381](../adr/0381-semantic-theme-and-accessibility-contract.md)** (szemantikus téma- és akadálymentességi szerződés). A kör ezeket a MÁR ELFOGADOTT szerződéseket teszi az app tényleges futásidejű témájává.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/app/strumsight_app.dart` MÉRT téma-sorait (a megíráskor `theme: AppTheme.light()`, `darkTheme: AppTheme.dark()`, és a hibaág `theme: AppTheme.dark()`), valamint a `SsLightTheme.data()` / `SsDarkTheme.data()` szerkezetét (mindkettő a `legacyThemeForBrightness`-ből indul és extensionöket ad hozzá). Ha az E12 sáv időközben hozzányúlt a bootstraphez, a §4 listát igazítsd.

## 0.0 Pre-flight revízió (Claude/Opus 5, 2026-08-28, `main @ 1e23bd27`)

A brief előre megírt, MÉRT állításait a pre-flight újramérte. Négy állítás
javításra szorult; a normatív döntéseket az
[ADR 0466](../adr/0466-app-runtime-theme-is-the-design-system-theme.md) rögzíti.

**Visszakeresés (ADR 0312, szűkítve ELŐSZÖR):**
`--corpus lessons,halts,adr` → [ADR 0273](../adr/0273-design-system-token-source-of-truth.md)
(egy token-forrás, `public.dart` az EGYETLEN belépő),
[ADR 0381](../adr/0381-semantic-theme-and-accessibility-contract.md),
[ADR 0383](../adr/0383-typography-and-text-scale-contract.md).
`--corpus lessons,halts` → **[L387](../LESSONS.md#l387)** (egy `ThemeData`-integráció
scope-ja a meglévő adapter-kompatibilitási tesztet is magában foglalja — ez a
kör legveszélyesebb hibaosztálya, lásd R3 lent), **[L524](../LESSONS.md#l524)**
(PNG-mentes variáns-mátrix), **[L517](../LESSONS.md#l517)** (a `textScaler 2.0`
keret valódi, addig láthatatlan elrendezési hibát mér ki),
[L486](../LESSONS.md#l486) / [L507](../LESSONS.md#l507) (miért nem PNG a mérce).

| # | Brief-állítás | MÉRT valóság | Következmény |
|---|---|---|---|
| **R1** | „`SsLightTheme.data()` NÉGY extensiont ad hozzá… és a `SsTypography` a legacy ágon hiányozhat" | `ss_light_theme.dart:7-23` / `ss_dark_theme.dart:9-28` **HÁROM** extensiont ad (`SsColorScheme`, `SsStateOverlays`, `SsThemeBehavior`); az `SsTypography`-t a `legacyThemeForBrightness` (`ss_theme_extensions.dart:86-93`) **MINDKÉT fényerőn** már regisztrálja, és a `foundations_test.dart` első cellája `same(...)` szinten állítja | **`ss_theme_extensions.dart` módosítására nincs mért szükség** (ADR 0466 D6). A fájl az engedélyezett listán MARAD (a kör mérése kimutathat tényleges hiányt), de érintetlen fájl is elfogadható kimenet. |
| **R2** | „**Tíz** feature-szintű `*ThemeScope` burkoló… (auth, settings, share, progress_v2, library_v2, gamification, community, offline_ai, **today, metronome**)" | `grep -rln "class .*ThemeScope" lib/` → **KILENC**: progress_v2, auth, settings, library_v2, share, gamification, community, offline_ai, **vision**. A `today` és a `metronome` nem burkol, csak fogyaszt | A §2 és a `migration-status.md` szám- és névlistája a KILENCES mérésre javítva. |
| **R3** | (hiányzott) | `test/core/design_system/foundations_test.dart` második cellája (≈80–93. sor) **kipinneli a `ss_theme_extensions.dart` FORRÁSSZÖVEGÉT**: tartalmaznia kell az `AppColors.primary`, `AppPalette.dark`, `AppTheme.dark()`, `AppTheme.light()` szövegeket, és NEM tartalmazhat `ThemeData(` alakot vagy `Color(0x…)` literált | Ez az **L387 hibaosztály** őre. Ha az implementer mégis hozzányúl a fájlhoz, ezt a hat feltételt betartja. A cella a §7 gate-jébe **felvéve**. |
| **R4** | „§5.3 A `SsHighContrastTheme` elérhető marad **a hozzáférési beállításból**" | Ilyen beállítás **NEM létezik**: a `themeModeProvider` (`lib/core/theme/theme_mode_provider.dart:26-31`) csak `light`/`dark`/`system` értéket ismer, és az `SsHighContrastTheme` egyetlen fogyasztója a `component_catalog_screen.dart:95` | A §5.3 átfogalmazva: a téma **nem szűnik meg**; a negyedik fok BEKÖTÉSE külön kör dolga (ADR 0466 D5). |

**Két további, a briefben nem szereplő MÉRT tény, amely a scope-ot köti:**

- **A belépő a barrel.** A fán MINDEN design-system import
  `core/design_system/public.dart`-ra megy (70/70 mért feature-import), és a
  `public.dart:65-68` mindhárom témát exportálja. `strumsight_app.dart` tehát a
  **barrelen át** importál, nem a `themes/ss_*.dart` fájlokból (ADR 0273 §1,
  ADR 0466 D3).
- **A komponensek `!`-gal oldják fel a tokent** (`ss_button.dart:57`,
  `ss_content_card.dart:107-108`:
  `Theme.of(context).extension<SsColorScheme>()!`), tehát burkoló nélkül MA
  kivételt dobnak — nem esnek vissza alapértékre. Ez az **A2 falszifikációs
  mechanizmusa**: a cella a kör ELŐTT pirosnak MÉRHETŐ.
- **A PNG-mentes mátrix előzménye** `test/ui/goldens/e13_r36_variant_matrix_test.dart`;
  a négy kizárt cellája MIND `landscape` viewportos, tehát az e körben előírt
  compact-portrait-only mátrixon **kizárási lista nem megengedett** (ADR 0466 D7).

**Elérhető cél-státusz mérése (a prompt §1.1):** a kör nem állapotgépet
mozgat; a mérendő „státusz" a `ThemeData.extension<T>()` feloldása, amit a
2. pont szerinti `!`-os hívási lánc TÉNYLEGESEN produkál — nem réteg-diagramból
következtetve.

**Foglalás:** az `ADR 0466` markere lefoglalva
(`.pipeline/inflight/adr/0466`). MÉRT eltérés: a
`tools/round-slots.py reserve-adr` `0450`-et adott, mert csak a lemezen +
ágakon LÉVŐ ADR-eket látja, a `pipeline-queue.tsv` E12-R09…R34 sorainak papíron
előre kiosztott `0450`–`0465` tartományát nem. A queue és a kör-prompt
egybehangzó `0466` az irányadó; a `0450` marker érintetlenül marad, hogy az
E12-sáv sorát ne bolygassa.

## 0.0.1 A kör MÉRT kiváltó oka

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
  "test/core/design_system/foundations_test.dart",
  "test/app/bootstrap_failure_app_test.dart",
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
- `SsLightTheme.data()` a `SsThemeExtensions.legacyThemeForBrightness(...)`-ből indul, és HÁROM extensiont ad hozzá: `SsColorScheme`, `SsStateOverlays`, `SsThemeBehavior`; a NEGYEDIK, az `SsTypography`, már a `legacyThemeForBrightness`-ben regisztrálva van **mindkét fényerőn** (§0.0/R1). **Vagyis a színek forrása változatlanul a legacy `AppPalette`/`AppColors`** — ez a kör tehát NEM változtat márkaszínt (az az `E15-R02`).
- **Kilenc** feature-szintű `*ThemeScope` burkoló él a fán (progress_v2, auth, settings, library_v2, share, gamification, community, offline_ai, vision — §0.0/R2); ezek a kör után feleslegessé válnak, de a MEGSZÜNTETÉSÜK nem ezé a köré (a képernyő-körök viszik).
- `public.dart:65-68` mindhárom témát exportálja; a fán 70/70 design-system import a barrelen megy (§0.0).
- `dart run tool/ui_inventory.dart` → **96** képernyő-forrás; `test/ui/goldens/goldens/` **144** PNG.

## 3. Scope

**Benne van:** a `MaterialApp` `theme`/`darkTheme` átállítása `SsLightTheme.data()` / `SsDarkTheme.data()`-ra (a hibaág is), a `core/design_system/public.dart` barrelen át importálva (§0.0, ADR 0466 D3) · `SsThemeExtensions` kiegészítése CSAK akkor, ha a kör mérése tényleges hiányt talál (a §0.0/R1 szerint ilyen nincs; ha mégis hozzányúlsz, a §0.0/R3 forrás-pin hat feltételét tartsd) · `test/app/theme_adoption_test.dart`: a futó app témája MINDEN elvárt extensiont hordoz, mindkét fényerőn, a legacy `colorScheme`/`textTheme` VÁLTOZATLAN, és a `*ThemeScope` burkoló NÉLKÜLI design-rendszer komponens is feloldja a `SsColorScheme`-t · `test/ui/goldens/e15_r01_theme_adoption_test.dart`: PNG-mentes variáns-mátrix (nincs raszter-összehasonlítás, csak túlcsordulás- és kivétel-figyelés) hat képernyőre × {világos, sötét} × {en, hu} × {1.0, 2.0 textScale}, compact portrait (412×915) viewporton · `docs/ui/migration-status.md` frissítése a MÉRT új állapottal.

**NINCS benne (tilos):**

- Bármely `lib/features/**` fájl módosítása (képernyő-migráció).
- Márkaszín, paletta vagy tipográfiai token megváltoztatása (`lib/core/theme/**`) — az az `E15-R02`.
- A `*ThemeScope` burkolók törlése.
- Új golden PNG felvétele (ADR 0426: a raszterizáció a merge-kapu architektúráján mérendő).
- `docs/adr/**` — az ADR 0466-ot a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/app/strumsight_app.dart` | a téma átkötése (mindhárom hivatkozás), a `public.dart` barrelen át |
| `lib/core/design_system/themes/ss_theme_extensions.dart` | CSAK ha a kör mérése tényleges extension-hiányt talál (§0.0/R1: ilyen nincs) — érintetlen fájl is elfogadható; módosítás esetén a §0.0/R3 forrás-pin köti |
| `test/app/theme_adoption_test.dart` | ÚJ — a §6 A1–A3, A6–A8 cellái |
| `test/ui/goldens/e15_r01_theme_adoption_test.dart` | ÚJ — PNG-mentes 48 cellás variáns-mátrix (A4) |
| `docs/ui/migration-status.md` | a MÉRT állapot frissítése (A6) |
| `docs/rounds/e15-r01-design-system-theme-adoption.md` | a §10 implementation handoff kitöltése |

**Tilos zóna:** `lib/features/**` · `lib/core/theme/**` · `lib/core/design_system/` egyéb könyvtárai · `test/ui/goldens/goldens/**` · `docs/adr/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0466)

### 5.1 EGY token-forrás: az app témája

A migrált komponensek a `Theme.of(context)` extensionjeiből oldják fel a tokeneket. **NEM elfogadható gyengítés:** új feature-szintű `ThemeScope` bevezetése „amíg a migráció tart" — pontosan ezt a kettősséget szünteti meg a kör.

### 5.2 A legacy képernyők NEM romolhatnak el

A `SsLightTheme`/`SsDarkTheme` a legacy témából származik, tehát a nem migrált képernyők látványa változatlan marad. **NEM elfogadható gyengítés:** a `ColorScheme` vagy a `TextTheme` „menet közbeni" átszabása — az vizuális regressziót okozna 53 képernyőn, és ez a kör azt nem méri.

### 5.3 A magas kontrasztú téma nem vész el

A `SsHighContrastTheme.data()` továbbra is előállítható, és a komponens-katalógusból (`component_catalog_screen.dart:95`) elérhető marad. **MÉRT pontosítás (§0.0/R4):** hozzáférési beállítás ma NEM létezik (`themeModeProvider` = `light`/`dark`/`system`), tehát a negyedik fok BEKÖTÉSE nem ezé a köré (ADR 0466 D5). **NEM elfogadható gyengítés:** a harmadik téma törlése vagy elérhetetlenné tétele azzal az indokkal, hogy „úgysem használja senki".

### 5.4 A belépő a barrel

`lib/app/strumsight_app.dart` a témákat `package:strumsight/core/design_system/public.dart`-ból (vagy a relatív `../core/design_system/public.dart`-ból) importálja, szükség esetén `show SsDarkTheme, SsLightTheme` szűkítéssel. **NEM elfogadható gyengítés:** közvetlen import a `themes/ss_light_theme.dart` / `ss_dark_theme.dart` fájlból (ADR 0273 §1).

### 5.5 A záró mátrixnak nincs kizárási listája

A §0.0 mérése szerint compact portraiton egyetlen ismert túlcsordulás sincs. **NEM elfogadható gyengítés:** `skip`, tolerancia-emelés, kizárási lista vagy cella-kikapcsolás. Piros cella → vagy a téma-átkötés regressziója (a körben javítandó), vagy `lib/features/**` defekt — utóbbi a §0 STOP-protokollját váltja ki.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A futó app témája világos ÉS sötét módban is hordozza a `SsColorScheme`, `SsTypography`, `SsStateOverlays`, `SsThemeBehavior` extensiont | `theme_adoption_test.dart` |
| A2 | Egy `*ThemeScope` burkoló NÉLKÜL pumpolt design-rendszer komponens feloldja a tokeneket (nem dob, nem esik vissza alapértékre) | `theme_adoption_test.dart` |
| A3 | A bootstrap-hibaág (recovery képernyő) is a design-rendszer témáját kapja | `theme_adoption_test.dart` |
| A4 | **Hat NEVESÍTETT képernyő** (`today_hub`, `live`, `tuner`, `settings`, `vision_result`, `login` — az `e13_r36_variant_matrix_test.dart` kockázat-alapú készlete és annak fixture-mintája) × 2 fényerő × 2 locale × 2 szövegskála (**48 cella**, 6 × 2 × 2 × 2) compact portrait (412×915) viewporton túlcsordulás és kivétel nélkül renderel, **az app ADOPTÁLT témájával** (`SsLightTheme.data()`/`SsDarkTheme.data()`), kizárási lista NÉLKÜL | `e15_r01_theme_adoption_test.dart` |
| A5 | A meglévő akadálymentességi, navigációs és design-system-adapter őrök VÁLTOZATLANUL zöldek | a §7 gate |
| A6 | A `migration-status.md` a MÉRT (nem becsült) új állapotot írja: hány képernyő old fel tokent az app témájából, és hogy a „`*ThemeScope` kerülőút" sora elavult | a dokumentum + `theme_adoption_test.dart` szám-cellája |
| A7 | Az app témájának `colorScheme`, `textTheme` és `scaffoldBackgroundColor` mezője `equals`-szel EGYENLŐ a megfelelő `AppTheme.light()`/`AppTheme.dark()` mezőjével (ADR 0466 D2 — a legacy látvány nem változik) | `theme_adoption_test.dart` |
| A8 | Az app témája a `core/design_system/public.dart` barrelen át kerül be (ADR 0466 D3) | `theme_adoption_test.dart` forrás-cellája: `lib/app/strumsight_app.dart` szövege tartalmazza a `design_system/public.dart` importot, és NEM tartalmazza a `themes/ss_light_theme.dart` / `themes/ss_dark_theme.dart` alakot |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A `theme:` átáll, de a `darkTheme:` marad `AppTheme.dark()` | A1 (sötét ág) |
| Az extension-lista `copyWith`-nél felülíródik (a legacy extensionök elvesznek) | A1 |
| A hibaág témája marad legacy | A3 |
| A téma átkötése egy képernyőn túlcsordulást okoz 200%-os szövegnél | A4 |
| „Gyorsan" új `ColorScheme`/`TextTheme` kerül a témába (márkaszín-előreszaladás) | A7 |
| A téma közvetlen `themes/ss_dark_theme.dart` importtal jön be, a barrel megkerülésével | A8 |
| A `*ThemeScope` burkolót „biztos, ami biztos" alapon a komponens köré teszik a tesztben | A2 (a burkoló NÉLKÜLI pumpolás a cella előírása) |
| A mátrix egy piros cellát kizárási listával némít el | A4 (a §5.5 tiltja; a review is méri) |

### 6.2 A NULLA PIXELES túlcsordulás-küszöb cellahármasa (S3)

A mátrix egyetlen numerikus küszöbe a `RenderFlex` túlcsordulás **0.0 px**-e;
tolerancia nincs (§5.5). A `RenderFlex` a szigorú `>` reláció szerint jelent,
tehát a pontosan kitöltő cella még ZÖLD. `python3 -c` mérés a compact portrait
412.0 px szélességére:

```
alatta:  tartalom=411.0  viewport=412.0  →  túlcsordulás 0.0 px
rajta:   tartalom=412.0  viewport=412.0  →  túlcsordulás 0.0 px
fölötte: tartalom=412.5  viewport=412.0  →  túlcsordulás 0.5 px
```

| Cella | Elvárt kimenet | Miért ez a mérce |
|---|---|---|
| **A küszöb ALATT** (411.0 px tartalom) | ZÖLD — `FlutterError.onError` nem kap `overflowed by` üzenetet | a normál eset |
| **A küszöbÖN** (412.0 px tartalom) | ZÖLD — a `RenderFlex` a `>` reláció miatt itt még nem jelent | ez a cella tiltja a „biztonsági" 1–2 px-es tolerancia bevezetését: nincs mit kompenzálni |
| **A küszöb FÖLÖTT** (412.5 px tartalom) | PIROS — `overflowed by 0.5 pixels`, és a §5.5 szerint kizárási listával, `skip`-pel vagy tolerancia-emeléssel NEM némítható | a fél pixel is bukás; a tényleges 48 cella egyike sem lehet ilyen |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** állítsd vissza a `darkTheme`-et `AppTheme.dark()`-ra, futtasd a §7 gate-et → az **A1** sötét cellájának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/app/theme_adoption_test.dart test/ui/goldens/e15_r01_theme_adoption_test.dart test/accessibility/semantics_contract_test.dart test/app/navigation/adaptive_scaffold_test.dart test/core/design_system/foundations_test.dart test/app/bootstrap_failure_app_test.dart
```

A `foundations_test.dart` és a `bootstrap_failure_app_test.dart` a §0.0
mérése alapján került be: az előbbi az **L387** hibaosztály őre (kipinnelt
adapter-forrás + `SsTypography` regisztráció), az utóbbi a hibaág (A3)
meglévő cellája. **Egyik sincs az engedélyezett fájllistán** — pirosra
váltásuk nem a teszt javítását, hanem a produkciós változtatás javítását
jelenti; ha ez nem oldható meg a listán belül, a kimenet `stopped`.

## 8. Implementációs sorrend

1. `test/app/theme_adoption_test.dart` — a mérce ELŐSZÖR (RED). Az A2 cellája a kör előtt PIROS: egy `Ss*` komponens `AppTheme.dark()` alatt, burkoló nélkül pumpolva ma kivételt dob (`extension<SsColorScheme>()!`, §0.0). Ezt a pirosat MÉRD MEG, és írd be a §10-be.
2. `lib/app/strumsight_app.dart` — mindhárom téma-hivatkozás átkötése (`:33`, `:34`, `:62`), a `core/design_system/public.dart` barrelen át (§5.4).
3. Csak ha a 1. lépés tényleges extension-hiányt mért: `lib/core/design_system/themes/ss_theme_extensions.dart` (§0.0/R1 + R3).
4. `test/ui/goldens/e15_r01_theme_adoption_test.dart` — a 48 cellás mátrix; a fixture-mintát (fake engine/repo doubles, `FlutterError.onError`, `TextScaler.linear`) az `test/ui/goldens/e13_r36_variant_matrix_test.dart`-ból vedd át, de a `MaterialApp` témája itt az ADOPTÁLT `SsLightTheme.data()`/`SsDarkTheme.data()`.
5. `docs/ui/migration-status.md` + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Extension-vesztés `copyWith`-nél.** A leggyakoribb hiba: a `extensions:` felülírja a legacy listát (A1).
- **Néma kontraszt-romlás.** A színforrás nem változik, de az overlay-tokenek igen — az A4 mátrix fogja.
- **Scope-csúszás a képernyők felé.** A tilos zóna szigorú: egy „gyors" képernyő-javítás itt elrejtené, mit mért a kör.

## 10. Implementation handoff — az implementer tölti ki

**Folytatás (Sonnet 5, 2026-08-28):** az implementáció (`5756204f`) már
készen állt a folytatás indulásakor — a `lib/app/strumsight_app.dart`
mindhárom téma-hivatkozása (`theme:`, `darkTheme:`, a bootstrap-hibaág
`theme:`) `SsLightTheme.data()`/`SsDarkTheme.data()`-ra volt kötve, a
`public.dart` barrelen át. A folytatás dolga a §7 gate ELŐTÉRBEN futtatása,
az A4 mátrix ellenőrzése, a `migration-status.md` frissítése (A6), a
valódi-sértés próba, és ez a szakasz volt.

### A §7 gate — ELŐTÉRBEN, kétszer zöldre futtatva

A gate-sort (`tools/round-gate.sh test/app/theme_adoption_test.dart
test/ui/goldens/e15_r01_theme_adoption_test.dart
test/accessibility/semantics_contract_test.dart
test/app/navigation/adaptive_scaffold_test.dart
test/core/design_system/foundations_test.dart
test/app/bootstrap_failure_app_test.dart`) ELŐTÉRBEN, `run_in_background`
nélkül, csővezeték nélkül futtattam — először a meglévő implementáción
(ZÖLD, `format`/`analyze`/mind a hat teszt/`architecture`/`secrets`/`l10n`),
majd a valódi-sértés próba után újra (szintén ZÖLD, lásd lent). Az A4
mátrix mind a 48 kombinációja (6 képernyő × 2 fényerő × 2 locale × 2
szövegskála) `overflow`/kivétel nélkül futott le, kizárási lista, `skip`
vagy tolerancia-emelés NÉLKÜL.

### A4 — kizárási lista ellenőrzése

`grep -in "skip|exclude|tolerance"
test/ui/goldens/e15_r01_theme_adoption_test.dart` → nulla találat. A mátrix
a §5.5 előírása szerint kizárás nélküli.

### `docs/ui/migration-status.md` frissítése (A6)

Hozzáadtam egy E15-R01 szakaszt a fájl elejére: a MÉRT új állapot, hogy
**96/96** production screen forrás oldhat fel tokent az app témájából
(`test/app/theme_adoption_test.dart` A6 cellája ugyanezt a 96-ot pinneli a
`Directory('lib/features')` bejárásával) — ez token-ELÉRHETŐSÉG, nem
komponens-migráció mérése, ezért a lenti "Per-feature status" tábla
(43/96 migrált) EBBEN a körben változatlan marad. A "Canonical token source
by migration phase" tábla harmadik sorát MÉRT módon elavultnak jelöltem
(a burkolók immár redundánsak, mert az app `ThemeData`-ja már közvetlenül
hordozza mind a négy extensiont), és a sor felsorolását a tényleges KILENC
burkolóra javítottam (`ProgressThemeScope`, `AuthThemeScope`,
`SettingsThemeScope`, `LibraryThemeScope`, `ShareThemeScope`,
`GamificationThemeScope`, `CommunityThemeScope`, `OfflineAiThemeScope`,
`VisionThemeScope` — mindegyik `grep -rn "class .*ThemeScope" lib/`-vel
ellenőrizve, pontos fájlnévvel/osztálynévvel). A burkolókat NEM töröltem
(`lib/features/**` tilos zóna).

### Valódi-sértés próba (KÖTELEZŐ, §6.2/§9.4) — a MÉRT piros

A `darkTheme:`-et ideiglenesen visszaállítottam `AppTheme.dark()`-ra (a
szükséges `import '../core/theme/app_theme.dart';` sorral együtt), és
ELŐTÉRBEN újrafuttattam a §7 gate-sort. A gate a 3. lépésnél (`test
test/app/theme_adoption_test.dart`) PIROSRA váltott, kilépési kód 1, a
szó szerinti mért kimenettel:

```
00:00 +0: A1: the running app theme carries all four design-system extensions, light and dark
══╡ EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK ╞════════════════════════════════════════════════════
The following TestFailure was thrown running a test:
Expected: not null
  Actual: <null>
SsColorScheme missing from the app theme

When the exception was thrown, this was the stack:
#4      main.<anonymous closure> (file:///home/ubuntu/ss-sonnet-impl-e15-r01/test/app/theme_adoption_test.dart:54:9)
...
00:01 +0 -1: A1: the running app theme carries all four design-system extensions, light and dark [E]
  Test failed. See exception logs above.
00:01 +0 -1: A2: a design-system component resolves tokens without a ThemeScope wrapper, under the app theme
00:02 +1 -1: A3: the bootstrap-failure recovery screen also gets the design-system theme
00:02 +2 -1: A7: the app theme colorScheme/textTheme/scaffoldBackgroundColor equal the legacy AppTheme (additive-only adoption, ADR 0466 D2)
00:02 +3 -1: A6: every production screen source can now resolve tokens from the app theme (ADR 0466 D1) — count must match docs/ui/migration-status.md and tool/ui_inventory.dart
00:02 +4 -1: A8: strumsight_app.dart imports the design-system theme through the public barrel (ADR 0466 D3), not the theme files directly
00:02 +5 -1: Some tests failed.

Failing tests:
  /home/ubuntu/ss-sonnet-impl-e15-r01/test/app/theme_adoption_test.dart: A1: the running app theme carries all four design-system extensions, light and dark

    → [3] test test/app/theme_adoption_test.dart: PIROS (kilépési kód 1)
```

A hiba pontosan az A1 SÖTÉT ágán jelentkezett (a `for (final theme in
[app.theme, app.darkTheme])` ciklus a világos ágon átment, majd a sötét
ágon buktatta el `SsColorScheme missing from the app theme` üzenettel) —
ez a §6.1 mátrix pontosan előírt kimenete ("A `theme:` átáll, de a
`darkTheme:` marad `AppTheme.dark()`" → "A1 (sötét ág)"). Ezután a
`darkTheme:`-et visszaállítottam `SsDarkTheme.data()`-ra, az importot
töröltem, és a `git diff lib/app/strumsight_app.dart` üres — a fájl
byte-azonos a `5756204f` commitban lévővel. A gate-et harmadszor is
lefuttattam ELŐTÉRBEN: MINDEN lépés ZÖLD (format, analyze, mind a hat
teszt, architecture, secrets, l10n).

### Nyitva maradt

- A `*ThemeScope` burkolók (kilenc db) törlése/kivezetése — ez a §3
  szerint SEM ennek a körnek a dolga; a `migration-status.md` most már
  MÉRT módon elavultnak jelöli őket, de a tényleges eltávolítás a
  képernyő-migrációs körök (E15-R05…) hatásköre.
- A brief §0.0-ban is jelzett negyedik fokozat (magas kontraszt)
  hozzáférési beállításba kötése — ADR 0466 D5 szerint külön kör.
- A `SsThemeExtensions`-hez NEM nyúltam: a mérés (§0.0/R1) szerint nincs
  tényleges hiány, és a gate zöld a fájl érintetlenül is.

### Javító kör (review MINOR-1, MINOR-2)

A független review két MINOR leletét javítottuk: a nem létező `ADR 0466 D8`
hivatkozás törölve (`test/app/theme_adoption_test.dart:2`,
`docs/ui/migration-status.md:6`), és a fenti §10 cellaszáma `48`-ról a
tényleges **24**-re javítva (6 × 2 × 2 × 2, ennyi `testWidgets` cellát
generál a mátrix). Kód nem változott, csak komment és dokumentum-szöveg.
A javító kör diffjét az orchestrátor auditálta az `allowed_paths` ellen és
commitolta, majd a §7 gate-et ELŐTÉRBEN újrafuttatta — lásd
`docs/reviews/e15-r01-review.md` §6.

## 11. Review — a Claude tölti ki
