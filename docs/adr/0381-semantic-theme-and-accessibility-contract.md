# ADR 0381 — Semantic theme and accessibility contract

**Státusz:** elfogadva (E13-R03 pre-flight, 2026-08-21).

Kapcsolódó források: [ADR 0273](0273-design-system-token-source-of-truth.md),
[`Chapter 13 §9.2–§9.3`](../sdd/13-chapter-13-ui-ux-design-system.md) és
[`E13-R03`](../rounds/e13-r03-semantic-colors-and-themes.md).

## Kontextus

Az E13-R02 compatibility adaptere hét legacy színt olvas, miközben a Chapter
13 teljes `SsColorScheme` szerződése brand-, surface-, text-, status-,
confidence-, offline-, AI- és sync-tokeneket kér három témában. Az ADR 0273
rögzíti az egyetlen színforrást, de nem dönti el, hogyan marad a High Contrast
ténylegesen több egy átszínezett dark témánál, illetve hogyan őrizzük meg azt,
hogy confidence, offline és AI provenance ne csak szín legyen.

## Döntés

1. Az `SsColorScheme` a Chapter 13 §9.2 teljes, 23 mezős szerződését valósítja
   meg. A Dark Studio és Warm Light a megfelelő `AppPalette`-ból, minden téma
   brand- és státuszszínei pedig az `AppColors` publikus API-jából olvasnak.
   A High Contrast is kizárólag ezeket a meglévő értékeket kombinálja; új hex
   nem kerül a design systembe.
2. A szemantikai jelentések nem olvadnak össze: `confidenceLow != danger`,
   `offline != danger`, és `syncPending != warning`. Ezek szerződéses
   invariánsok, nem vizuális preferenciák.
3. A disabled, focus, hover, pressed és selected overlayek névvel ellátott,
   témánként elérhető tokenek. Widget nem találhat ki saját overlay-színt.
4. A High Contrast külön, gépileg vizsgálható theme-karakterisztikát kap:
   erősebb border, nagyobb fókuszgyűrű, teljesen opak surface és kikapcsolt
   dekoratív blur/glow. Nem elegendő a Dark Studio színeit módosítani.
5. Confidence-, offline- és AI-provenance megjelenítéshez a design system
   színtől független marker-contractot (ikon vagy shape) ad. A Component
   Catalog ezt a markert ténylegesen megjeleníti; lokalizált termékszöveget
   ez a fejlesztői kör nem vezet be.
6. A három téma `ThemeData`-ként készül el, és egyaránt tartalmazza az
   `SsColorScheme` és a High Contrast viselkedését is leíró extensiont. A
   legacy `AppTheme` és a production theme-mode wiring ebben a körben nem
   változik.

## Következmények

- A későbbi komponenskörök szemantikai névre támaszkodhatnak hardkódolt szín
  és widgetenkénti overlay-logika nélkül.
- A High Contrast tulajdonságai unit tesztben falszifikálhatók.
- A production témaváltás továbbra is későbbi migrációs feladat; az E13-R03
  csak a theme-konfigurációt és a development-only katalógus kapcsolóját adja.
- A WCAG-kontrasztot egy közös, futtatható számítás méri: normál szöveg
  legalább 4,5:1, fontos nem-szöveges határ legalább 3:1.

## Elvetett alternatívák

- **Új high-contrast hex-paletta:** második igazságforrást hozna létre az ADR
  0273 ellenében.
- **Csak ColorScheme-váltás:** nem bizonyítaná a border-, fókusz-, opacity- és
  effekt-követelményeket.
- **A confidence/offline/AI jelentés kizárólag színnel:** sértené a Chapter 13
  hozzáférhetőségi és bizonyossági határát.
