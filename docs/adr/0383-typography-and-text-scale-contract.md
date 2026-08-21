# ADR 0383 — Typography and text-scale contract

**Státusz:** elfogadva (E13-R04 pre-flight, 2026-08-21).

Kapcsolódó források: [ADR 0273](0273-design-system-token-source-of-truth.md),
[ADR 0381](0381-semantic-theme-and-accessibility-contract.md),
[`Chapter 13 §9.4`](../sdd/13-chapter-13-ui-ux-design-system.md) és
[`E13-R04`](../rounds/e13-r04-typography-and-text-scale.md).

## Kontextus

A Chapter 13 a Poppins és Montserrat szerepét, tizenegy tipográfiai tokent,
200%-os text-scale clipping-mentességet és adaptív chord hero viselkedést ír
elő. A fontok ténylegesen jelen vannak a `pubspec.yaml`-ban, de a design
systemben még nincs tipográfiai contract. A Dark Studio és Warm Light témák a
`SsThemeExtensions.legacyThemeForBrightness` adapteren át épülnek, a High
Contrast pedig a Dark Studio buildjét használja; ez a közös bekötési pont.

## Döntés

1. Az `SsTypography` immutable `ThemeExtension`, amely a Chapter 13 §9.4
   mind a tizenegy tokenjét névvel adja. A Poppins a chord-, heading-, CTA- és
   body-szerepeket, a Montserrat a három metric-szerepet viszi.
2. A metric stílusok `FontFeature.tabularFigures()` feature-t kérnek. A
   production metric-label helper az értéket és az egységet nem törő
   szóközzel kapcsolja össze, így például a `120 BPM` nem válhat két,
   értelmetlen sorra.
3. A tipográfia a közös legacy-theme adapterben kerül a `ThemeData`
   extensionjei közé. A már meglévő extensionök megmaradnak; a Dark Studio,
   Warm Light és High Contrast témából azonos tipográfiai contract kérhető le.
4. Az `SsChordHeroText` egyetlen, teljes chord labelt renderel. A platform
   text scalerét nem írja felül, a tervezési méretet a viewport alapján 80 és
   128 logical pixel között választja, és csak tényleges helyhiánynál használ
   `BoxFit.scaleDown` viselkedést. Ellipszis és karakterlevágás tilos.
5. A hosszú magyar fixture legalább 30%-kal hosszabb a párba állított rövid
   referenciánál. A widgetmátrix 1.0, 1.3, 2.0 és nem követelményként 2.5
   text scale-en ellenőrzi, hogy nincs render overflow vagy exception.

## Következmények

- A későbbi design-system komponensek egyetlen theme-extension contractból
  olvashatják a stílusokat, ad hoc `TextStyle` nélkül.
- A tabular figure kérés és a nem törő metric label külön unit cellával
  falszifikálható.
- A chord hero megőrzi az accessibility text scale jelét, miközben hosszú
  akkordnévnél információvesztés nélkül fér el.
- A production legacy `AppTheme` közvetlen fogyasztói ebben a körben nem
  migrálnak; a design-system témák kapják meg az új extensiont.

## Elvetett alternatívák

- **Statikus style-katalógus ThemeExtension nélkül:** nem lenne ténylegesen a
  téma része, és megkerülhető második stílusforrást hozna létre.
- **A text scale befagyasztása vagy felülírása:** clippinget rejtene el az
  accessibility igény figyelmen kívül hagyásával.
- **Ellipszis a chord hero címkén:** a Stage Mode legfontosabb zenei adatából
  veszítene információt.
- **Külön value/unit Text widget:** értelmetlen sortörést engedne.
