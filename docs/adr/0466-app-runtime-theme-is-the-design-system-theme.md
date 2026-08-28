# ADR 0466 — Az app futásidejű témája a design-rendszer témája

- **Státusz:** elfogadva (2026-08-28, E15-R01 pre-flight)
- **Kontextus:** SDD Chapter 15, Kör 1;
  [`docs/rounds/e15-r01-design-system-theme-adoption.md`](../rounds/e15-r01-design-system-theme-adoption.md)
- **Kapcsolódó:** [ADR 0273](0273-design-system-token-source-of-truth.md)
  (egy token-forrás: a design system OLVAS, nem másol; `public.dart` az egyetlen
  belépő), [ADR 0381](0381-semantic-theme-and-accessibility-contract.md)
  (`SsColorScheme` 23 mezős szerződése, overlay-tokenek, High Contrast),
  [ADR 0383](0383-typography-and-text-scale-contract.md) (`SsTypography` és a
  text-scale szerződés; „a design-system témák kapják meg az új extensiont"),
  [ADR 0426](0426-golden-rasterization-on-the-gate-architecture.md) (a
  raszterizáció a kapu architektúráján mérendő), [L387](../LESSONS.md#l387) (egy
  `ThemeData`-integráció scope-ja a meglévő adapter-kompatibilitási tesztet is
  magában foglalja), [L524](../LESSONS.md#l524) (a PNG NÉLKÜLI variáns-mátrix
  olyan defektet mért ki, amit a golden-készlet és a teljes CI-suite átengedett)

## Kontextus — mért tények (E15-R01 pre-flight, `main @ 1e23bd27`)

1. **A design-rendszer témája SOHA nem lépett működésbe.**
   `lib/app/strumsight_app.dart:33-34` → `theme: AppTheme.light()`,
   `darkTheme: AppTheme.dark()`; a bootstrap-hibaág (`:62`) `AppTheme.dark()`.
   `grep -rn "SsLightTheme\|SsDarkTheme" lib/app lib/main.dart` → **0 találat**.
2. **A három téma megépült és összefügg.**
   `SsLightTheme.data()` (`ss_light_theme.dart:7-23`) és
   `SsDarkTheme.build()` (`ss_dark_theme.dart:9-28`) egyaránt a
   `SsThemeExtensions.legacyThemeForBrightness(...)`-ből indul, és HÁROM
   extensiont ad hozzá: `SsColorScheme`, `SsStateOverlays`, `SsThemeBehavior`.
   `SsHighContrastTheme.data()` = `SsDarkTheme.build(highContrast: true)`.
3. **Az `SsTypography` MÁR MOST mindkét fényerőn rajta van** — a
   `legacyThemeForBrightness` (`ss_theme_extensions.dart:86-93`) a legacy
   `ThemeData`-t `copyWith(extensions: [...legacy.extensions.values, typography])`
   alakban adja vissza, és a
   `test/core/design_system/foundations_test.dart` első cellája ezt
   mindkét fényerőre `same(SsThemeExtensions.typography)` szinten állítja.
   **Következmény:** a briefben feltételezett „hiányzó extension pótlása" nem
   létező hiányra vonatkozott — `ss_theme_extensions.dart` módosítására nincs
   mért szükség (lásd D6).
4. **A színforrás valóban nem változik.** Mindkét téma `legacy.copyWith(...)`,
   azaz a `colorScheme`, a `textTheme` és a `scaffoldBackgroundColor` a legacy
   `AppTheme`-ből jön változatlanul; csak az `extensions` lista bővül.
5. **A komponensek `!`-gal oldják fel a tokent, tehát a hiányzó extension
   DOB, nem esik vissza alapértékre:**
   `ss_button.dart:57` és `ss_content_card.dart:107-108` →
   `Theme.of(context).extension<SsColorScheme>()!`. Ez a kör falszifikációs
   mechanizmusa: burkoló nélkül ma kivétel, a kör után feloldás.
6. **A belépő a barrel.** A fán MINDEN design-system import
   `core/design_system/public.dart`-ra megy (70/70 mért feature-import), és a
   `public.dart:65-68` mindhárom témát exportálja. Belső téma-fájl közvetlen
   importja tehát megszegné az ADR 0273 §1-et.
7. **Az adapter forrásszövege KIPINNELT.** A
   `test/core/design_system/foundations_test.dart` második cellája (≈80–93.
   sor) beolvassa a `ss_theme_extensions.dart` forrását, és megköveteli, hogy
   tartalmazza az `AppColors.primary`, `AppPalette.dark`, `AppTheme.dark()`,
   `AppTheme.light()` szövegeket, ÉS ne tartalmazza a `ThemeData(` alakot vagy
   `Color(0x…)` literált. Ez az L387 hibaosztály őre.
8. **A High Contrast ma NEM hozzáférési beállításból érhető el.** Az egyetlen
   fogyasztója a `component_catalog_screen.dart:95`
   (`_CatalogTheme.highContrast => SsHighContrastTheme.data()`); a
   `themeModeProvider` (`lib/core/theme/theme_mode_provider.dart`) csak
   `light`/`dark`/`system` értéket ismer, negyedik fok nincs.
9. **A kettősség mérete.** `grep -rln "class .*ThemeScope" lib/` → **9**
   feature-szintű burkoló (progress_v2, auth, settings, library_v2, share,
   gamification, community, offline_ai, vision — a `today` és a `metronome`
   NEM burkol, csak fogyaszt). `lib/features/**` alatt **22** fájl hivatkozik
   `SsColorScheme`-re vagy `SsTypography`-ra.
10. **Van PNG-mentes mátrix-előzmény.**
    `test/ui/goldens/e13_r36_variant_matrix_test.dart` a bevett minta
    (`FlutterError.onError`-ra kötött túlcsordulás- és kivétel-figyelés). A
    négy kizárt cellája MIND `landscape` viewportos (`live`, 12 px / 34 px,
    2026-08-27) — compact portrait viewporton EGYETLEN kizárt cella sincs.

## Döntés

### D1 — Az app futásidejű témája a design-rendszer témája, a hibaágon is

A `MaterialApp.router` `theme:` = `SsLightTheme.data()`, `darkTheme:` =
`SsDarkTheme.data()`, és a `BootstrapFailureApp` `theme:` = `SsDarkTheme.data()`.
Ettől a fán MINDEN képernyő — a migrált és a migrálatlan is — ugyanabból a
`ThemeData`-ból oldja fel a tokeneket.

*Az elutasított alternatíva:* „amíg a migráció tart, maradjon a legacy téma, és
minden képernyő hozza a saját `ThemeScope`-ját". Pontosan ezt a kettősséget
szünteti meg a kör: 9 burkoló mellett a nem burkolt képernyők egyáltalán nem
látják a tokeneket, és minden új képernyő újabb burkolót örököl.

### D2 — Az átállás ADDITÍV: a legacy látvány bitre változatlan

A `SsLightTheme`/`SsDarkTheme` a legacy `AppTheme`-ből származik
(`legacy.copyWith(extensions: …)`), tehát a `colorScheme`, a `textTheme` és a
`scaffoldBackgroundColor` NEM változhat. Ez falszifikálható állítás: az app
témájának ezen mezői `equals`-szel egyenlők a megfelelő `AppTheme` mezőivel.

*Az elutasított alternatíva:* a `ColorScheme` vagy a `TextTheme` „menet közbeni"
átszabása. Az 53 még nem migrált képernyőn néma vizuális regressziót okozna,
és ez a kör azt nem méri. Márkaszín-változtatás az `E15-R02` dolga.

### D3 — A belépő a `core/design_system/public.dart` barrel

`lib/app/strumsight_app.dart` a témákat a barrelen át importálja (szükség
esetén `show SsDarkTheme, SsLightTheme` szűkítéssel a névütközés ellen), NEM a
`themes/ss_*.dart` fájlokból közvetlenül. Ez az ADR 0273 §1 következménye, és
a fán mért 70/70 import mintája.

### D4 — Négy extension a szerződés, mindkét fényerőn

Az app témája világos ÉS sötét módban egyaránt hordozza a `SsColorScheme`,
`SsTypography`, `SsStateOverlays`, `SsThemeBehavior` extensiont. A négyes
lista a szerződés; egy `copyWith`, amely a legacy extensionöket elejti, ezt a
cellát pirosra viszi.

### D5 — A High Contrast téma nem vész el, de a bekötése nem ezé a köré

`SsHighContrastTheme.data()` továbbra is előállítható és a komponens-katalógusból
elérhető marad. A negyedik téma-fok bekötése a `themeModeProvider`-be vagy egy
hozzáférési beállításba **külön kör** dolga (Chapter 15 későbbi köre) — a
mai fán ilyen beállítás nem létezik (mért tény 8.), tehát ez a kör nem
„megőrzi a beállítást", hanem nem szünteti meg a témát.

*Az elutasított alternatíva:* a harmadik téma csendes kihagyása a
design-rendszerből, mert „úgysem használja senki".

### D6 — `ss_theme_extensions.dart` mért módosítási igény nélkül marad

A mért tény 3. szerint az `SsTypography` mindkét fényerőn regisztrált, tehát
nincs pótolandó extension. A fájl az engedélyezett listán marad (a kör
mérése kimutathat egy tényleges hiányt), de módosítása esetén a mért tény 7.
szerinti forrás-pin köti: `AppTheme.dark()`/`AppTheme.light()` szövegnek benne
kell maradnia, `ThemeData(` és színliterál nem kerülhet bele.

### D7 — A záró mátrix PNG-mentes, és kizárási lista NÉLKÜL zöld

Az A4 mátrix hat képernyő × {világos, sötét} × {en, hu} × {1.0, 2.0 textScale}
= 24 cella, compact portrait (412×915) viewporton, `FlutterError.onError`-ra
kötött túlcsordulás- és kivétel-figyeléssel (L524 mintája), **új golden PNG
nélkül** (ADR 0426). A mért tény 10. szerint compact portraiton nincs ismert
túlcsordulás, ezért **kizárási lista nem megengedett**: egy piros cella vagy
a téma-átkötés regressziója (a körben javítandó), vagy egy `lib/features/**`
defekt — utóbbi a brief STOP-protokollját váltja ki, nem egy kizárást.

## Következmények

- A `*ThemeScope` burkolók funkcionálisan feleslegessé válnak, de a törlésük a
  képernyő-körökre marad; amíg élnek, ártalmatlan duplikáció (ugyanazt az
  extension-halmazt regisztrálják újra).
- A migrálatlan képernyők látványa változatlan (D2), viszont onnantól
  fogva bármelyikük használhat `Ss*` komponenst burkoló nélkül.
- Az `E15-R02` márkaszín-köre egyetlen ponton, a design-rendszer témáján át
  hat az egész appra — nem 53 képernyőnyi legacy hivatkozáson át.
- A `docs/ui/migration-status.md` „Canonical token source by migration phase"
  táblájának harmadik sora (a `*ThemeScope`-os kerülőút) a kör után MÉRT
  módon elavul, és ezt a dokumentumnak rögzítenie kell.
